import SwiftUI

struct StudioHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AutoNovel Studio Help")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            Form {
                Section("Set up a book") {
                    Text("Open New Book Setup from the sidebar. Fill the five essential fields, then use Save in the toolbar or File > Save. Save & Continue to Start returns you to Overview.")
                }
                Section("Connect a model") {
                    Text("Choose AutoNovel Studio > Settings to set the provider, API base URL, and authentication. Private keys are stored in the macOS Keychain. Check Connection verifies the backend without starting a full run.")
                }
                Section("Edit the manuscript") {
                    Text("Chapters, Canon, and other book files open in the editor. Changes save automatically. File > Save writes immediately. Edit > Find… opens the system Find panel in the current text.")
                }
                Section("Run the pipeline") {
                    Text("Overview starts or resumes writing. Activity & Logs shows live process output. Use View > Show Sidebar if the section list is hidden.")
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 520)
    }
}
