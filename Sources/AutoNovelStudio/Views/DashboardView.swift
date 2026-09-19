import SwiftUI

struct DashboardView: View {
    @Bindable var store: StudioStore
    @State private var confirmFullRun = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DashboardHeroView(store: store, confirmFullRun: $confirmFullRun)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                if store.hasPipelineFailure {
                    DashboardFailureNoticeView(store: store, confirmFullRun: $confirmFullRun)
                        .padding(.top, 18)
                }
                DashboardMetricsView(store: store)
                    .padding(.vertical, 24)
                DashboardPhaseRailView(store: store)
                DashboardWorkbenchView(store: store)
                    .padding(.vertical, 26)
                if store.runner.isRunning || !store.runner.output.isEmpty {
                    DashboardLiveConsoleView(store: store)
                        .padding(.bottom, 26)
                }
                DashboardRecentActivityView(store: store)
            }
            .padding(28)
            .frame(maxWidth: 1_220, alignment: .leading)
        }
        .navigationTitle("Overview")
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
        }
        .alert("Start writing \(bookTitle)?", isPresented: $confirmFullRun) {
            Button("Cancel", role: .cancel) {}
            Button(store.actualDraftedChapters > 0 ? "Resume writing" : "Start writing") {
                store.runFullPipeline()
            }
        } message: {
            Text("Continues from files on disk. Existing Book Setup, Story Seed, and chapters are not erased.")
        }
    }

    private var bookTitle: String {
        let title = store.loadBookBrief().title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled manuscript" : title
    }
}
