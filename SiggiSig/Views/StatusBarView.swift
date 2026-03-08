import SwiftUI

struct StatusBarView: View {
    let statusText: String
    let errorMessage: String?

    var body: some View {
        HStack {
            if let error = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .foregroundColor(.orange)
                    .font(.caption)
            } else {
                Image(systemName: "waveform")
                    .foregroundColor(.secondary)
                Text(statusText)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
