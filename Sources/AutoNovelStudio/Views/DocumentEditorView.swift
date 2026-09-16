import SwiftUI

struct DocumentEditorView: View {
    @Bindable var store: StudioStore
    let document: BookDocument

    @State private var text = ""
    @State private var lastSavedText = ""
    @State private var loaded = false
    @State private var saveState = "Loading…"
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var showsGuide = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(document.title)
        .focusedValue(\.studioSaveAction, { saveNow() })
        .task(id: document.id) { load() }
        .onChange(of: text) { _, newValue in scheduleSave(newValue) }
        .onDisappear {
            saveTask?.cancel()
            if loaded, text != lastSavedText { saveNow() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: document.symbol)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(document.title)
                        .font(.system(.title3, design: document.role == .chapter ? .serif : .default, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    StatusPill(
                        text: document.role.rawValue,
                        color: document.role == .required ? StudioTheme.amber : StudioTheme.moss
                    )
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            if let errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(errorMessage)
            } else {
                Label(saveState, systemImage: saveState == "Saved" ? "checkmark.circle" : "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button("Guide", systemImage: "questionmark.circle") {
                showsGuide = true
            }
            .labelStyle(.iconOnly)
            .help("Show editing guidance")
            .popover(isPresented: $showsGuide, arrowEdge: .top) {
                guidance
                    .frame(width: 380)
            }

            Button("Save", systemImage: "square.and.arrow.down") { saveNow() }
                .labelStyle(.iconOnly)
                .help("Save now")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var editor: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: document.role == .chapter ? 17 : 15, design: document.role == .chapter ? .serif : .monospaced))
                    .lineSpacing(document.role == .chapter ? 5 : 2)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, document.role == .chapter ? 34 : 16)
                    .padding(.vertical, document.role == .chapter ? 24 : 16)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                if text.isEmpty && loaded {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(emptyTitle)
                            .font(.headline)
                        if document.role == .generated {
                            Text("Overview generates this, or write it here")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(26)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(document.role == .chapter ? 0.72 : 0.45))
    }

    private var emptyTitle: String {
        switch document.role {
        case .chapter: "No prose yet"
        default: "No \(document.title.lowercased()) yet"
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionEyebrow(text: "What belongs here")
                Spacer()
                Label(document.fileName, systemImage: "doc.text")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            ForEach(document.guidance, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(StudioTheme.moss)
                        .padding(.top, 1)
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioTheme.moss.opacity(0.07))
    }

    private func load() {
        saveTask?.cancel()
        loaded = false
        do {
            let loadedText = try store.loadText(for: document)
            text = loadedText
            lastSavedText = loadedText
            errorMessage = nil
            saveState = "Saved"
        } catch CocoaError.fileReadNoSuchFile {
            text = ""
            lastSavedText = ""
            errorMessage = nil
            saveState = "New file"
        } catch {
            text = ""
            lastSavedText = ""
            errorMessage = error.localizedDescription
            saveState = "Could not load"
        }
        loaded = true
    }

    private func scheduleSave(_ newValue: String) {
        guard loaded, newValue != lastSavedText else { return }
        saveTask?.cancel()
        saveState = "Saving…"
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        guard loaded else { return }
        saveTask?.cancel()
        do {
            try store.saveText(text, for: document)
            lastSavedText = text
            errorMessage = nil
            saveState = "Saved"
        } catch {
            errorMessage = error.localizedDescription
            saveState = "Save failed"
        }
    }
}
