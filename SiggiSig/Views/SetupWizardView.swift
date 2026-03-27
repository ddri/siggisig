import ScreenCaptureKit
import SwiftUI

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
            Image(
                systemName: blackHoleDetected
                    ? "checkmark.circle.fill" : "speaker.wave.2.circle"
            )
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
            .font(.system(size: 48))
            .foregroundColor(permissionGranted ? .green : .secondary)

            Text("Screen Recording Permission")
                .font(.headline)

            Text(
                "SiggiSig needs this permission to capture audio from individual apps."
            )
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
            _ = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true)
            permissionGranted = true
        } catch {
            permissionGranted = false
        }
    }
}
