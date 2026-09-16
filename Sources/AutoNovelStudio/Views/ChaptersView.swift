import SwiftUI

struct ChaptersView: View {
    @Bindable var store: StudioStore
    @State private var selectedChapter: Int?
    @State private var searchText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if store.chapters.isEmpty {
                ContentUnavailableView {
                    Label("No chapters yet", systemImage: "books.vertical")
                } description: {
                    Text("Start the novel from Overview. Drafted chapters will appear here automatically as the local model writes them.")
                } actions: {
                    Button("Go to Overview") { store.selection = .overview }
                        .buttonStyle(.borderedProminent)
                    Button("Review Book Setup") { store.selection = .setup }
                }
            } else if filteredChapters.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                HSplitView {
                    chapterNavigator
                        .frame(minWidth: 230, idealWidth: 270, maxWidth: 330)
                    if let chapter = activeChapter {
                        DocumentEditorView(store: store, document: document(for: chapter))
                            .id(chapter.id)
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Chapters")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Find a chapter")
        .task(id: store.chapters.map(\.id)) {
            if selectedChapter == nil || !store.chapters.contains(where: { $0.id == selectedChapter }) {
                selectedChapter = store.chapters.first?.id
            }
        }
    }

    private var chapterNavigator: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manuscript")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("\(store.chapters.count) chapters · \(store.totalWords.formatted()) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: "\(store.actualDraftedChapters)/\(store.targetChapters)", color: StudioTheme.success)
                }
            }
            .padding(16)

            Divider()

            List(selection: $selectedChapter) {
                ForEach(filteredChapters) { chapter in
                    ChapterRow(chapter: chapter)
                        .tag(chapter.id)
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Button("Previous", systemImage: "chevron.up") { selectChapter(offset: -1) }
                    .labelStyle(.iconOnly)
                    .help("Previous chapter")
                    .disabled(activeChapter?.id == store.chapters.first?.id)
                Button("Next", systemImage: "chevron.down") { selectChapter(offset: 1) }
                    .labelStyle(.iconOnly)
                    .help("Next chapter")
                    .disabled(activeChapter?.id == store.chapters.last?.id)
                Spacer()
                if let activeChapter {
                    Text("\(activeChapter.words.formatted()) words")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var filteredChapters: [ChapterInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.chapters }
        return store.chapters.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.excerpt.localizedCaseInsensitiveContains(query)
                || String($0.number).contains(query)
        }
    }

    private var activeChapter: ChapterInfo? {
        guard let selectedChapter else { return nil }
        return store.chapters.first { $0.id == selectedChapter }
    }

    private func document(for chapter: ChapterInfo) -> BookDocument {
        BookDocument(
            fileName: "chapters/\(chapter.url.lastPathComponent)",
            title: chapter.title,
            summary: "Drafted chapter \(chapter.number), currently \(chapter.words.formatted()) words.",
            symbol: "doc.text",
            role: .chapter,
            guidance: [
                "You can edit the prose directly; changes save to the chapter file.",
                "Keep established facts aligned with Canon and character knowledge.",
                "The evaluator may revise this chapter during later pipeline phases.",
            ]
        )
    }

    private func selectChapter(offset: Int) {
        guard let selectedChapter,
              let currentIndex = store.chapters.firstIndex(where: { $0.id == selectedChapter })
        else { return }
        let destination = currentIndex + offset
        guard store.chapters.indices.contains(destination) else { return }
        let nextID = store.chapters[destination].id
        if reduceMotion {
            self.selectedChapter = nextID
        } else {
            withAnimation(.snappy(duration: 0.24)) {
                self.selectedChapter = nextID
            }
        }
    }
}

private struct ChapterRow: View {
    let chapter: ChapterInfo

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(chapter.numberLabel)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(chapter.excerpt.isEmpty ? "No prose yet" : chapter.excerpt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chapter.title), \(chapter.words) words")
    }
}
