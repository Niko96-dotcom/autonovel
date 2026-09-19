import SwiftUI

struct DashboardFailureNoticeView: View {
    @Bindable var store: StudioStore
    @Binding var confirmFullRun: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Run stopped").font(.headline)
                Text(store.state.lastError?.message ?? "The last pipeline step did not finish.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("\(store.actualDraftedChapters) chapters remain on disk")
                    .font(.caption.weight(.medium))
            }
            Spacer()
            Button("Resume writing", systemImage: "play.fill") { confirmFullRun = true }
                .buttonStyle(.borderedProminent)
                .disabled(store.runner.isRunning)
        }
        .padding(17)
        .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
