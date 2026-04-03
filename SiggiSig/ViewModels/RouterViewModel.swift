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

    private let engine = AudioCaptureEngine()
    private let sessionStore = SessionStore()
    private var saveTimer: Timer?
    private var refreshTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
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
        let savedRoutes = routerState.routes.map { route in
            SavedRoute(
                bundleID: route.bundleID ?? "",
                appName: route.appName,
                channelSlot: route.slot,
                volume: route.volume
            )
        }
        do {
            try sessionStore.save(routes: savedRoutes)
        } catch {
            // Session save failures are non-fatal, don't show to user
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
