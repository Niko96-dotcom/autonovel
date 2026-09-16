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
                intro
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
                Button("Save & Continue to Start") {
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

    private var intro: some View {
        HStack(alignment: .top, spacing: 22) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(StudioTheme.heroGradient, in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrow(text: "The only required page")
                Text("Tell AutoNovel what kind of book you want.")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                Text("You do not need a complete world bible or a chapter plan. Fill the five essential fields, add any details you care about, and the local model can propose the rest. Every generated file stays editable.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 7) {
                Text("\(brief.requiredCompleted) / 5")
                    .font(.title2.bold())
                    .monospacedDigit()
                Text("essentials")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(brief.requiredCompleted), total: 5)
                    .frame(width: 120)
            }
        }
        .studioCard(padding: 22)
    }

    private var bookIdentity: some View {
        setupSection(
            eyebrow: "1 · Book shape",
            title: "What kind of book is this?",
            description: "A working title is enough. These choices guide voice, scale, and reader expectations."
        ) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    compactField("Working title *", text: $brief.title, prompt: "The Clockmaker's Daughter")
                    compactField("Author name", text: $brief.author, prompt: "Your name or pen name")
                }
                GridRow {
                    compactField("Genre / subgenre", text: $brief.genre, prompt: "Cozy fantasy, thriller, romance…")
                    compactField("Intended reader", text: $brief.audience, prompt: "Adult, YA, middle grade…")
                }
                GridRow {
                    compactField("Point of view", text: $brief.pointOfView, prompt: "First person, third limited…")
                    compactField("Tense", text: $brief.tense, prompt: "Past or present tense")
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
        setupSection(
            eyebrow: "2 · Story engine",
            title: "Who wants what—and why can’t they have it?",
            description: "These are the strongest levers in the whole setup. Plain language works best."
        ) {
            LabeledEditor(
                title: "Premise *",
                prompt: "In one or two sentences: who is the story about, what changes, and what must they do?",
                text: $brief.premise
            )
            LabeledEditor(
                title: "Protagonist *",
                prompt: "Name, role, defining contradiction, and the thing that makes them difficult or compelling.",
                text: $brief.protagonist
            )
            HStack(alignment: .top, spacing: 16) {
                LabeledEditor(
                    title: "What they want",
                    prompt: "Their concrete external goal—and, if you know it, what they actually need.",
                    text: $brief.protagonistWant,
                    minHeight: 110
                )
                LabeledEditor(
                    title: "Central conflict *",
                    prompt: "The person, system, force, or inner flaw that keeps making the goal harder.",
                    text: $brief.centralConflict,
                    minHeight: 110
                )
            }
            LabeledEditor(
                title: "Stakes",
                prompt: "What is lost if the protagonist fails? Include personal and wider consequences.",
                text: $brief.stakes
            )
        }
    }

    private var worldAndWonder: some View {
        setupSection(
            eyebrow: "3 · World and wonder",
            title: "What makes this story’s world distinct?",
            description: "Give the model one memorable hook and honest limits. It can build the deeper lore."
        ) {
            LabeledEditor(
                title: "World hook *",
                prompt: "The place, era, society, or situation readers could recognize in one sentence.",
                text: $brief.worldHook
            )
            HStack(alignment: .top, spacing: 16) {
                LabeledEditor(
                    title: "Speculative element or magic",
                    prompt: "What can happen here that cannot happen in ordinary life? Leave blank for realism.",
                    text: $brief.speculativeElement,
                    minHeight: 110
                )
                LabeledEditor(
                    title: "Costs and limits",
                    prompt: "What can this power, technology, or social system not do—and what does it cost?",
                    text: $brief.costsAndLimits,
                    minHeight: 110
                )
            }
        }
    }

    private var readerPromise: some View {
        setupSection(
            eyebrow: "4 · Reader promise",
            title: "How should the book feel?",
            description: "This is where you steer emotional tone and prevent technically correct but wrong-feeling prose."
        ) {
            HStack(alignment: .top, spacing: 16) {
                LabeledEditor(
                    title: "Themes",
                    prompt: "Questions or tensions to explore—not a lesson the book must preach.",
                    text: $brief.themes,
                    minHeight: 110
                )
                LabeledEditor(
                    title: "Tone and reader promise",
                    prompt: "Lyrical but tense? Funny and tender? Bleak with a hopeful center?",
                    text: $brief.toneAndPromise,
                    minHeight: 110
                )
            }
            LabeledEditor(
                title: "Ending direction",
                prompt: "A precise ending, a general emotional destination, or simply what must feel resolved.",
                text: $brief.endingDirection
            )
        }
    }

    private var boundaries: some View {
        setupSection(
            eyebrow: "5 · Your boundaries",
            title: "What must—or must never—appear?",
            description: "Optional, but important when a trope, theme, intensity, or representation choice matters to you."
        ) {
            LabeledEditor(
                title: "Must include",
                prompt: "Scenes, relationships, images, ideas, tropes, or moments you already know you want.",
                text: $brief.mustInclude
            )
            HStack(alignment: .top, spacing: 16) {
                LabeledEditor(
                    title: "Avoid and hard boundaries",
                    prompt: "Unwanted tropes, plot turns, styles, or subjects.",
                    text: $brief.avoid,
                    minHeight: 110
                )
                LabeledEditor(
                    title: "Content and intensity",
                    prompt: "Desired limits for violence, sex, language, horror, or other sensitive material.",
                    text: $brief.contentNotes,
                    minHeight: 110
                )
            }
        }
    }

    private func setupSection<Content: View>(
        eyebrow: String,
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                SectionEyebrow(text: eyebrow)
                Text(title).font(.system(.title2, design: .serif, weight: .semibold))
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            content()
        }
        .studioCard(padding: 22)
    }

    private func compactField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(prompt, text: text)
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
