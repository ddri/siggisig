import CoreAudio
import SwiftUI

@MainActor
@Observable
final class RouterViewModel {
    var availableApps: [CaptureApp] = []
    var routerState = RouterState()
    var isSetupComplete = false
    var errorMessage: String?
    var meterLevels: [pid_t: MeterLevels] = [:]
    var pendingRoutes: [SavedRoute] = []

    private let engine = AudioCaptureEngine()
    private let sessionStore = SessionStore()
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
        do {
            try engine.setup()
        } catch {
            errorMessage = error.localizedDescription
        }
        observeWorkspace()
        observeAudioDevices()
        restoreSession()
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
                meterLevels.removeValue(forKey: app.id)
                scheduleSave()
            } else {
                do {
                    let slot = try await engine.startCapture(for: app)
                    routerState.addRoute(
                        appName: app.name,
                        bundleID: app.bundleIdentifier,
                        pid: app.id,
                        slot: slot
                    )
                    let pid = app.id
                    engine.installMeterTap(for: app) { [weak self] levels in
                        Task { @MainActor in
                            self?.meterLevels[pid] = levels
                        }
                    }
                    scheduleSave()
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
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
        let used = engine.usedSlots
        return (0..<8).filter { !used.contains($0) }
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

    private func saveSession() {
        var savedRoutes = routerState.routes.map { route in
            SavedRoute(
                bundleID: route.bundleID ?? "",
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

    private func restoreSession() {
        guard let savedRoutes = try? sessionStore.load(), !savedRoutes.isEmpty else { return }

        let runningApps = AppDiscovery.runningApps()

        for saved in savedRoutes {
            if let app = runningApps.first(where: { $0.bundleIdentifier == saved.bundleID }) {
                Task {
                    do {
                        let slot = try await engine.startCapture(for: app, preferredSlot: saved.channelSlot)
                        routerState.addRoute(
                            appName: app.name,
                            bundleID: app.bundleIdentifier,
                            pid: app.id,
                            slot: slot
                        )
                        routerState.setVolume(pid: app.id, volume: saved.volume)
                        engine.setVolume(for: app, db: saved.volume)
                        routerState.setPan(pid: app.id, pan: saved.pan)
                        engine.setPan(for: app, pan: saved.pan)
                        let pid = app.id
                        engine.installMeterTap(for: app) { [weak self] levels in
                            Task { @MainActor in
                                self?.meterLevels[pid] = levels
                            }
                        }
                    } catch {
                        // If restore fails for one app, continue with others
                    }
                }
            } else {
                pendingRoutes.append(saved)
            }
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
                self?.routerState.removeRoute(pid: pid)
                self?.meterLevels.removeValue(forKey: pid)
                self?.scheduleSave()
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
            let apps = AppDiscovery.runningApps()
            guard let app = apps.first(where: { $0.bundleIdentifier == bundleID }) else { return }
            do {
                let slot = try await engine.startCapture(for: app, preferredSlot: saved.channelSlot)
                routerState.addRoute(
                    appName: app.name,
                    bundleID: app.bundleIdentifier,
                    pid: app.id,
                    slot: slot
                )
                routerState.setVolume(pid: app.id, volume: saved.volume)
                engine.setVolume(for: app, db: saved.volume)
                routerState.setPan(pid: app.id, pan: saved.pan)
                engine.setPan(for: app, pan: saved.pan)
                let appPid = app.id
                engine.installMeterTap(for: app) { [weak self] levels in
                    Task { @MainActor in
                        self?.meterLevels[appPid] = levels
                    }
                }
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
