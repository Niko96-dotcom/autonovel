import SwiftUI

struct DashboardWorkbenchView: View {
    @Bindable var store: StudioStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 42) {
                projectChecklist
                Divider()
                providerControl
            }
            VStack(alignment: .leading, spacing: 26) {
                projectChecklist
                Divider()
                providerControl
            }
        }
    }

    private var projectChecklist: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionEyebrow(text: "Project")
            checklistRow("Book setup", "Premise, protagonist, conflict, and world hook", done: store.seedIsReady)
            checklistRow("Story foundation", "World, cast, voice, outline, canon, and secrets", done: store.state.foundationScore > 0)
            checklistRow("Drafted prose", done: store.actualDraftedChapters > 0)
            Button("Open New Book Setup", systemImage: "arrow.right") { store.selection = .setup }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerControl: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionEyebrow(text: "Model provider")
                Spacer()
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
            }
            Text(store.providerConfiguration.writerModel.isEmpty ? "Connect a writing model" : store.providerConfiguration.writerModel)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .lineLimit(1)
            Text(store.providerSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let error = store.runner.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if store.runner.isRunning {
                Label(store.runner.modelStatus ?? store.runner.label, systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            HStack {
                Button("Check Connection", systemImage: "bolt.horizontal.circle") { store.runModelCheck() }
                    .buttonStyle(.borderedProminent)
                    .help("Check Connection")
                    .disabled(store.runner.isRunning)
                SettingsLink { Label("Open settings", systemImage: "slider.horizontal.3") }
            }
            if !store.completionIsVerified {
                Button("Run current phase: \(store.currentPhase.title)", systemImage: "play.fill") { store.runCurrentPhase() }
                    .disabled(!store.seedIsReady || store.runner.isRunning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checklistRow(_ title: String, _ detail: String? = nil, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? StudioTheme.success : .secondary)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
