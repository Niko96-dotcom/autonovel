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
            primaryToolbar
        }
        .overlay {
            if store.showHelp {
                helpOverlay
            }
        }
    }

    @ToolbarContentBuilder
    private var primaryToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if store.runner.isRunning {
                StatusPill(text: store.runner.label, color: StudioTheme.amber, animated: true)
            } else {
                StatusPill(
                    text: store.hasPipelineFailure ? "Needs attention" : "Ready",
                    color: store.hasPipelineFailure ? .red : StudioTheme.moss
                )
            }
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if store.runner.isRunning {
                Button("Stop", systemImage: "stop.fill") { store.runner.stop() }
            } else {
                Button("Check Connection", systemImage: "bolt.horizontal.circle") {
                    store.runModelCheck()
                }
                .help("Check Connection")
                .disabled(store.runner.isRunning)
            }
        }
    }

    private var helpOverlay: some View {
        ZStack {
            Color.black.opacity(reduceMotion ? 0.10 : 0.16)
                .ignoresSafeArea()
                .onTapGesture { store.showHelp = false }
            StudioHelpView(onClose: { store.showHelp = false })
                .modifier(StudioGlassPanel(cornerRadius: 16))
                .padding(36)
        }
        .accessibilityAddTraits(.isModal)
        .onKeyPress(.escape) {
            store.showHelp = false
            return .handled
        }
        .onExitCommand { store.showHelp = false }
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

/// Custom help surface: system glass on macOS 26+, adaptive material below.
private struct StudioGlassPanel: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.18), radius: 22, y: 8)
        }
    }
}
