import SwiftUI
import AppKit

struct ActivityView: View {
    @Bindable var store: StudioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                liveStatus
                savedAttempts
                stateDetails
                evaluationHistory
                console
            }
            .padding(28)
            .frame(maxWidth: 1_150, alignment: .leading)
        }
        .navigationTitle("Activity & Logs")
    }

    private var liveStatus: some View {
        HStack(spacing: 18) {
            Image(systemName: store.runner.isRunning ? "waveform.circle.fill" : (store.hasPipelineFailure ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath"))
                .font(.system(size: 34))
                .foregroundStyle(store.runner.isRunning ? StudioTheme.amber : (store.hasPipelineFailure ? .red : StudioTheme.moss))
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.phaseDescription)
                        .font(.title2.weight(.semibold))
                    Text("Last refresh \(store.lastRefresh.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.runner.isRunning {
                Button("Stop process", systemImage: "stop.fill", role: .destructive) { store.runner.stop() }
            } else {
                Button("Check Connection", systemImage: "bolt.horizontal.circle") { store.runModelCheck() }
                    .help("Check Connection")
            }
        }
        .studioCard()
    }

    private var savedAttempts: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Saved attempts")
                    .font(.headline)
                Text("Includes rejected drafts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open attempts", systemImage: "folder") {
                NSWorkspace.shared.open(store.projectURL.appendingPathComponent("draft_attempts"))
            }
            .disabled(!FileManager.default.fileExists(atPath: store.projectURL.appendingPathComponent("draft_attempts").path))
        }
        .studioCard()
    }

    private var stateDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(text: "Pipeline state")
            Grid(alignment: .leading, horizontalSpacing: 34, verticalSpacing: 11) {
                stateRow("Phase", store.currentPhase.title, "Current focus", store.state.currentFocus ?? "—")
                stateRow("Foundation iterations", "\(store.state.iteration)", "Foundation score", store.state.foundationScore.formatted(.number.precision(.fractionLength(1))))
                stateRow("Lore score", store.state.loreScore.formatted(.number.precision(.fractionLength(1))), "Drafted chapters", "\(store.actualDraftedChapters) / \(store.targetChapters)")
                stateRow(
                    "Revision cycle",
                    "\(store.state.revisionCycle)",
                    "Novel score",
                    store.state.novelScore.map {
                        $0.formatted(.number.precision(.fractionLength(1)))
                    } ?? "Not scored"
                )
                stateRow("Words on disk", store.totalWords.formatted(), "Open continuity debts", "\(store.pendingDebts)")
            }
            if let failure = store.state.lastError, store.state.status == "failed" {
                Divider()
                Label("Stopped during \(failure.step.replacingOccurrences(of: "_", with: " "))", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let logPath = failure.logPath {
                    Text("Full diagnostic: \(logPath)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            if let refreshError = store.refreshError {
                Label(refreshError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var evaluationHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "Evaluation history")
            if store.activity.isEmpty {
                ContentUnavailableView(
                    "No evaluations yet",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Written to results.tsv when the pipeline scores a draft")
                )
                .frame(minHeight: 120)
            } else {
                ForEach(store.activity) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(record.columns.first ?? "")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        Text(record.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if record.id != store.activity.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var console: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow(text: "Process output")
                Spacer()
                Button("Clear") { store.runner.clearOutput() }
                    .disabled(store.runner.isRunning || store.runner.output.isEmpty)
            }
            if store.runner.output.isEmpty {
                Text("No process output yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                ScrollView {
                    Text(store.runner.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .frame(minHeight: 180, maxHeight: 420)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private func stateRow(_ leftLabel: String, _ leftValue: String, _ rightLabel: String, _ rightValue: String) -> some View {
        GridRow {
            Text(leftLabel).foregroundStyle(.secondary)
            Text(leftValue).fontWeight(.medium).monospacedDigit()
            Text(rightLabel).foregroundStyle(.secondary)
            Text(rightValue).fontWeight(.medium).monospacedDigit()
        }
        .font(.subheadline)
    }
}
