import SwiftUI

struct DashboardView: View {
    @Bindable var store: StudioStore
    @State private var confirmFullRun = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                if store.hasPipelineFailure {
                    failureNotice.padding(.top, 18)
                }
                metrics
                    .padding(.vertical, 24)
                phaseRail
                workbench
                    .padding(.vertical, 26)
                if store.runner.isRunning || !store.runner.output.isEmpty {
                    liveConsole
                        .padding(.bottom, 26)
                }
                recentActivity
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

    private var hero: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(StudioTheme.ink)

            Circle()
                .stroke(StudioTheme.accent.opacity(0.34), lineWidth: 52)
                .frame(width: 260, height: 260)
                .offset(x: 74, y: -82)
                .accessibilityHidden(true)

            HStack(alignment: .bottom, spacing: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        SectionEyebrow(text: store.completionIsVerified ? "Manuscript complete" : "In production", onDark: true)
                        Circle().fill(.white.opacity(0.24)).frame(width: 3, height: 3)
                        Text("Updated \(store.lastRefresh.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Text(bookTitle)
                        .font(.system(size: 38, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if !store.completionIsVerified {
                        Text(store.phaseDescription)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(2)
                    }

                    heroAction
                        .padding(.top, 2)
                }
                .frame(maxWidth: 650, alignment: .leading)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 7) {
                    Text(store.overallProgress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 52, weight: .light, design: .serif))
                        .foregroundStyle(.white)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text("OVERALL PROGRESS")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.52))
                    ProgressView(value: store.overallProgress)
                        .tint(StudioTheme.accent)
                        .frame(width: 126)
                }
                .padding(.bottom, 3)
            }
            .padding(28)
        }
        .frame(minHeight: 250)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var heroAction: some View {
        if store.runner.isRunning {
            Button("Stop \(store.runner.label)", systemImage: "stop.fill", role: .destructive) {
                store.runner.stop()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(StudioTheme.ink)
            .controlSize(.large)
        } else if !store.seedIsReady {
            Button("Complete New Book Setup", systemImage: "arrow.right") {
                store.selection = .setup
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(StudioTheme.ink)
            .controlSize(.large)
        } else if store.completionIsVerified {
            Button("Inspect all chapters", systemImage: "books.vertical") {
                store.selection = .chapters
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(StudioTheme.ink)
            .controlSize(.large)
        } else {
            Button(
                store.actualDraftedChapters > 0 ? "Resume writing" : "Start writing",
                systemImage: "play.fill"
            ) {
                confirmFullRun = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(StudioTheme.ink)
            .controlSize(.large)
        }
    }

    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { metricReadouts }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                metricReadouts
            }
        }
    }

    @ViewBuilder
    private var metricReadouts: some View {
        MetricReadout(
            label: "Foundation",
            value: store.state.foundationScore.formatted(.number.precision(.fractionLength(1))),
            detail: "Target 7.5"
        )
        metricDivider
        MetricReadout(
            label: "Chapters",
            value: "\(store.actualDraftedChapters)/\(store.targetChapters)",
            detail: "\(store.chapters.count) files on disk"
        )
        metricDivider
        MetricReadout(
            label: "Words drafted",
            value: store.totalWords.formatted()
        )
        metricDivider
        MetricReadout(
            label: "Novel score",
            value: store.state.novelScore.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
            detail: store.state.novelScore == nil ? "Not scored" : "\(store.pendingDebts) open debts"
        )
    }

    private var metricDivider: some View {
        Divider().frame(height: 58).padding(.horizontal, 20)
    }

    private var phaseRail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                SectionEyebrow(text: "Pipeline")
                Spacer()
                Text("Phase \(currentPhaseNumber) of 5")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                ForEach(Array(PipelinePhase.allCases.enumerated()), id: \.element) { index, phase in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: phase.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(index <= currentPhaseIndex ? .white : .secondary)
                                .frame(width: 27, height: 27)
                                .background(index <= currentPhaseIndex ? Color.accentColor : Color.secondary.opacity(0.10), in: Circle())
                            Rectangle()
                                .fill(index < currentPhaseIndex ? Color.accentColor : Color.secondary.opacity(0.13))
                                .frame(height: 1)
                        }
                        Text(phase.title)
                            .font(.caption.weight(phase == store.currentPhase ? .semibold : .regular))
                            .foregroundStyle(phase == store.currentPhase ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 22)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var workbench: some View {
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
            checklistRow("Book setup", "Premise, protagonist, conflict, and world hook", done: store.hasBookBrief)
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

    private var liveConsole: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow(text: "Live output")
                Spacer()
                StatusPill(
                    text: store.runner.isRunning ? "Running" : (store.runner.exitCode == 0 ? "Finished" : "Stopped"),
                    color: store.runner.isRunning ? StudioTheme.accent : (store.runner.exitCode == 0 ? StudioTheme.success : .secondary),
                    animated: store.runner.isRunning
                )
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(String(store.runner.output.suffix(12_000)))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(16)
                        .id("console-end")
                }
                .frame(minHeight: 140, maxHeight: 260)
                .background(StudioTheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white.opacity(0.78))
                .onChange(of: store.runner.output) { _, _ in
                    if reduceMotion {
                        proxy.scrollTo("console-end", anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("console-end", anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionEyebrow(text: "Evaluations")
                Spacer()
                Button("Open activity", systemImage: "arrow.right") { store.selection = .activity }
            }

            if store.activity.isEmpty {
                ContentUnavailableView(
                    "No evaluations yet",
                    systemImage: "clock"
                )
                .frame(minHeight: 110)
            } else {
                ForEach(store.activity.prefix(4)) { record in
                    HStack(spacing: 12) {
                        Image(systemName: record.resultSymbol)
                            .foregroundStyle(record.isFailure ? .red : (record.isDiscarded ? .orange : StudioTheme.success))
                            .frame(width: 18)
                        Text(record.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(record.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    if record.id != store.activity.prefix(4).last?.id { Divider() }
                }
            }
        }
        .padding(.top, 2)
    }

    private var failureNotice: some View {
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

    private var currentPhaseIndex: Int {
        PipelinePhase.allCases.firstIndex(of: store.currentPhase) ?? 0
    }

    private var currentPhaseNumber: Int { currentPhaseIndex + 1 }

    private var bookTitle: String {
        let title = store.loadBookBrief().title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled manuscript" : title
    }
}

private struct MetricReadout: View {
    let label: String
    let value: String
    var detail: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title, design: .serif, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
