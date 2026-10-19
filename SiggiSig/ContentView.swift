import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: RouterViewModel

    var body: some View {
        Group {
            if viewModel.isSetupComplete {
                mainView
            } else {
                SetupWizardView(isComplete: $viewModel.isSetupComplete)
            }
        }
        .frame(minWidth: 720, idealWidth: 840, minHeight: 480, idealHeight: 560)
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AppListView(
                    apps: viewModel.availableApps,
                    isRouted: { viewModel.isRouted($0) },
                    channelLabel: { viewModel.channelLabel(for: $0) },
                    onToggle: { viewModel.toggleCapture(for: $0) }
                )
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)

                Divider()

                MixerView(
                    routes: viewModel.routerState.routes,
                    pendingRoutes: viewModel.pendingRoutes,
                    meterLevels: viewModel.meterLevels,
                    maxSlots: viewModel.routerState.maxSlots,
                    availableSlots: viewModel.availableSlots,
                    onVolumeChange: { pid, db in
                        viewModel.setVolume(for: pid, db: db)
                    },
                    onPanChange: { pid, pan in
                        viewModel.setPan(for: pid, pan: pan)
                    },
                    onChannelChange: { pid, newSlot in
                        viewModel.reassignChannel(pid: pid, to: newSlot)
                    },
                    iconForBundle: { bundleID in
                        viewModel.availableApps.first(where: { $0.bundleIdentifier == bundleID })?.icon
                    }
                )
                .frame(maxWidth: .infinity)
            }

            Divider()

            StatusBarView(
                statusText: viewModel.routerState.statusText,
                errorMessage: viewModel.errorMessage
            )
        }
    }
}
