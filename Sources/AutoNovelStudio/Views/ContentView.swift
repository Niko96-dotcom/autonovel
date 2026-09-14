import SwiftUI

struct ContentView: View {
    @Bindable var store: StudioStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.runner.isRunning {
                    StatusPill(text: store.runner.label, color: StudioTheme.amber, animated: true)
                    Button("Stop", systemImage: "stop.fill") { store.runner.stop() }
                } else {
                    StatusPill(
                        text: store.hasPipelineFailure ? "Needs attention" : "Live",
                        color: store.hasPipelineFailure ? .red : StudioTheme.moss
                    )
                    Button("Check Model", systemImage: "bolt.horizontal.circle") {
                        store.runModelCheck()
                    }
                    .disabled(store.runner.isRunning)
                }

                SettingsLink {
                    Label("Model Provider", systemImage: "server.rack")
                }
                .labelStyle(.iconOnly)
                .help("Configure model provider")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection {
        case .overview:
            DashboardView(store: store)
        case .setup:
            BookSetupView(store: store)
        case .chapters:
            ChaptersView(store: store)
        case .rules:
            AdvancedDocumentsView(store: store)
        case .activity:
            ActivityView(store: store)
        default:
            if let document = BookDocument.forSection(store.selection) {
                DocumentEditorView(store: store, document: document)
                    .id(document.id)
            }
        }
    }
}
