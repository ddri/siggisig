import SwiftUI

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("What's New")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                Text(LocalizedStringKey(changelogContent))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 500, height: 450)
    }

    private var changelogContent: String {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let content = try? String(contentsOf: url) else {
            return "Changelog not available."
        }
        // Strip the "# Changelog" title and subtitle since we have our own header
        let lines = content.components(separatedBy: "\n")
        let stripped = lines.drop(while: { !$0.hasPrefix("## ") })
        return stripped.joined(separator: "\n")
    }
}
