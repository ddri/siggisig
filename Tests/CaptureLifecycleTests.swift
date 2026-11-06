@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import SiggiSig

// Route lifecycle tests with a fake capture stream, so no ScreenCaptureKit,
// Screen Recording permission or BlackHole is needed.

/// Records what the engine does with its streams. Starts suspend briefly so
/// overlapping calls interleave the way a fast double-click does.
final class FakeStreams: @unchecked Sendable {
    var started = 0
    var stopped = 0
    var failStart = false

    @MainActor
    func factory() -> AudioCaptureEngine.StreamFactory {
        { [self] _, _ in FakeStream(owner: self) }
    }
}

final class FakeStream: AudioStreamSource, @unchecked Sendable {
    let owner: FakeStreams
    init(owner: FakeStreams) { self.owner = owner }

    func start() async throws {
        try await Task.sleep(for: .milliseconds(10))
        if owner.failStart { throw AudioCaptureError.appNotFound }
        owner.started += 1
    }

    func stop() async { owner.stopped += 1 }
}

private func app(_ pid: pid_t, bundleID: String? = nil) -> CaptureApp {
    CaptureApp(id: pid, name: "App \(pid)", bundleIdentifier: bundleID ?? "com.example.app\(pid)", icon: nil)
}

private func tempStore() throws -> SessionStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return SessionStore(directory: dir)
}

// MARK: - Engine

@Test @MainActor func testFailedStartFreesSlotAndNodes() async throws {
    let streams = FakeStreams()
    streams.failStart = true
    let engine = AudioCaptureEngine(makeStream: streams.factory())
    await #expect(throws: AudioCaptureError.self) { try await engine.startCapture(for: app(1)) }
    #expect(engine.usedSlots.isEmpty)
    #expect(!engine.isCapturing(app(1)))

    streams.failStart = false
    #expect(try await engine.startCapture(for: app(1)) == 0)
}

@Test @MainActor func testOverlappingStartsForSameAppStartOneStream() async throws {
    let streams = FakeStreams()
    let engine = AudioCaptureEngine(makeStream: streams.factory())
    // Either call may win; the other must be refused.
    async let first: Int? = try? engine.startCapture(for: app(1))
    async let second: Int? = try? engine.startCapture(for: app(1))
    let results = await [first, second]
    #expect(results.compactMap { $0 } == [0])
    #expect(streams.started == 1)
    #expect(engine.usedSlots == [0])
}

@Test @MainActor func testOverlappingStartsForDifferentAppsGetDifferentSlots() async throws {
    let engine = AudioCaptureEngine(makeStream: FakeStreams().factory())
    async let a = engine.startCapture(for: app(1))
    async let b = engine.startCapture(for: app(2))
    let slots = try await [a, b]
    #expect(Set(slots) == [0, 1])
}

@Test @MainActor func testNewRoutesAvoidReservedSlots() async throws {
    let engine = AudioCaptureEngine(makeStream: FakeStreams().factory())
    #expect(try await engine.startCapture(for: app(1), reserved: [0, 1]) == 2)
}

@Test @MainActor func testOutOfRangePreferredSlotFallsBack() async throws {
    let engine = AudioCaptureEngine(makeStream: FakeStreams().factory())
    #expect(try await engine.startCapture(for: app(1), preferredSlot: 12) == 0)
    #expect(try await engine.startCapture(for: app(2), preferredSlot: -1) == 1)
}

// MARK: - View model

@MainActor
private func makeViewModel(
    streams: FakeStreams = FakeStreams(),
    store: SessionStore? = nil,
    running: [CaptureApp] = []
) throws -> RouterViewModel {
    RouterViewModel(
        engine: AudioCaptureEngine(makeStream: streams.factory()),
        sessionStore: try store ?? tempStore(),
        runningApps: { running }
    )
}

@Test @MainActor func testQuittingRoutedAppStopsCaptureAndFreesSlot() async throws {
    let streams = FakeStreams()
    let vm = try makeViewModel(streams: streams)
    await vm.toggle(app(1))
    #expect(vm.routerState.routes.count == 1)

    await vm.appTerminated(pid: 1)
    #expect(vm.routerState.routes.isEmpty)
    #expect(vm.availableSlots.count == 8)
    #expect(streams.stopped == 1)
}

@Test @MainActor func testDoubleClickRoutesOnce() async throws {
    let streams = FakeStreams()
    let vm = try makeViewModel(streams: streams)
    async let first: Void = vm.toggle(app(1))
    async let second: Void = vm.toggle(app(1))
    _ = await (first, second)
    #expect(vm.routerState.routes.count == 1)
    #expect(streams.started == 1)
}

@Test @MainActor func testRestoreRunsOnlyOnce() async throws {
    let store = try tempStore()
    try store.save(routes: [SavedRoute(bundleID: "com.example.closed", appName: "Closed", channelSlot: 3, volume: 0)])
    let vm = try makeViewModel(store: store)
    await vm.restoreSession()
    await vm.restoreSession()
    #expect(vm.pendingRoutes.count == 1)
}

@Test @MainActor func testPendingRouteKeepsItsSlot() async throws {
    let store = try tempStore()
    try store.save(routes: [SavedRoute(bundleID: "com.example.closed", appName: "Closed", channelSlot: 0, volume: 0)])
    let vm = try makeViewModel(store: store)
    await vm.restoreSession()
    await vm.toggle(app(1))
    #expect(vm.routerState.slotFor(pid: 1) == 1)
    #expect(!vm.availableSlots.contains(0))
}

@Test @MainActor func testRestoreWithOutOfRangeSlotDoesNotCrash() async throws {
    let store = try tempStore()
    try store.save(routes: [SavedRoute(bundleID: "com.example.app1", appName: "App 1", channelSlot: 12, volume: -6)])
    let vm = try makeViewModel(store: store, running: [app(1)])
    await vm.restoreSession()
    #expect(vm.routerState.slotFor(pid: 1) == 0)
}

@Test @MainActor func testAppWithoutBundleIDIsNotSaved() async throws {
    let store = try tempStore()
    let vm = try makeViewModel(store: store)
    await vm.toggle(CaptureApp(id: 1, name: "No Bundle", bundleIdentifier: nil, icon: nil))
    await vm.toggle(app(2))
    vm.saveSession()
    #expect(try store.load().map(\.bundleID) == ["com.example.app2"])
}
