import SwiftUI

struct DashboardPhaseRailView: View {
    @Bindable var store: StudioStore

    var body: some View {
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

    private var currentPhaseIndex: Int {
        PipelinePhase.allCases.firstIndex(of: store.currentPhase) ?? 0
    }

    private var currentPhaseNumber: Int { currentPhaseIndex + 1 }
}
