import CoreGraphics
import SwiftUI

struct SetupWizardView: View {
    let onComplete: () -> Void
    @State private var blackHoleDetected = false
    @State private var hasPermission = false
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
        .padding(32)
        .frame(width: 480)
        .onAppear {
            checkPermission()
            checkBlackHole()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermission()
            checkBlackHole()
        }
    }

    private var blackHoleStep: some View {
        VStack(spacing: 16) {
            Image(
                systemName: blackHoleDetected
                    ? "checkmark.circle.fill" : "speaker.wave.2.circle"
            )
            .font(.largeTitle)
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
                    Link(
                        "Download BlackHole",
                        destination: URL(string: "https://existential.audio/blackhole/") ?? URL(string: "about:blank")!
                    )
                    .buttonStyle(.borderedProminent)

                    Button("Refresh") {
                        checkBlackHole()
                    }
                }
            }
        }
    }

    private var permissionStep: some View {
        VStack(spacing: 16) {
            Image(
                systemName: hasPermission
                    ? "checkmark.circle.fill"
                    : "rectangle.dashed.badge.record"
            )
            .font(.largeTitle)
            .foregroundColor(hasPermission ? .green : .secondary)

            Text("Screen Recording Permission")
                .font(.headline)

            if hasPermission {
                Text("Permission Granted!")
                    .foregroundColor(.green)
                    .fontWeight(.medium)

                Text("SiggiSig is ready to route audio from your apps.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .multilineTextAlignment(.center)

                Button("Get Started") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(
                    "SiggiSig needs Screen Recording permission to capture audio from individual apps.\n\nIn System Settings, make sure the toggle switch next to SiggiSig is turned ON (blue)."
                )
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

                Text("Just turned it on? If it still isn't detected, quit and reopen SiggiSig.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    Button("Open System Settings") {
                        openScreenRecordingSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 12) {
                        Button("Check Again") {
                            checkPermission()
                        }
                        .buttonStyle(.bordered)

                        Button("Continue Anyway") {
                            onComplete()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func checkPermission() {
        hasPermission = CGPreflightScreenCaptureAccess() || Self.canReadOtherWindowTitles()
    }

    /// CGPreflightScreenCaptureAccess() caches its answer for the life of the process, so a
    /// grant made in System Settings isn't seen until relaunch. Other apps' window titles are
    /// only readable with Screen Recording permission, which makes them a live check.
    private static func canReadOtherWindowTitles() -> Bool {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]]
        else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                let owner = info[kCGWindowOwnerName as String] as? String,
                owner != "Dock", owner != "Window Server",
                let title = info[kCGWindowName as String] as? String
            else { return false }
            return !title.isEmpty
        }
    }

    private func checkBlackHole() {
        blackHoleDetected = AudioDeviceManager.findDevice(named: "BlackHole 16ch") != nil
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
