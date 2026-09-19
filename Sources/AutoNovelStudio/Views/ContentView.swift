import SwiftUI

struct ContentView: View {
    @Bindable var store: StudioStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 280)
        } detail: {
            detail
                .id(store.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.runner.isRunning {
                    StatusPill(text: store.runner.label, color: StudioTheme.amber, animated: true)
                    Button("Stop", systemImage: "stop.fill") { store.runner.stop() }
                } else {
                    StatusPill(
                        text: store.hasPipelineFailure ? "Needs attention" : "Ready",
                        color: store.hasPipelineFailure ? .red : StudioTheme.moss
                    )
                    Button("Check Connection", systemImage: "bolt.horizontal.circle") {
                        store.runModelCheck()
                    }
                    .help("Check Connection")
                    .disabled(store.runner.isRunning)
                }
            }
        }
        .overlay {
            if store.showHelp {
                ZStack {
                    Color.black.opacity(reduceMotion ? 0.18 : 0.28)
                        .ignoresSafeArea()
                        .onTapGesture { store.showHelp = false }
                    StudioHelpView(onClose: { store.showHelp = false })
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: reduceMotion ? .clear : .black.opacity(0.28), radius: reduceMotion ? 0 : 28, y: reduceMotion ? 0 : 10)
                        .padding(36)
                }
                .accessibilityAddTraits(.isModal)
                .onKeyPress(.escape) {
                    store.showHelp = false
                    return .handled
                }
                .onExitCommand { store.showHelp = false }
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
        case .seed, .world, .characters, .voice, .outline, .canon, .mystery:
            if let document = BookDocument.forSection(store.selection) {
                DocumentEditorView(store: store, document: document)
                    .id(document.id)
            }
        }
    }
}
