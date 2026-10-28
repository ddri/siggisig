import SwiftUI

@main
struct SiggiSigApp: App {
    @State private var viewModel = RouterViewModel()
    @State private var showChangelog = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("SiggiSig", id: "main") {
            ContentView(viewModel: viewModel)
                .sheet(isPresented: $showChangelog) {
                    ChangelogView()
                }
        }
        .defaultSize(width: 840, height: 560)
        .commands {
            CommandGroup(replacing: .help) {
                Button("What's New") {
                    showChangelog = true
                }
                Button("Rerun Setup Wizard...") {
                    viewModel.isSetupComplete = false
                }
            }
        }

        MenuBarExtra {
            menuBarContent
        } label: {
            let activeCount = viewModel.routerState.routes.count
            Image(systemName: activeCount > 0 ? "waveform.circle.fill" : "waveform")
        }
    }

    @ViewBuilder
    private var menuBarContent: some View {
        let routes = viewModel.routerState.routes
        if routes.isEmpty {
            Text("SiggiSig: Idle")
        } else {
            Text("SiggiSig: \(routes.count) Route\(routes.count == 1 ? "" : "s") Active")
            Divider()
            ForEach(routes) { route in
                Text("• \(route.appName) → \(Route.channelPairLabel(for: route.slot))")
            }
        }

        Divider()

        Button("Open SiggiSig") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o", modifiers: .command)

        Button("What's New") {
            showChangelog = true
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit SiggiSig") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
