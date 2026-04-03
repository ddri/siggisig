import SwiftUI

struct MeterBarView: View {
    let rms: Float
    let peak: Float

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let rmsHeight = CGFloat(rms) * height
            let peakY = height - (CGFloat(peak) * height)

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
                if peak > 0.01 {
                    Rectangle()
                        .fill(peak > 0.9 ? Color.red : Color.yellow)
                        .frame(height: 2)
                        .offset(y: peakY - height)
                }
            }
        }
    }
}
