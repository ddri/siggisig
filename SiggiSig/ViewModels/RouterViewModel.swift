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
