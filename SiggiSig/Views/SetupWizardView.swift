import SwiftUI

struct SetupWizardView: View {
    @Binding var isComplete: Bool
    @State private var blackHoleDetected = false
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
        .padding(32)
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
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("Screen Recording Permission")
                .font(.headline)

            Text(
                "SiggiSig needs Screen Recording permission to capture audio from individual apps. Please make sure SiggiSig is enabled in System Settings."
            )
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button("Open System Settings") {
                    openScreenRecordingSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Continue") { isComplete = true }
                    .buttonStyle(.bordered)
            }
        }
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
