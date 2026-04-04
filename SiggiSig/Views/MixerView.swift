import SwiftUI

struct MixerView: View {
    let routes: [Route]
    let pendingRoutes: [SavedRoute]
    let meterLevels: [pid_t: MeterLevels]
    let maxSlots: Int
    let onVolumeChange: (pid_t, Float) -> Void
    let iconForBundle: (String?) -> NSImage?

    var body: some View {
        VStack(spacing: 0) {
            Text("Mixer")
                .font(.headline)
                .padding(.bottom, 8)

            if routes.isEmpty && pendingRoutes.isEmpty {
                Spacer()
                Text("Click an app to start routing")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        // Active routes
                        ForEach(routes) { route in
                            MixerStripView(
                                appName: route.appName,
                                icon: iconForBundle(route.bundleID),
                                channelLabel: route.channelPair,
                                isActive: true,
                                meterLevels: meterLevels[route.pid],
                                volume: Binding(
                                    get: { route.volume },
                                    set: { onVolumeChange(route.pid, $0) }
                                )
                            )
                        }

                        // Pending (saved but not running) routes
                        ForEach(pendingRoutes, id: \.bundleID) { saved in
                            MixerStripView(
                                appName: saved.appName,
                                icon: iconForBundle(saved.bundleID),
                                channelLabel: Route.channelPairLabel(for: saved.channelSlot),
                                isActive: false,
                                meterLevels: nil,
                                volume: .constant(saved.volume)
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Spacer()

            // Available slots indicator
            let usedSlots = routes.count + pendingRoutes.count
            let freeSlots = maxSlots - usedSlots
            Text("\(freeSlots) of \(maxSlots) channels free")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
    }
}
