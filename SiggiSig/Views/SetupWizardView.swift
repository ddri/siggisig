import ScreenCaptureKit
import SwiftUI

struct SetupWizardView: View {
    @Binding var isComplete: Bool
    @State private var blackHoleDetected = false
    @State private var permissionGranted = false
    @State private var checking = false
    @State private var permissionRequested = false
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
                systemName: permissionGranted
                    ? "checkmark.circle.fill" : "rectangle.dashed.badge.record"
            )
            .font(.largeTitle)
            .foregroundColor(permissionGranted ? .green : .secondary)

            Text("Screen Recording Permission")
                .font(.headline)

            if permissionGranted {
                Text("Permission granted!")
                    .foregroundColor(.green)
                Button("Get Started") { isComplete = true }
                    .buttonStyle(.borderedProminent)
            } else if permissionRequested {
                Text(
                    "If no prompt appeared, you'll need to add SiggiSig manually in System Settings."
                )
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    Button("Open System Settings") {
                        openScreenRecordingSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Check Again") {
                        Task { await checkPermission() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text(
                    "SiggiSig needs this permission to capture audio from individual apps."
                )
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

                Button("Request Permission") {
                    Task { await requestPermission() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task { await checkPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkPermission() }
        }
    }

    private func checkBlackHole() async {
        checking = true
        blackHoleDetected = AudioDeviceManager.findDevice(named: "BlackHole 16ch") != nil
        checking = false
    }

    private func checkPermission() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            permissionGranted = true
        } catch {
            permissionGranted = false
        }
    }

    private func requestPermission() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            permissionGranted = true
        } catch {
            permissionGranted = false
        }
        permissionRequested = true
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
