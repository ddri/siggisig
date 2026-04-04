import SwiftUI

struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    @State private var isDragging = false
    @State private var dragStartValue: Float = 0

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
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            dragStartValue = value
                        }
                        let deltaY = drag.translation.height
                        let deltaNorm = Float(deltaY / height)
                        let newValue = dragStartValue - deltaNorm * (range.upperBound - range.lowerBound)
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }
}
