import SwiftUI

@main
struct SiggiSigApp: App {
    @State private var showChangelog = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showChangelog) {
                    ChangelogView()
                }
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("What's New") {
                    showChangelog = true
                }
            }
        }
    }
}
