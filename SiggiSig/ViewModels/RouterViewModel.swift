import CoreAudio
import SwiftUI

@MainActor
@Observable
final class RouterViewModel {
    var availableApps: [CaptureApp] = []
    var routerState = RouterState()
    private static let setupCompleteKey = "hasCompletedSetup"
    private var isInitialized = false
    private(set) var isSetupComplete: Bool
    /// Wizard reopened from the Help menu. Not persisted, so quitting mid-wizard
    /// leaves the completed setup intact for the next launch.
    var isRerunningSetup = false
    var showsSetupWizard: Bool { !isSetupComplete || isRerunningSetup }
    var errorMessage: String?
    var meterLevels: [pid_t: MeterLevels] = [:]
    var pendingRoutes: [SavedRoute] = []

    private let engine: AudioCaptureEngine
    private let sessionStore: SessionStore
    private let runningApps: () -> [CaptureApp]
    /// Apps with a connect or disconnect in progress; further clicks on them are ignored.
    private var togglesInFlight: Set<pid_t> = []
    private var hasRestoredSession = false

    init(
        engine: AudioCaptureEngine? = nil,
        sessionStore: SessionStore = SessionStore(),
        runningApps: @escaping () -> [CaptureApp] = AppDiscovery.runningApps
    ) {
        self.engine = engine ?? AudioCaptureEngine()
        self.sessionStore = sessionStore
        self.runningApps = runningApps
        self.isSetupComplete = UserDefaults.standard.bool(forKey: Self.setupCompleteKey)
    }

    /// Starts the engine, observers and refresh timer if setup is complete.
    /// Kept out of init so creating a view model has no side effects.
    func start() {
        // Show the wizard again if BlackHole went missing since setup was completed.
        if isSetupComplete && AudioDeviceManager.findDevice(named: "BlackHole 16ch") == nil {
            isSetupComplete = false
        }
        startIfReady()
    }

    func completeSetup() {
        isRerunningSetup = false
        isSetupComplete = true
        UserDefaults.standard.set(true, forKey: Self.setupCompleteKey)
        startIfReady()
    }

    private func startIfReady() {
        guard isSetupComplete, !isInitialized else { return }
        isInitialized = true
        setup()
        startRefreshTimer()
    }

    private var saveTimer: Timer?
    private var refreshTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var audioDevicePropertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var audioDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    deinit {
        MainActor.assumeIsolated {
            saveTimer?.invalidate()
            refreshTimer?.invalidate()
            if let observer = workspaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            if let observer = launchObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            if let block = audioDeviceListenerBlock {
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject),
                    &audioDevicePropertyAddress,
                    .main,
                    block
                )
            }
        }
    }

    var isBlackHoleAvailable: Bool {
        engine.blackHoleDevice != nil
    }

    func setup() {
        setupEngine()
        observeWorkspace()
        observeAudioDevices()
    }

    /// Restores the saved session once the engine is running (first try or the retry).
    private func setupEngine() {
        do {
            try engine.setup()
            errorMessage = nil
            Task { await restoreSession() }
        } catch {
            errorMessage = "Failed to start audio engine"
            // Retry once after a short delay — BlackHole may not be ready yet
            Task {
                try? await Task.sleep(for: .seconds(1))
                do {
                    try engine.setup()
                    errorMessage = nil
                    await restoreSession()
                } catch {
                    errorMessage = "Failed to start audio engine"
                }
            }
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
        Task { await toggle(app) }
    }

    func toggle(_ app: CaptureApp) async {
        guard !togglesInFlight.contains(app.id) else { return }
        togglesInFlight.insert(app.id)
        defer { togglesInFlight.remove(app.id) }

        if engine.isCapturing(app) {
            await disconnect(pid: app.id)
            scheduleSave()
        } else {
            do {
                try await connect(app)
                errorMessage = nil
                scheduleSave()
            } catch AudioCaptureError.alreadyStarting {
                // Session restore or auto-connect is already bringing this app up.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func appTerminated(pid: pid_t) async {
        await disconnect(pid: pid)
        scheduleSave()
    }

    /// Starts capturing `app` and adds its route, applying a saved route's slot, volume and pan.
    private func connect(_ app: CaptureApp, saved: SavedRoute? = nil) async throws {
        let slot = try await engine.startCapture(
            for: app,
            preferredSlot: saved?.channelSlot,
            reserved: Set(pendingRoutes.map(\.channelSlot))
        )
        guard routerState.slotFor(pid: app.id) == nil else { return }
        routerState.addRoute(appName: app.name, bundleID: app.bundleIdentifier, pid: app.id, slot: slot)
        if let saved {
            routerState.setVolume(pid: app.id, volume: saved.volume)
            engine.setVolume(for: app, db: saved.volume)
            routerState.setPan(pid: app.id, pan: saved.pan)
            engine.setPan(for: app, pan: saved.pan)
        }
        let pid = app.id
        engine.installMeterTap(for: app) { [weak self] levels in
            Task { @MainActor in
                self?.meterLevels[pid] = levels
            }
        }
    }

    private func disconnect(pid: pid_t) async {
        await engine.stopCapture(pid: pid)
        routerState.removeRoute(pid: pid)
        meterLevels.removeValue(forKey: pid)
    }

    func setVolume(for pid: pid_t, db: Float) {
        routerState.setVolume(pid: pid, volume: db)
        if let route = routerState.routes.first(where: { $0.pid == pid }) {
            let fakeApp = CaptureApp(id: pid, name: route.appName, bundleIdentifier: route.bundleID, icon: nil)
            engine.setVolume(for: fakeApp, db: db)
        }
        scheduleSave()
    }

    func setPan(for pid: pid_t, pan: Float) {
        routerState.setPan(pid: pid, pan: pan)
        if let route = routerState.routes.first(where: { $0.pid == pid }) {
            let fakeApp = CaptureApp(id: pid, name: route.appName, bundleIdentifier: route.bundleID, icon: nil)
            engine.setPan(for: fakeApp, pan: pan)
        }
        scheduleSave()
    }

    func reassignChannel(pid: pid_t, to newSlot: Int) {
        guard let route = routerState.routes.first(where: { $0.pid == pid }) else { return }
        let fakeApp = CaptureApp(id: pid, name: route.appName, bundleIdentifier: route.bundleID, icon: nil)
        engine.reassignChannel(for: fakeApp, to: newSlot)
        routerState.reassignSlot(pid: pid, to: newSlot)
        scheduleSave()
    }

    var availableSlots: [Int] {
        // Slots saved for apps that aren't running are held for them.
        let used = engine.usedSlots.union(pendingRoutes.map(\.channelSlot))
        return (0..<AudioCaptureEngine.maxStereoSlots).filter { !used.contains($0) }
    }

    func isRouted(_ app: CaptureApp) -> Bool {
        engine.isCapturing(app)
    }

    func channelLabel(for app: CaptureApp) -> String? {
        guard let slot = routerState.slotFor(pid: app.id) else { return nil }
        return Route.channelPairLabel(for: slot)
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveSession()
            }
        }
    }

    /// Apps without a bundle ID aren't saved: there's no way to match them on the next launch.
    func saveSession() {
        var savedRoutes = routerState.routes.compactMap { route -> SavedRoute? in
            guard let bundleID = route.bundleID, !bundleID.isEmpty else { return nil }
            return SavedRoute(
                bundleID: bundleID,
                appName: route.appName,
                channelSlot: route.slot,
                volume: route.volume,
                pan: route.pan
            )
        }
        savedRoutes.append(contentsOf: pendingRoutes)
        do {
            try sessionStore.save(routes: savedRoutes)
        } catch {
            // Session save failures are non-fatal, don't show to user
        }
    }

    /// Runs once per launch. Saved apps that aren't running become pending (holding their
    /// slots); running ones are reconnected one at a time so they can't race for slots.
    func restoreSession() async {
        guard !hasRestoredSession else { return }
        hasRestoredSession = true
        guard let savedRoutes = try? sessionStore.load(), !savedRoutes.isEmpty else { return }

        let running = runningApps()
        var toConnect: [(CaptureApp, SavedRoute)] = []
        for saved in savedRoutes where !saved.bundleID.isEmpty {
            if let app = running.first(where: { $0.bundleIdentifier == saved.bundleID }) {
                toConnect.append((app, saved))
            } else if !pendingRoutes.contains(where: { $0.bundleID == saved.bundleID }) {
                pendingRoutes.append(saved)
            }
        }
        for (app, saved) in toConnect {
            // If restore fails for one app, continue with others
            try? await connect(app, saved: saved)
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor in
                await self?.appTerminated(pid: pid)
            }
        }

        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let nsApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = nsApp.bundleIdentifier else { return }
            Task { @MainActor in
                self?.handleAppLaunched(bundleID: bundleID, pid: nsApp.processIdentifier)
            }
        }
    }

    private func handleAppLaunched(bundleID: String, pid: pid_t) {
        guard let pendingIndex = pendingRoutes.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        let saved = pendingRoutes.remove(at: pendingIndex)

        Task {
            try? await Task.sleep(for: .seconds(1))
            guard let app = runningApps().first(where: { $0.bundleIdentifier == bundleID }) else {
                pendingRoutes.append(saved)
                return
            }
            do {
                try await connect(app, saved: saved)
            } catch {
                pendingRoutes.append(saved)
            }
        }
    }

    private func observeAudioDevices() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                if self?.isBlackHoleAvailable == false {
                    self?.errorMessage = "BlackHole 16ch disconnected"
                }
            }
        }
        audioDeviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &audioDevicePropertyAddress,
            .main,
            block
        )
    }

    /// Backstop for missed quit notifications. Checks the engine's captures (not just the
    /// routes, so orphans are caught too) against the process table rather than the app
    /// list, which leaves out apps that drop to background-only mode while still running.
    private func cleanupDeadProcesses() {
        for pid in engine.activePIDs where !Self.isProcessAlive(pid) {
            Task { await appTerminated(pid: pid) }
        }
    }

    private static func isProcessAlive(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated
    }
}
