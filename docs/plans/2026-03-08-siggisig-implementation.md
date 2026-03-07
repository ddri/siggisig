# SiggiSig Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS app that captures per-app audio via ScreenCaptureKit and routes each app to separate stereo pairs on BlackHole 16ch for DAW recording.

**Architecture:** ScreenCaptureKit captures per-app audio as CMSampleBuffers, which are converted to AVAudioPCMBuffers and fed into AVAudioEngine. The engine outputs to BlackHole 16ch with channel mapping so each app gets its own stereo pair. SwiftUI provides the UI.

**Tech Stack:** Swift, SwiftUI, ScreenCaptureKit, AVAudioEngine, CoreAudio. macOS 15+. Xcode project with Swift Package Manager.

---

### Task 1: Create Xcode Project Structure

**Files:**
- Create: `SiggiSig/SiggiSigApp.swift`
- Create: `SiggiSig/ContentView.swift`
- Create: `SiggiSig/Info.plist`
- Create: `SiggiSig/SiggiSig.entitlements`
- Create: `Package.swift`

**Step 1: Create the Swift Package with executable target**

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiggiSig",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SiggiSig",
            path: "SiggiSig"
        ),
        .testTarget(
            name: "SiggiSigTests",
            dependencies: ["SiggiSig"],
            path: "Tests"
        )
    ]
)
```

**Step 2: Create the app entry point**

```swift
// SiggiSig/SiggiSigApp.swift
import SwiftUI

@main
struct SiggiSigApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

```swift
// SiggiSig/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("SiggiSig")
            .frame(width: 600, height: 400)
    }
}
```

**Step 3: Create entitlements for audio and screen capture**

```xml
<!-- SiggiSig/SiggiSig.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

```xml
<!-- SiggiSig/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSScreenCaptureUsageDescription</key>
    <string>SiggiSig needs screen capture permission to capture audio from individual applications.</string>
</dict>
</plist>
```

**Step 4: Build and run to verify**

Run: `cd /Users/david/GitHub/siggisig && swift build`
Expected: Successful build

**Step 5: Commit**

```bash
git add Package.swift SiggiSig/ Tests/
git commit -m "feat: create Swift package project structure"
```

---

### Task 2: Audio Device Discovery

**Files:**
- Create: `SiggiSig/Audio/AudioDeviceManager.swift`
- Create: `Tests/AudioDeviceManagerTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/AudioDeviceManagerTests.swift
import Testing
@testable import SiggiSig

@Test func testListAudioDevices() {
    let devices = AudioDeviceManager.listOutputDevices()
    #expect(!devices.isEmpty, "Should find at least one output device")
}

@Test func testDeviceHasNameAndID() {
    let devices = AudioDeviceManager.listOutputDevices()
    guard let first = devices.first else {
        Issue.record("No devices found")
        return
    }
    #expect(!first.name.isEmpty)
    #expect(first.id != 0)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AudioDeviceManagerTests`
Expected: FAIL — `AudioDeviceManager` not found

**Step 3: Implement AudioDeviceManager**

```swift
// SiggiSig/Audio/AudioDeviceManager.swift
import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let channelCount: Int
}

enum AudioDeviceManager {
    static func listOutputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard let name = getDeviceName(deviceID),
                  let channelCount = getOutputChannelCount(deviceID),
                  channelCount > 0 else { return nil }
            return AudioDevice(id: deviceID, name: name, channelCount: channelCount)
        }
    }

    static func findDevice(named targetName: String) -> AudioDevice? {
        listOutputDevices().first { $0.name.contains(targetName) }
    }

    private static func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &name
        ) == noErr else { return nil }
        return name as String
    }

    private static func getOutputChannelCount(_ deviceID: AudioDeviceID) -> Int? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID, &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return nil }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer
        ) == noErr else { return nil }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter AudioDeviceManagerTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SiggiSig/Audio/AudioDeviceManager.swift Tests/AudioDeviceManagerTests.swift
git commit -m "feat: add CoreAudio device discovery"
```

---

### Task 3: App Process Discovery

**Files:**
- Create: `SiggiSig/App/AppDiscovery.swift`
- Create: `Tests/AppDiscoveryTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/AppDiscoveryTests.swift
import Testing
@testable import SiggiSig

@Test func testDiscoverRunningApps() {
    let apps = AppDiscovery.runningApps()
    #expect(!apps.isEmpty, "Should find running GUI apps")
}

@Test func testAppsHaveBundleIdentifier() {
    let apps = AppDiscovery.runningApps()
    for app in apps {
        #expect(app.bundleIdentifier != nil, "\(app.name) should have a bundle ID")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppDiscoveryTests`
Expected: FAIL — `AppDiscovery` not found

**Step 3: Implement AppDiscovery**

```swift
// SiggiSig/App/AppDiscovery.swift
import AppKit

struct CaptureApp: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CaptureApp, rhs: CaptureApp) -> Bool {
        lhs.id == rhs.id
    }
}

enum AppDiscovery {
    static func runningApps() -> [CaptureApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> CaptureApp? in
                guard let name = app.localizedName else { return nil }
                return CaptureApp(
                    id: app.processIdentifier,
                    name: name,
                    bundleIdentifier: app.bundleIdentifier,
                    icon: app.icon
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppDiscoveryTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SiggiSig/App/AppDiscovery.swift Tests/AppDiscoveryTests.swift
git commit -m "feat: add app process discovery"
```

---

### Task 4: Audio Capture Engine (ScreenCaptureKit → AVAudioEngine)

**Files:**
- Create: `SiggiSig/Audio/AudioCaptureEngine.swift`
- Create: `SiggiSig/Audio/AppAudioStream.swift`

This is the core of the app. Cannot be fully unit tested (requires real audio devices + permissions), so we write it with manual test steps.

**Step 1: Implement AppAudioStream (wraps SCStream for one app)**

```swift
// SiggiSig/Audio/AppAudioStream.swift
import ScreenCaptureKit
import AVFoundation
import CoreMedia

final class AppAudioStream: NSObject, SCStreamOutput {
    let app: CaptureApp
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioFormat) -> Void)?

    private var stream: SCStream?

    init(app: CaptureApp) {
        self.app = app
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let scApp = content.applications.first(where: { $0.processID == app.id }) else {
            throw AudioCaptureError.appNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: content.windows.first!)
        // Use app-level filter for audio
        let appFilter = SCContentFilter(
            .init(display: content.displays.first!, excludingApplications: [], exceptingWindows: []),
            including: [scApp],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // Minimize video overhead — we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        stream = SCStream(filter: appFilter, configuration: config, delegate: nil)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream?.startCapture()
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = formatDesc.audioStreamBasicDescription else { return }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: asbd.mSampleRate,
            channels: asbd.mChannelsPerFrame
        ) else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return }

        onAudioBuffer?(pcmBuffer, format)
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case appNotFound
    case blackHoleNotFound
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .appNotFound: "Application not found for capture"
        case .blackHoleNotFound: "BlackHole 16ch not found. Please install it."
        case .engineStartFailed: "Failed to start audio engine"
        }
    }
}
```

**Step 2: Implement AudioCaptureEngine (manages AVAudioEngine + routing)**

```swift
// SiggiSig/Audio/AudioCaptureEngine.swift
import AVFoundation
import CoreAudio

final class AudioCaptureEngine {
    private let engine = AVAudioEngine()
    private var activeStreams: [pid_t: ManagedStream] = [:]
    private let maxStereoSlots = 8  // BlackHole 16ch = 8 stereo pairs

    private struct ManagedStream {
        let appStream: AppAudioStream
        let playerNode: AVAudioPlayerNode
        let channelSlot: Int  // 0-7, maps to stereo pair
    }

    var blackHoleDevice: AudioDevice? {
        AudioDeviceManager.findDevice(named: "BlackHole 16ch")
    }

    func setup() throws {
        guard let device = blackHoleDevice else {
            throw AudioCaptureError.blackHoleNotFound
        }

        // Set AVAudioEngine output to BlackHole
        let outputNode = engine.outputNode
        guard let audioUnit = outputNode.audioUnit else {
            throw AudioCaptureError.engineStartFailed
        }

        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioCaptureError.engineStartFailed
        }

        engine.prepare()
        try engine.start()
    }

    func startCapture(for app: CaptureApp) async throws -> Int {
        guard activeStreams[app.id] == nil else { return activeStreams[app.id]!.channelSlot }

        guard let slot = nextFreeSlot() else {
            throw AudioCaptureError.engineStartFailed
        }

        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)

        // Connect player to output with channel mapping
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        // Set channel map: route to the correct stereo pair
        let channelMap = makeChannelMap(slot: slot, totalChannels: 16)
        playerNode.auAudioUnit.channelMap = channelMap

        playerNode.play()

        let appStream = AppAudioStream(app: app)
        appStream.onAudioBuffer = { [weak self] buffer, format in
            self?.scheduleBuffer(buffer, format: format, on: playerNode)
        }

        try await appStream.start()

        activeStreams[app.id] = ManagedStream(
            appStream: appStream,
            playerNode: playerNode,
            channelSlot: slot
        )

        return slot
    }

    func stopCapture(for app: CaptureApp) async {
        guard let managed = activeStreams.removeValue(forKey: app.id) else { return }
        await managed.appStream.stop()
        managed.playerNode.stop()
        engine.detach(managed.playerNode)
    }

    func stopAll() async {
        for (_, managed) in activeStreams {
            await managed.appStream.stop()
            managed.playerNode.stop()
            engine.detach(managed.playerNode)
        }
        activeStreams.removeAll()
        engine.stop()
    }

    func isCapturing(_ app: CaptureApp) -> Bool {
        activeStreams[app.id] != nil
    }

    func channelSlot(for app: CaptureApp) -> Int? {
        activeStreams[app.id]?.channelSlot
    }

    var activeAppCount: Int { activeStreams.count }

    // MARK: - Private

    private func nextFreeSlot() -> Int? {
        let usedSlots = Set(activeStreams.values.map(\.channelSlot))
        return (0..<maxStereoSlots).first { !usedSlots.contains($0) }
    }

    private func makeChannelMap(slot: Int, totalChannels: Int) -> [NSNumber] {
        // Map stereo input (ch 0,1) to output channels (slot*2, slot*2+1)
        // -1 means "no audio on this channel"
        var map = [NSNumber](repeating: -1, count: totalChannels)
        map[slot * 2] = 0      // left channel
        map[slot * 2 + 1] = 1  // right channel
        return map
    }

    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat, on playerNode: AVAudioPlayerNode) {
        // Convert format if needed
        let outputFormat = playerNode.outputFormat(forBus: 0)
        if format == outputFormat {
            playerNode.scheduleBuffer(buffer)
        } else if let converter = AVAudioConverter(from: format, to: outputFormat) {
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: buffer.frameCapacity
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error == nil {
                playerNode.scheduleBuffer(convertedBuffer)
            }
        }
    }
}
```

**Step 3: Build to verify compilation**

Run: `swift build`
Expected: Successful build

**Step 4: Commit**

```bash
git add SiggiSig/Audio/AppAudioStream.swift SiggiSig/Audio/AudioCaptureEngine.swift
git commit -m "feat: add audio capture engine with ScreenCaptureKit and AVAudioEngine"
```

---

### Task 5: Router State Model

**Files:**
- Create: `SiggiSig/State/RouterState.swift`
- Create: `Tests/RouterStateTests.swift`

**Step 1: Write the failing tests**

```swift
// Tests/RouterStateTests.swift
import Testing
@testable import SiggiSig

@Test func testInitialStateEmpty() {
    let state = RouterState()
    #expect(state.routes.isEmpty)
    #expect(state.availableSlots == 8)
}

@Test func testAddRoute() {
    var state = RouterState()
    state.addRoute(appName: "Chrome", bundleID: "com.google.Chrome", pid: 123, slot: 0)
    #expect(state.routes.count == 1)
    #expect(state.routes[0].appName == "Chrome")
    #expect(state.routes[0].channelPair == "Ch 1-2")
    #expect(state.availableSlots == 7)
}

@Test func testRemoveRoute() {
    var state = RouterState()
    state.addRoute(appName: "Chrome", bundleID: "com.google.Chrome", pid: 123, slot: 0)
    state.removeRoute(pid: 123)
    #expect(state.routes.isEmpty)
    #expect(state.availableSlots == 8)
}

@Test func testChannelPairLabels() {
    #expect(Route.channelPairLabel(for: 0) == "Ch 1-2")
    #expect(Route.channelPairLabel(for: 1) == "Ch 3-4")
    #expect(Route.channelPairLabel(for: 7) == "Ch 15-16")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter RouterStateTests`
Expected: FAIL

**Step 3: Implement RouterState**

```swift
// SiggiSig/State/RouterState.swift
import Foundation

struct Route: Identifiable, Equatable {
    let id = UUID()
    let appName: String
    let bundleID: String?
    let pid: pid_t
    let slot: Int

    var channelPair: String { Self.channelPairLabel(for: slot) }

    static func channelPairLabel(for slot: Int) -> String {
        let first = slot * 2 + 1
        let second = slot * 2 + 2
        return "Ch \(first)-\(second)"
    }
}

struct RouterState {
    private(set) var routes: [Route] = []
    let maxSlots = 8

    var availableSlots: Int { maxSlots - routes.count }

    var statusText: String {
        if routes.isEmpty {
            return "No apps routed"
        }
        return "Routing \(routes.count) app\(routes.count == 1 ? "" : "s") to BlackHole"
    }

    mutating func addRoute(appName: String, bundleID: String?, pid: pid_t, slot: Int) {
        let route = Route(appName: appName, bundleID: bundleID, pid: pid, slot: slot)
        routes.append(route)
    }

    mutating func removeRoute(pid: pid_t) {
        routes.removeAll { $0.pid == pid }
    }

    func slotFor(pid: pid_t) -> Int? {
        routes.first { $0.pid == pid }?.slot
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter RouterStateTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SiggiSig/State/RouterState.swift Tests/RouterStateTests.swift
git commit -m "feat: add router state model with channel pair assignment"
```

---

### Task 6: Setup Wizard View

**Files:**
- Create: `SiggiSig/Views/SetupWizardView.swift`

**Step 1: Implement the setup wizard**

```swift
// SiggiSig/Views/SetupWizardView.swift
import SwiftUI
import ScreenCaptureKit

struct SetupWizardView: View {
    @Binding var isComplete: Bool
    @State private var blackHoleDetected = false
    @State private var permissionGranted = false
    @State private var checking = false
    @State private var step = 1

    var body: some View {
        VStack(spacing: 24) {
            Text("SiggiSig Setup")
                .font(.title)
                .bold()

            if step == 1 {
                blackHoleStep
            } else {
                permissionStep
            }
        }
        .padding(40)
        .frame(width: 480)
        .task { await checkBlackHole() }
    }

    private var blackHoleStep: some View {
        VStack(spacing: 16) {
            Image(systemName: blackHoleDetected ? "checkmark.circle.fill" : "speaker.wave.2.circle")
                .font(.system(size: 48))
                .foregroundColor(blackHoleDetected ? .green : .secondary)

            Text("BlackHole 16ch")
                .font(.headline)

            if blackHoleDetected {
                Text("Detected!")
                    .foregroundColor(.green)
                Button("Next") { step = 2 }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("BlackHole 16ch is required for audio routing.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Link("Download BlackHole", destination: URL(string: "https://existential.audio/blackhole/")!)
                        .buttonStyle(.borderedProminent)

                    Button("Refresh") {
                        Task { await checkBlackHole() }
                    }
                    .disabled(checking)
                }
            }
        }
    }

    private var permissionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: permissionGranted ? "checkmark.circle.fill" : "rectangle.dashed.badge.record")
                .font(.system(size: 48))
                .foregroundColor(permissionGranted ? .green : .secondary)

            Text("Screen Recording Permission")
                .font(.headline)

            Text("SiggiSig needs this permission to capture audio from individual apps.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if permissionGranted {
                Text("Permission granted!")
                    .foregroundColor(.green)
                Button("Get Started") { isComplete = true }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Request Permission") {
                    Task { await requestPermission() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func checkBlackHole() async {
        checking = true
        blackHoleDetected = AudioDeviceManager.findDevice(named: "BlackHole 16ch") != nil
        checking = false
    }

    private func requestPermission() async {
        do {
            // Requesting shareable content triggers the permission prompt
            _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            permissionGranted = true
        } catch {
            permissionGranted = false
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: PASS

**Step 3: Commit**

```bash
git add SiggiSig/Views/SetupWizardView.swift
git commit -m "feat: add first-launch setup wizard for BlackHole and permissions"
```

---

### Task 7: Main UI — App Picker and Active Routes

**Files:**
- Create: `SiggiSig/Views/AppListView.swift`
- Create: `SiggiSig/Views/ActiveRoutesView.swift`
- Create: `SiggiSig/Views/StatusBarView.swift`
- Create: `SiggiSig/ViewModels/RouterViewModel.swift`
- Modify: `SiggiSig/ContentView.swift`

**Step 1: Implement the ViewModel**

```swift
// SiggiSig/ViewModels/RouterViewModel.swift
import SwiftUI

@MainActor
@Observable
final class RouterViewModel {
    var availableApps: [CaptureApp] = []
    var routerState = RouterState()
    var isSetupComplete = false
    var errorMessage: String?

    private let engine = AudioCaptureEngine()
    private var refreshTimer: Timer?

    var isBlackHoleAvailable: Bool {
        engine.blackHoleDevice != nil
    }

    func setup() {
        do {
            try engine.setup()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshApps() {
        availableApps = AppDiscovery.runningApps()
    }

    func startRefreshTimer() {
        refreshApps()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshApps()
                self?.cleanupDeadProcesses()
            }
        }
    }

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func toggleCapture(for app: CaptureApp) {
        Task {
            if engine.isCapturing(app) {
                await engine.stopCapture(for: app)
                routerState.removeRoute(pid: app.id)
            } else {
                do {
                    let slot = try await engine.startCapture(for: app)
                    routerState.addRoute(
                        appName: app.name,
                        bundleID: app.bundleIdentifier,
                        pid: app.id,
                        slot: slot
                    )
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func isRouted(_ app: CaptureApp) -> Bool {
        engine.isCapturing(app)
    }

    func channelLabel(for app: CaptureApp) -> String? {
        guard let slot = routerState.slotFor(pid: app.id) else { return nil }
        return Route.channelPairLabel(for: slot)
    }

    private func cleanupDeadProcesses() {
        let livePIDs = Set(availableApps.map(\.id))
        let deadRoutes = routerState.routes.filter { !livePIDs.contains($0.pid) }
        for route in deadRoutes {
            let fakeApp = CaptureApp(id: route.pid, name: route.appName, bundleIdentifier: route.bundleID, icon: nil)
            Task { await engine.stopCapture(for: fakeApp) }
            routerState.removeRoute(pid: route.pid)
        }
    }
}
```

**Step 2: Implement the views**

```swift
// SiggiSig/Views/AppListView.swift
import SwiftUI

struct AppListView: View {
    let apps: [CaptureApp]
    let isRouted: (CaptureApp) -> Bool
    let channelLabel: (CaptureApp) -> String?
    let onToggle: (CaptureApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Available Apps")
                .font(.headline)
                .padding(.bottom, 4)

            List(apps) { app in
                HStack {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    Text(app.name)
                        .lineLimit(1)
                    Spacer()
                    if let label = channelLabel(app) {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Circle()
                        .fill(isRouted(app) ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                }
                .contentShape(Rectangle())
                .onTapGesture { onToggle(app) }
            }
        }
    }
}
```

```swift
// SiggiSig/Views/ActiveRoutesView.swift
import SwiftUI

struct ActiveRoutesView: View {
    let routes: [Route]
    let maxSlots: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active Routes")
                .font(.headline)
                .padding(.bottom, 4)

            List {
                ForEach(0..<maxSlots, id: \.self) { slot in
                    if let route = routes.first(where: { $0.slot == slot }) {
                        HStack {
                            Text(route.appName)
                                .lineLimit(1)
                            Spacer()
                            Text(route.channelPair)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack {
                            Text(Route.channelPairLabel(for: slot))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("free")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}
```

```swift
// SiggiSig/Views/StatusBarView.swift
import SwiftUI

struct StatusBarView: View {
    let statusText: String
    let errorMessage: String?

    var body: some View {
        HStack {
            if let error = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .foregroundColor(.orange)
                    .font(.caption)
            } else {
                Image(systemName: "waveform")
                    .foregroundColor(.secondary)
                Text(statusText)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
```

**Step 3: Update ContentView to wire it all together**

```swift
// SiggiSig/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var viewModel = RouterViewModel()

    var body: some View {
        Group {
            if viewModel.isSetupComplete {
                mainView
            } else {
                SetupWizardView(isComplete: $viewModel.isSetupComplete)
            }
        }
        .onChange(of: viewModel.isSetupComplete) { _, complete in
            if complete {
                viewModel.setup()
                viewModel.startRefreshTimer()
            }
        }
        .frame(width: 600, height: 450)
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AppListView(
                    apps: viewModel.availableApps,
                    isRouted: { viewModel.isRouted($0) },
                    channelLabel: { viewModel.channelLabel(for: $0) },
                    onToggle: { viewModel.toggleCapture(for: $0) }
                )
                .frame(maxWidth: .infinity)

                Divider()

                ActiveRoutesView(
                    routes: viewModel.routerState.routes,
                    maxSlots: viewModel.routerState.maxSlots
                )
                .frame(maxWidth: .infinity)
            }

            Divider()

            StatusBarView(
                statusText: viewModel.routerState.statusText,
                errorMessage: viewModel.errorMessage
            )
        }
    }
}
```

**Step 4: Build to verify**

Run: `swift build`
Expected: PASS

**Step 5: Commit**

```bash
git add SiggiSig/Views/ SiggiSig/ViewModels/ SiggiSig/ContentView.swift
git commit -m "feat: add main UI with app picker, active routes, and status bar"
```

---

### Task 8: App Lifecycle Handling

**Files:**
- Modify: `SiggiSig/ViewModels/RouterViewModel.swift`

**Step 1: Add workspace notification observers for app termination and BlackHole disconnect**

Add to `RouterViewModel.setup()`:

```swift
// Add to RouterViewModel
private func observeWorkspace() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification,
        object: nil,
        queue: .main
    ) { [weak self] notification in
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        self?.routerState.removeRoute(pid: pid)
    }
}

private func observeAudioDevices() {
    // Register for device list changes
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectAddPropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        .main
    ) { [weak self] _, _ in
        if self?.isBlackHoleAvailable == false {
            self?.errorMessage = "BlackHole 16ch disconnected"
        }
    }
}
```

**Step 2: Call observers from setup()**

Add `observeWorkspace()` and `observeAudioDevices()` calls in `setup()`.

**Step 3: Build and verify**

Run: `swift build`
Expected: PASS

**Step 4: Commit**

```bash
git add SiggiSig/ViewModels/RouterViewModel.swift
git commit -m "feat: add app termination and device disconnect detection"
```

---

### Task 9: Integration Testing (Manual)

**Files:**
- Create: `docs/testing-guide.md`

**Step 1: Write the manual test guide**

```markdown
# SiggiSig Manual Testing Guide

## Prerequisites
- BlackHole 16ch installed
- Ableton Live (or any DAW)

## Test 1: Setup Wizard
1. Delete app preferences (fresh state)
2. Launch SiggiSig
3. Verify BlackHole detection shows green checkmark
4. Verify Screen Recording permission prompt appears
5. Grant permission, verify "Get Started" button appears

## Test 2: App Discovery
1. Open Chrome and Safari
2. Verify both appear in the app list
3. Close Safari, verify it disappears within 3 seconds

## Test 3: Basic Audio Routing
1. Open Chrome, play a YouTube video
2. In SiggiSig, click Chrome in the app list
3. Verify it appears in Active Routes as "Ch 1-2"
4. In Ableton, create an audio track with input "BlackHole 16ch 1-2"
5. Arm the track, verify audio levels show YouTube audio
6. Record, verify playback contains the audio

## Test 4: Multi-App Routing
1. Route Chrome → Ch 1-2
2. Route Spotify → Ch 3-4
3. In Ableton, create two tracks on Ch 1-2 and Ch 3-4
4. Verify each track receives only its respective app audio

## Test 5: App Quit Handling
1. Route Chrome → Ch 1-2
2. Quit Chrome
3. Verify route is removed from Active Routes
4. Verify Ch 1-2 shows as "free"

## Test 6: BlackHole Disconnect
1. Route an app
2. Uninstall/disable BlackHole (or change audio device settings)
3. Verify error message appears in status bar
```

**Step 2: Commit**

```bash
git add docs/testing-guide.md
git commit -m "docs: add manual integration testing guide"
```

---

### Task 10: Final Polish and README Update

**Files:**
- Modify: `README.md`

**Step 1: Update README with build/run instructions**

```markdown
# SiggiSig

A macOS audio routing app that captures per-app audio and pipes it to virtual audio devices for use in DAWs.

Built with Swift, ScreenCaptureKit, and CoreAudio.

## Requirements

- macOS 15.0+ (Sequoia)
- [BlackHole 16ch](https://existential.audio/blackhole/)
- Xcode 16+

## Build & Run

```bash
swift build
swift run
```

Or open in Xcode:
```bash
open Package.swift
```

## Usage

1. Launch SiggiSig
2. Complete the setup wizard (detects BlackHole, requests permissions)
3. Click an app in the left panel to route its audio
4. Each app gets assigned a stereo pair (Ch 1-2, Ch 3-4, etc.)
5. In your DAW, set input to the corresponding BlackHole channel pair
6. Record!

## Architecture

- **ScreenCaptureKit** captures per-app audio as `CMSampleBuffer`
- **AVAudioEngine** converts and routes audio buffers
- **BlackHole 16ch** provides the virtual audio device (up to 8 stereo apps)
- **SwiftUI** for the routing interface
```

**Step 2: Commit and push**

```bash
git add README.md
git commit -m "docs: update README with build and usage instructions"
git push
```
