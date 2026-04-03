import SwiftUI

struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbY = height - (normalized * height)

            ZStack {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 4)

                // Unity gain marker (0 dB)
                let unityNorm = CGFloat((0 - range.lowerBound) / (range.upperBound - range.lowerBound))
                let unityY = height - (unityNorm * height)
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 12, height: 1)
                    .offset(y: unityY - height / 2)

                // Thumb
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 18, height: 10)
                    .shadow(radius: 1)
                    .offset(y: thumbY - height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let normalized = 1.0 - (drag.location.y / height)
                                let clamped = min(max(normalized, 0), 1)
                                value = Float(clamped) * (range.upperBound - range.lowerBound) + range.lowerBound
                            }
                    )
            }
        }
    }
}
