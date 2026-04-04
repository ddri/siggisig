import SwiftUI

struct MeterBarView: View {
    let rms: Float
    let peak: Float

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let scaledRMS = scaleMeter(rms)
            let scaledPeak = scaleMeter(peak)
            let rmsHeight = CGFloat(scaledRMS) * height
            let peakY = height - (CGFloat(scaledPeak) * height)

            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.3))

                // RMS bar with gradient
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.green, .green, .yellow, .red],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: rmsHeight)

                // Peak hold indicator
                if scaledPeak > 0.01 {
                    Rectangle()
                        .fill(scaledPeak > 0.9 ? Color.red : Color.yellow)
                        .frame(height: 2)
                        .offset(y: peakY - height)
                }
            }
        }
    }

    /// Scale linear amplitude (0...1) to a visually useful meter range.
    /// Uses a dB-based curve so quiet audio is still visible.
    private func scaleMeter(_ linear: Float) -> Float {
        guard linear > 0.0001 else { return 0 }
        // Convert to dB (-60...0 range)
        let db = 20 * log10(linear)
        // Map -60dB...0dB to 0...1
        let scaled = (db + 60) / 60
        return min(max(scaled, 0), 1)
    }
}
