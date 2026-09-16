import SwiftUI

struct SidebarView: View {
    @Bindable var store: StudioStore

    var body: some View {
        List(selection: $store.selection) {
            Section("Start here") {
                rows(StudioSection.startHere)
            }
            Section("Your book") {
                rows(StudioSection.bookFiles)
            }
            Section("Advanced") {
                rows(StudioSection.advanced)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                projectFooter
            }
        }
        .navigationTitle("Studio")
    }

    private var projectFooter: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Model provider")
                        .font(.caption.weight(.medium))
                    Text(store.providerSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .help("Open settings")
            }

            Label(store.projectName, systemImage: "externaldrive")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.bar)
        .help(store.projectURL.path)
    }

    @ViewBuilder
    private func rows(_ sections: [StudioSection]) -> some View {
        ForEach(sections, id: \.self) { section in
            HStack(spacing: 11) {
                Image(systemName: section.symbol)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 19, height: 16, alignment: .center)
                    .foregroundStyle(.secondary)
                Text(section.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tag(section)
        }
    }
}
