import SwiftUI

struct ActiveRoutesView: View {
    let routes: [Route]
    let maxSlots: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active Routes")
                .font(.headline)
                .padding(.bottom, 4)

            List {
                ForEach(0..<maxSlots, id: \.self) { slot in
                    if let route = routes.first(where: { $0.slot == slot }) {
                        HStack {
                            Text(route.appName)
                                .lineLimit(1)
                            Spacer()
                            Text(route.channelPair)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack {
                            Text(Route.channelPairLabel(for: slot))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("free")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}
