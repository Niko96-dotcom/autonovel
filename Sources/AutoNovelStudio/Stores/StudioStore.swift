import Foundation
import Observation

@MainActor
@Observable
final class StudioStore {
    let projectURL: URL
    let runner: PipelineRunner
    private let environmentStore: EnvironmentFileStore

    var selection: StudioSection = .overview {
        didSet {
            guard selection != oldValue else { return }
            StudioLog.sidebar.info(
                "Selected sidebar item: \(self.selection.rawValue, privacy: .public)"
            )
        }
    }
    var showHelp = false
    private(set) var state = PipelineState()
    private(set) var chapters: [ChapterInfo] = []
    private(set) var activity: [ActivityRecord] = []
    private(set) var lastRefresh = Date()
    private(set) var refreshError: String?
    private(set) var hasBookBrief = false
    private(set) var seedIsReady = false
    private(set) var providerConfiguration: ProviderConfiguration

    private var monitorTask: Task<Void, Never>?

    init(projectURL: URL = ProjectLocator.locate()) {
        self.projectURL = projectURL
        self.runner = PipelineRunner(projectURL: projectURL)
        let environmentStore = EnvironmentFileStore(projectURL: projectURL)
        self.environmentStore = environmentStore
        self.providerConfiguration = environmentStore.load()
        refresh()
    }

    var projectName: String { projectURL.lastPathComponent }
    var totalWords: Int { chapters.reduce(0) { $0 + $1.words } }
    var targetChapters: Int {
        if state.chaptersTotal > 0 { return state.chaptersTotal }
        return loadBookBrief().targetChapters
    }
    var pendingDebts: Int { state.debts.filter { $0.status != "done" }.count }
    var providerSummary: String {
        let model = providerConfiguration.writerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? providerConfiguration.preset.title : "\(providerConfiguration.preset.title) · \(model)"
    }
    var actualDraftedChapters: Int {
        var expected = 1
        for chapter in chapters.sorted(by: { $0.number < $1.number }) {
            guard chapter.number == expected, chapter.words > 0 else { break }
            expected += 1
        }
        return expected - 1
    }
    var hasPipelineFailure: Bool { state.status == "failed" && state.lastError != nil }
    var completionIsVerified: Bool {
        guard state.phase.lowercased() == "complete",
              state.status.isEmpty || state.status == "complete",
              actualDraftedChapters == targetChapters,
              let score = state.novelScore
        else { return false }
        return (0...10).contains(score)
    }

    var currentPhase: PipelinePhase {
        if state.phase.lowercased() == "complete", !completionIsVerified {
            return actualDraftedChapters < targetChapters ? .drafting : .revision
        }
        return PipelinePhase(rawValue: state.phase.lowercased()) ?? .foundation
    }

    var overallProgress: Double {
        switch currentPhase {
        case .foundation:
            return min(0.24, max(0, state.foundationScore / 7.5) * 0.24)
        case .drafting:
            let total = max(1, targetChapters)
            return 0.25 + (Double(actualDraftedChapters) / Double(total)) * 0.40
        case .revision:
            return 0.66 + min(Double(state.revisionCycle) / 6.0, 1) * 0.23
        case .export: return 0.92
        case .complete: return 1
        }
    }

    var phaseDescription: String {
        if runner.isRunning { return runner.modelStatus ?? runner.label }
        if let failure = state.lastError, state.status == "failed" {
            let failedStep = failure.step.replacingOccurrences(of: "_", with: " ")
            return "Stopped at \(failedStep)"
        }
        if let focus = state.currentFocus, !focus.isEmpty {
            return focus.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return switch currentPhase {
        case .foundation: "Preparing world, characters, voice, outline, and canon"
        case .drafting: "Writing and checking chapters in sequence"
        case .revision: "Reviewing, cutting, rewriting, and re-scoring"
        case .export: "Building the manuscript and final formats"
        case .complete: "Complete"
        }
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        StudioLog.pipeline.info("Started pipeline state monitoring")
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func refresh() {
        do {
            let stateURL = projectURL.appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let data = try Data(contentsOf: stateURL)
                state = try JSONDecoder().decode(PipelineState.self, from: data)
            }
            chapters = try loadChapters()
            activity = loadActivity()
            hasBookBrief = FileManager.default.fileExists(
                atPath: projectURL.appendingPathComponent("book.json").path
            )
            let seed = try? String(
                contentsOf: projectURL.appendingPathComponent("seed.txt"),
                encoding: .utf8
            )
            let hasSeedContent = !(seed?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if hasBookBrief {
                seedIsReady = loadBookBrief().requiredCompleted == 5 && hasSeedContent
            } else {
                seedIsReady = (seed?.split(whereSeparator: { $0.isWhitespace }).count ?? 0) >= 40
            }
            refreshError = nil
            lastRefresh = Date()
        } catch {
            refreshError = error.localizedDescription
        }
    }

    func loadBookBrief() -> BookBrief {
        let url = projectURL.appendingPathComponent("book.json")
        guard let data = try? Data(contentsOf: url),
              let brief = try? JSONDecoder().decode(BookBrief.self, from: data)
        else { return BookBrief() }
        return brief
    }

    func saveBookBrief(_ brief: BookBrief) throws {
        let seedURL = projectURL.appendingPathComponent("seed.txt")
        let previousGenerated = loadBookBrief().seedText + "\n"
        let existingSeed = try? String(contentsOf: seedURL, encoding: .utf8)
        let existingIsBlank = existingSeed.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(brief)
        try data.write(to: projectURL.appendingPathComponent("book.json"), options: .atomic)
        if existingIsBlank || existingSeed == previousGenerated {
            try (brief.seedText + "\n").write(to: seedURL, atomically: true, encoding: .utf8)
        }
        refresh()
    }

    func loadText(for document: BookDocument) throws -> String {
        try String(
            contentsOf: projectURL.appendingPathComponent(document.fileName),
            encoding: .utf8
        )
    }

    func saveText(_ text: String, for document: BookDocument) throws {
        try text.write(
            to: projectURL.appendingPathComponent(document.fileName),
            atomically: true,
            encoding: .utf8
        )
        refresh()
    }

    func reloadProviderConfiguration() {
        providerConfiguration = environmentStore.load()
    }

    func saveProviderConfiguration(_ configuration: ProviderConfiguration) throws {
        providerConfiguration = try environmentStore.save(configuration)
    }

    func runModelCheck() {
        runner.run(
            label: "Checking connection",
            pythonArguments: ["check_llm.py"],
            extraEnvironment: pipelineEnvironment()
        )
    }

    func runCurrentPhase() {
        guard currentPhase != .complete else { return }
        do {
            try persistUnverifiedCompleteResume()
        } catch {
            refreshError = error.localizedDescription
            StudioLog.pipeline.error(
                "Failed to prepare current phase: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        runner.run(
            label: "Running \(currentPhase.title)",
            pythonArguments: ["run_pipeline.py", "--phase", currentPhase.rawValue],
            extraEnvironment: pipelineEnvironment()
        )
    }

    func runFullPipeline() {
        do {
            try persistUnverifiedCompleteResume()
        } catch {
            refreshError = error.localizedDescription
            StudioLog.pipeline.error(
                "Failed to prepare full pipeline: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        runner.run(
            label: actualDraftedChapters > 0 ? "Resuming at chapter \(actualDraftedChapters + 1)" : "Writing the novel",
            pythonArguments: ["run_pipeline.py"],
            extraEnvironment: pipelineEnvironment()
        )
    }

    func prepareFullPipelineArguments() throws -> [String] {
        try persistUnverifiedCompleteResume()
        return ["run_pipeline.py"]
    }

    func persistUnverifiedCompleteResume() throws {
        guard state.phase.lowercased() == "complete", !completionIsVerified else { return }
        var next = state
        next.phase = currentPhase.rawValue
        next.chaptersDrafted = actualDraftedChapters
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(next)
        try data.write(
            to: projectURL.appendingPathComponent("state.json"),
            options: .atomic
        )
        refresh()
    }

    private func pipelineEnvironment() -> [String: String] {
        environmentStore.pipelineEnvironment(credentialMode: providerConfiguration.credentialMode)
    }

    private func loadChapters() throws -> [ChapterInfo] {
        let directory = projectURL.appendingPathComponent("chapters", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("ch_"), let number = Int(name.dropFirst(3)) else { return nil }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return ChapterInfo.parse(number: number, url: url, text: text)
        }.sorted { $0.number < $1.number }
    }

    private func loadActivity() -> [ActivityRecord] {
        let url = projectURL.appendingPathComponent("results.tsv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let rows = text.split(separator: "\n").dropFirst()
        return Array(rows.enumerated().map { index, row in
            ActivityRecord(index: index, columns: row.split(separator: "\t").map(String.init))
        }.suffix(12).reversed())
    }
}
