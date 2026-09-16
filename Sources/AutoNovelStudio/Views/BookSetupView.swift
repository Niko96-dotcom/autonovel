import SwiftUI

struct BookSetupView: View {
    @Bindable var store: StudioStore
    @State private var brief = BookBrief()
    @State private var lastSavedBrief = BookBrief()
    @State private var didLoad = false
    @State private var saveMessage: String?
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                bookIdentity
                storyEngine
                worldAndWonder
                readerPromise
                boundaries
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .navigationTitle("New Book Setup")
        .toolbar {
            ToolbarItem(placement: .status) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        brief.requiredCompleted == 5
                            ? "Your book setup is ready"
                            : "\(5 - brief.requiredCompleted) essential field\(brief.requiredCompleted == 4 ? "" : "s") left"
                    )
                    Text(saveMessage ?? "Your answers save automatically")
                        .foregroundStyle(.secondary)
                    if let saveError {
                        Text(saveError).foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .frame(maxWidth: 320, alignment: .leading)
            }
            ToolbarItem(placement: .automatic) {
                Button("Save") { _ = save() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save and continue") {
                    if save() { store.selection = .overview }
                }
                .disabled(brief.requiredCompleted < 5)
            }
        }
        .focusedValue(\.studioSaveAction, { _ = save() })
        .task {
            guard !didLoad else { return }
            let savedBrief = store.loadBookBrief()
            brief = savedBrief
            lastSavedBrief = savedBrief
            didLoad = true
            saveMessage = store.hasBookBrief ? "All changes saved" : "Your answers save automatically"
        }
        .onChange(of: brief) { _, newValue in scheduleAutosave(newValue) }
        .onDisappear {
            saveTask?.cancel()
            if didLoad, brief != lastSavedBrief { _ = save(showMessage: false) }
        }
    }

    private var bookIdentity: some View {
        setupSection(title: "Book shape") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    compactField("Working title *", text: $brief.title)
                    compactField("Author name", text: $brief.author)
                }
                GridRow {
                    compactField("Genre / subgenre", text: $brief.genre)
                    compactField("Intended reader", text: $brief.audience)
                }
                GridRow {
                    compactField("Point of view", text: $brief.pointOfView)
                    compactField("Tense", text: $brief.tense)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Target length")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        TextField("Words", value: $brief.targetWords, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                            .onChange(of: brief.targetWords) { _, newValue in
                                let clamped = min(200_000, max(15_000, newValue))
                                if clamped != newValue { brief.targetWords = clamped }
                            }
                        Stepper("Target words", value: $brief.targetWords, in: 15_000...200_000, step: 5_000)
                            .labelsHidden()
                        Text("words")
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Chapters")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        TextField("Chapters", value: $brief.targetChapters, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                            .onChange(of: brief.targetChapters) { _, newValue in
                                let clamped = min(80, max(5, newValue))
                                if clamped != newValue { brief.targetChapters = clamped }
                            }
                        Stepper("Target chapters", value: $brief.targetChapters, in: 5...80)
                            .labelsHidden()
                        Text("chapters")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var storyEngine: some View {
        setupSection(title: "Story engine") {
            LabeledEditor(
                title: "Premise *",
                text: $brief.premise
            )
            LabeledEditor(
                title: "Protagonist *",
                text: $brief.protagonist
            )
            HStack(alignment: .top, spacing: 16) {
                LabeledEditor(
                    title: "What they want",
                    text: $brief.protagonistWant,
                    minHeight: 110
                )
                LabeledEditor(
                    title: "Central conflict *",
                    text: $brief.centralConflict,
                    minHeight: 110
                )
            }
            LabeledEditor(
                title: "Stakes",
                text: $brief.stakes
            )
        }
    }

    private var worldAndWonder: some View {
        setupSection(title: "World") {
            LabeledEditor(
                title: "World hook *",
                text: $brief.worldHook
            )
            HStack(alignment: .top, spacing: 16) {
                LabeledEditor(
                    title: "Speculative element or magic",
                    text: $brief.speculativeElement,
                    minHeight: 110
                )
                LabeledEditor(
                    title: "Costs and limits",
                    text: $brief.costsAndLimits,
                    minHeight: 110
                )
            }
        }
    }

    private var readerPromise: some View {
        setupSection(title: "Reader promise") {
            HStack(alignment: .top, spacing: 16) {
                LabeledEditor(
                    title: "Themes",
                    text: $brief.themes,
                    minHeight: 110
                )
                LabeledEditor(
                    title: "Tone and reader promise",
                    text: $brief.toneAndPromise,
                    minHeight: 110
                )
            }
            LabeledEditor(
                title: "Ending direction",
                text: $brief.endingDirection
            )
        }
    }

    private var boundaries: some View {
        setupSection(title: "Boundaries", description: "Optional") {
            LabeledEditor(
                title: "Must include",
                text: $brief.mustInclude
            )
            HStack(alignment: .top, spacing: 16) {
                LabeledEditor(
                    title: "Avoid and hard boundaries",
                    text: $brief.avoid,
                    minHeight: 110
                )
                LabeledEditor(
                    title: "Content and intensity",
                    text: $brief.contentNotes,
                    minHeight: 110
                )
            }
        }
    }

    private func setupSection<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(.title2, design: .serif, weight: .semibold))
                if let description {
                    Text(description).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Divider()
            content()
        }
        .studioCard(padding: 22)
    }

    private func compactField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField("", text: text)
                .accessibilityLabel(title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }

    private func scheduleAutosave(_ newValue: BookBrief) {
        guard didLoad, newValue != lastSavedBrief else { return }
        saveTask?.cancel()
        saveMessage = "Saving…"
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            _ = save(showMessage: false)
        }
    }

    @discardableResult
    private func save(showMessage: Bool = true) -> Bool {
        saveTask?.cancel()
        do {
            try store.saveBookBrief(brief)
            lastSavedBrief = brief
            saveError = nil
            saveMessage = showMessage
                ? "Saved \(Date().formatted(date: .omitted, time: .shortened))"
                : "All changes saved"
            return true
        } catch {
            saveMessage = nil
            saveError = error.localizedDescription
            return false
        }
    }
}
