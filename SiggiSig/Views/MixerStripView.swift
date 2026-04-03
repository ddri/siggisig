import SwiftUI

struct MixerStripView: View {
    let appName: String
    let icon: NSImage?
    let channelLabel: String
    let isActive: Bool
    let meterLevels: MeterLevels?
    @Binding var volume: Float

    @State private var peakHoldValue: Float = 0.0
    @State private var peakHoldTimer: Timer?

    var body: some View {
        VStack(spacing: 6) {
            // App icon and name
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .opacity(isActive ? 1.0 : 0.4)
            }
            Text(appName)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 60)
                .opacity(isActive ? 1.0 : 0.4)

            // Meter + Fader side by side
            HStack(spacing: 4) {
                // Meter
                MeterBarView(
                    rms: meterLevels?.rms ?? 0,
                    peak: peakHoldValue
                )
                .frame(width: 8)

                // Fader
                VerticalSlider(value: $volume, range: -60...6)
                    .frame(width: 24)
                    .disabled(!isActive)
            }
            .frame(height: 150)

            // Channel label
            Text(channelLabel)
                .font(.caption2)
                .foregroundColor(.secondary)

            // dB readout
            Text(volume <= -60 ? "-∞" : String(format: "%.1f", volume))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .onChange(of: meterLevels?.peak ?? 0) { _, newPeak in
            updatePeakHold(newPeak)
        }
    }

    private func updatePeakHold(_ newPeak: Float) {
        if newPeak > peakHoldValue {
            peakHoldValue = newPeak
            peakHoldTimer?.invalidate()
            peakHoldTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.5)) {
                        peakHoldValue = 0.0
                    }
                }
            }
        }
    }
}
