import CoreGraphics
import SwiftUI

struct SetupWizardView: View {
    @Binding var isComplete: Bool
    @State private var blackHoleDetected = false
    @State private var checking = false
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
        .task {
            checkPermission()
            await checkBlackHole()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermission()
            Task { await checkBlackHole() }
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
                        Task { await checkBlackHole() }
                    }
                    .disabled(checking)
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
                    isComplete = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(
                    "SiggiSig needs Screen Recording permission to capture audio from individual apps.\n\nIn System Settings, make sure the toggle switch next to SiggiSig is turned ON (blue)."
                )
                .foregroundColor(.secondary)
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
                            isComplete = true
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
        hasPermission = CGPreflightScreenCaptureAccess()
    }

    private func checkBlackHole() async {
        checking = true
        blackHoleDetected = AudioDeviceManager.findDevice(named: "BlackHole 16ch") != nil
        checking = false
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
