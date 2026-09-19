import SwiftUI

struct DashboardRecentActivityView: View {
    @Bindable var store: StudioStore

    var body: some View {
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
                            .foregroundStyle(
                                record.isFailure
                                    ? .red
                                    : (record.isDiscarded || record.isForced
                                        ? .orange
                                        : StudioTheme.success)
                            )
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
}
