import SwiftUI

struct SidebarView: View {
    @Bindable var store: StudioStore

    var body: some View {
        VStack(spacing: 0) {
            brandHeader

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

            Divider()
            projectFooter
        }
        .navigationTitle("Studio")
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "text.book.closed.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(StudioTheme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("AUTONOVEL")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                Text("Writing studio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var projectFooter: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(StudioTheme.accent)
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
                .help("Configure model provider")
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
        ForEach(sections) { section in
            HStack(spacing: 11) {
                Image(systemName: section.symbol)
                    .frame(width: 19)
                    .foregroundStyle(section == .setup ? StudioTheme.accent : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .lineLimit(1)
                    if let subtitle = section.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tag(section)
        }
    }
}
