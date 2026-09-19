import SwiftUI

struct DashboardHeroView: View {
    @Bindable var store: StudioStore
    @Binding var confirmFullRun: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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

    private var bookTitle: String {
        let title = store.loadBookBrief().title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled manuscript" : title
    }
}
