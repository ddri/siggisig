import SwiftUI

struct AppListView: View {
    let apps: [CaptureApp]
    let isRouted: (CaptureApp) -> Bool
    let channelLabel: (CaptureApp) -> String?
    let onToggle: (CaptureApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Apps")
                .font(.headline)
                .padding(.bottom, 8)

            List(apps) { app in
                HStack {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                    Text(app.name)
                        .lineLimit(1)
                    Spacer()
                    if let label = channelLabel(app) {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Circle()
                        .fill(isRouted(app) ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                }
                .contentShape(Rectangle())
                .onTapGesture { onToggle(app) }
            }
        }
    }
}
