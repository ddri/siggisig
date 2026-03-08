import SwiftUI

struct ContentView: View {
    @State private var viewModel = RouterViewModel()

    var body: some View {
        Group {
            if viewModel.isSetupComplete {
                mainView
            } else {
                SetupWizardView(isComplete: $viewModel.isSetupComplete)
            }
        }
        .onChange(of: viewModel.isSetupComplete) { _, complete in
            if complete {
                viewModel.setup()
                viewModel.startRefreshTimer()
            }
        }
        .frame(width: 600, height: 450)
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
                .frame(maxWidth: .infinity)

                Divider()

                ActiveRoutesView(
                    routes: viewModel.routerState.routes,
                    maxSlots: viewModel.routerState.maxSlots
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
