import AppKit

struct CaptureApp: Identifiable, Hashable, @unchecked Sendable {
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
