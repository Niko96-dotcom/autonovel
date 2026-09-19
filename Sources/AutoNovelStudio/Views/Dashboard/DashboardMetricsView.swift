import SwiftUI

struct DashboardMetricsView: View {
    @Bindable var store: StudioStore

    var body: some View {
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
