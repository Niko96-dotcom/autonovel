import XCTest
@testable import AutoNovelStudio

final class AutoNovelStudioTests: XCTestCase {
    func testLatestModelStatusTracksNewRequestAndIgnoresIncompleteLines() {
        let output = "[LLM progress] Response complete: 100 words.\nChecking chapter\n[LLM request] Reading context...\n[LLM progress] 2 wor"
        XCTAssertEqual(PipelineRunner.latestModelStatus(in: output), "Reading context...")
        XCTAssertEqual(PipelineRunner.latestModelStatus(in: output + "ds received.\n"), "2 words received.")
        XCTAssertNil(PipelineRunner.latestModelStatus(in: "Starting pipeline\n"))
    }

    func testLatestModelStatusTracksNewRequestAndIgnoresIncompleteLines_utf8DecoderReassemblesSplitCodepoints() {
        let flushed = PipelineRunner.UTF8StreamDecoder()
        XCTAssertEqual(flushed.consume(Data("AUTONOVEL_LOCAL_OK".utf8), flush: true), "AUTONOVEL_LOCAL_OK")

        let cafe = "café"
        let bytes = Array(cafe.utf8)
        XCTAssertEqual(bytes.suffix(2), [0xC3, 0xA9])
        XCTAssertNil(String(bytes: bytes.dropLast(), encoding: .utf8))
        XCTAssertNil(String(bytes: [bytes.last!], encoding: .utf8))

        let split = PipelineRunner.UTF8StreamDecoder()
        XCTAssertEqual(split.consume(Data(bytes.dropLast())), "caf")
        XCTAssertEqual(split.consume(Data([bytes.last!])), "é")

        let joined = PipelineRunner.UTF8StreamDecoder()
        XCTAssertEqual(
            joined.consume(Data(bytes.dropLast())) + joined.consume(Data([bytes.last!])),
            cafe
        )

        let thumb = Array("👍".utf8)
        let emoji = PipelineRunner.UTF8StreamDecoder()
        XCTAssertEqual(emoji.consume(Data(thumb.prefix(2))), "")
        XCTAssertEqual(emoji.consume(Data(thumb.dropFirst(2))), "👍")
    }

    func testBookBriefCountsOnlyEssentialFields() {
        var brief = BookBrief()
        XCTAssertEqual(brief.requiredCompleted, 0)

        brief.title = "The Glass Cartographer"
        brief.premise = "A mapmaker discovers that erased roads still remember their travelers."
        brief.protagonist = "Mara, an exacting apprentice who cannot get lost."
        brief.centralConflict = "The royal surveyor is deleting rebellious towns from reality."
        brief.worldHook = "Maps determine which places can physically exist."

        XCTAssertEqual(brief.requiredCompleted, 5)
    }

    func testBookBriefClampsTargetsWhenSaving() {
        var brief = BookBrief()
        brief.targetWords = 8
        brief.targetChapters = 2
        XCTAssertEqual(brief.targetWords, 8)
        XCTAssertEqual(brief.targetChapters, 2)

        brief.clampTargets()
        XCTAssertEqual(brief.targetWords, 15_000)
        XCTAssertEqual(brief.targetChapters, 5)

        brief.targetWords = 500_000
        brief.targetChapters = 100
        brief.clampTargets()
        XCTAssertEqual(brief.targetWords, 200_000)
        XCTAssertEqual(brief.targetChapters, 80)

        brief.targetWords = 70_000
        brief.targetChapters = 21
        brief.clampTargets()
        XCTAssertEqual(brief.targetWords, 70_000)
        XCTAssertEqual(brief.targetChapters, 21)
    }

    func testSeedTextCarriesBookChoices() {
        var brief = BookBrief()
        brief.title = "The Glass Cartographer"
        brief.targetWords = 70_000
        brief.targetChapters = 21
        brief.premise = "A living-map mystery."

        XCTAssertTrue(brief.seedText.contains("# The Glass Cartographer"))
        XCTAssertTrue(brief.seedText.contains("70000 words"))
        XCTAssertTrue(brief.seedText.contains("21 chapters"))
        XCTAssertTrue(brief.seedText.contains("A living-map mystery."))
        XCTAssertTrue(brief.seedText.contains("Not specified — let the pipeline propose options."))
    }

    @MainActor
    func testSaveBookBriefSkipsOverwriteWhenSeedWasCustomized() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("autonovel-seed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = StudioStore(projectURL: root)
        var brief = BookBrief()
        brief.title = "The Glass Cartographer"
        brief.author = "Ada"
        try store.saveBookBrief(brief)

        let seedURL = root.appendingPathComponent("seed.txt")
        XCTAssertEqual(try String(contentsOf: seedURL, encoding: .utf8), brief.seedText + "\n")

        brief.author = "Mara"
        try store.saveBookBrief(brief)
        XCTAssertEqual(try String(contentsOf: seedURL, encoding: .utf8), brief.seedText + "\n")
        XCTAssertTrue(try String(contentsOf: seedURL, encoding: .utf8).contains("Author: Mara"))

        let custom = "Polished story seed from DocumentEditorView.\n"
        try store.saveText(custom, for: .seed)

        brief.author = "Niko"
        try store.saveBookBrief(brief)

        XCTAssertEqual(try String(contentsOf: seedURL, encoding: .utf8), custom)
        XCTAssertEqual(store.loadBookBrief().author, "Niko")
    }

    @MainActor
    func testSaveBookBriefWritesGeneratedSeedWhenExistingSeedIsBlank() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("autonovel-blank-seed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = StudioStore(projectURL: root)
        let seedURL = root.appendingPathComponent("seed.txt")
        try Data().write(to: seedURL)

        var brief = BookBrief()
        brief.title = "The Glass Cartographer"
        brief.premise = "A mapmaker discovers that erased roads still remember their travelers."
        brief.protagonist = "Mara, an exacting apprentice who cannot get lost."
        brief.centralConflict = "The royal surveyor is deleting rebellious towns from reality."
        brief.worldHook = "Maps determine which places can physically exist."
        XCTAssertEqual(brief.requiredCompleted, 5)

        try store.saveBookBrief(brief)
        XCTAssertEqual(try String(contentsOf: seedURL, encoding: .utf8), brief.seedText + "\n")
        XCTAssertTrue(store.seedIsReady)

        try "   \n\t  \n".write(to: seedURL, atomically: true, encoding: .utf8)
        store.refresh()
        XCTAssertFalse(store.seedIsReady)

        try store.saveBookBrief(brief)
        XCTAssertEqual(try String(contentsOf: seedURL, encoding: .utf8), brief.seedText + "\n")
        XCTAssertTrue(store.seedIsReady)

        let custom = "Polished custom seed that must be preserved.\n"
        try custom.write(to: seedURL, atomically: true, encoding: .utf8)
        try store.saveBookBrief(brief)
        XCTAssertEqual(try String(contentsOf: seedURL, encoding: .utf8), custom)

        try Data().write(to: seedURL)
        store.refresh()
        XCTAssertEqual(store.loadBookBrief().requiredCompleted, 5)
        XCTAssertFalse(store.seedIsReady)
    }

    @MainActor
    func testBookBriefDecodesPartialJSONUsingDefaults() throws {
        let partialJSON = #"{"targetChapters":18}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BookBrief.self, from: partialJSON)
        var expectedPartial = BookBrief()
        expectedPartial.targetChapters = 18
        XCTAssertEqual(decoded, expectedPartial)
        XCTAssertEqual(decoded.targetChapters, 18)
        XCTAssertEqual(decoded.targetWords, 80_000)
        XCTAssertEqual(decoded.genre, "Fantasy")
        XCTAssertEqual(decoded.title, "")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("autonovel-brief-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try partialJSON.write(to: root.appendingPathComponent("book.json"))
        let store = StudioStore(projectURL: root)
        let loaded = store.loadBookBrief()
        XCTAssertEqual(loaded.targetChapters, 18)
        XCTAssertNotEqual(loaded.targetChapters, 24)
        XCTAssertEqual(loaded, expectedPartial)

        var complete = BookBrief()
        complete.title = "The Glass Cartographer"
        complete.author = "Ada"
        complete.genre = "Mystery"
        complete.audience = "YA"
        complete.pointOfView = "First person"
        complete.tense = "Present tense"
        complete.targetWords = 70_000
        complete.targetChapters = 21
        complete.premise = "A living-map mystery."
        complete.protagonist = "Mara"
        complete.protagonistWant = "To restore erased roads."
        complete.centralConflict = "A surveyor deleting towns."
        complete.stakes = "Places vanish."
        complete.worldHook = "Maps determine existence."
        complete.speculativeElement = "Living maps."
        complete.costsAndLimits = "Ink costs memory."
        complete.themes = "Memory."
        complete.toneAndPromise = "Quiet dread."
        complete.endingDirection = "The map remembers."
        complete.mustInclude = "A glass compass."
        complete.avoid = "Chosen ones."
        complete.contentNotes = "Mild peril."

        let completeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("autonovel-brief-complete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: completeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: completeRoot) }

        let completeStore = StudioStore(projectURL: completeRoot)
        try completeStore.saveBookBrief(complete)
        XCTAssertEqual(completeStore.loadBookBrief(), complete)
        let savedJSON = try String(
            contentsOf: completeRoot.appendingPathComponent("book.json"),
            encoding: .utf8
        )
        XCTAssertTrue(savedJSON.contains("\"targetChapters\""))
        XCTAssertFalse(savedJSON.contains("\"target_chapters\""))

        try store.saveBookBrief(loaded)
        XCTAssertEqual(store.loadBookBrief().targetChapters, 18)
        XCTAssertEqual(store.loadBookBrief(), expectedPartial)
    }

    @MainActor
    func testSeedIsReadyRequiresEssentialFieldsWhenBookBriefExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("autonovel-seed-ready-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = StudioStore(projectURL: root)
        var brief = BookBrief()
        brief.title = "The Glass Cartographer"
        try store.saveBookBrief(brief)

        let generatedSeed = try String(
            contentsOf: root.appendingPathComponent("seed.txt"),
            encoding: .utf8
        )
        XCTAssertGreaterThanOrEqual(
            generatedSeed.split(whereSeparator: { $0.isWhitespace }).count,
            40
        )
        XCTAssertEqual(store.loadBookBrief().requiredCompleted, 1)
        XCTAssertFalse(store.seedIsReady)

        brief.premise = "A mapmaker discovers that erased roads still remember their travelers."
        brief.protagonist = "Mara, an exacting apprentice who cannot get lost."
        brief.centralConflict = "The royal surveyor is deleting rebellious towns from reality."
        brief.worldHook = "Maps determine which places can physically exist."
        try store.saveBookBrief(brief)

        XCTAssertEqual(store.loadBookBrief().requiredCompleted, 5)
        XCTAssertTrue(store.seedIsReady)

        let seedOnly = FileManager.default.temporaryDirectory
            .appendingPathComponent("autonovel-seed-only-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: seedOnly, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: seedOnly) }

        let customSeed = (1...40).map { "word\($0)" }.joined(separator: " ") + "\n"
        try customSeed.write(
            to: seedOnly.appendingPathComponent("seed.txt"),
            atomically: true,
            encoding: .utf8
        )
        let seedOnlyStore = StudioStore(projectURL: seedOnly)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: seedOnly.appendingPathComponent("book.json").path)
        )
        XCTAssertTrue(seedOnlyStore.seedIsReady)
    }

    func testPipelineStateDecodesPartialState() throws {
        let json = #"{"phase":"drafting","chapters_drafted":3,"chapters_total":12}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(PipelineState.self, from: json)

        XCTAssertEqual(state.phase, "drafting")
        XCTAssertEqual(state.chaptersDrafted, 3)
        XCTAssertEqual(state.chaptersTotal, 12)
        XCTAssertEqual(state.foundationScore, 0)
        XCTAssertNil(state.novelScore)
        XCTAssertTrue(state.debts.isEmpty)
        XCTAssertEqual(state.status, "")
    }

    func testPipelineFailureDetailsDecode() throws {
        let json = #"{"phase":"drafting","status":"failed","novel_score":null,"last_error":{"phase":"drafting","step":"chapter_7","message":"Compute error","occurred_at":"2026-09-03T18:39:40","log_path":"/tmp/failure.log"}}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(PipelineState.self, from: json)

        XCTAssertEqual(state.status, "failed")
        XCTAssertEqual(state.lastError?.step, "chapter_7")
        XCTAssertEqual(state.lastError?.message, "Compute error")
        XCTAssertNil(state.novelScore)
    }

    func testFailedEvaluationHistoryIsNotShownAsSuccess() {
        let failed = ActivityRecord(
            index: 0,
            columns: ["abc", "revision-cycle-1", "-1.0", "1000", "cycle", "No score"]
        )
        let discarded = ActivityRecord(
            index: 1,
            columns: ["discarded", "ch02", "5.5", "1000", "discard", "Retry"]
        )
        let forced = ActivityRecord(
            index: 2,
            columns: ["abc123", "ch01", "?", "1200", "forced", "Chapter 1: kept after max attempts"]
        )

        XCTAssertTrue(failed.isFailure)
        XCTAssertEqual(failed.resultSymbol, "exclamationmark.triangle.fill")
        XCTAssertTrue(discarded.isDiscarded)
        XCTAssertEqual(discarded.resultSymbol, "arrow.counterclockwise.circle")
        XCTAssertTrue(forced.isForced)
        XCTAssertNotEqual(forced.resultSymbol, "checkmark.circle")
        XCTAssertEqual(forced.resultSymbol, "exclamationmark.triangle.fill")
    }

    func testForcedEvaluationHistoryIsNotShownAsSuccess() {
        let forced = ActivityRecord(
            index: 0,
            columns: ["deadbeef", "ch03", "?", "1840", "forced", "Chapter 3: kept after max attempts"]
        )

        XCTAssertTrue(forced.isForced)
        XCTAssertFalse(forced.isFailure)
        XCTAssertFalse(forced.isDiscarded)
        XCTAssertNotEqual(forced.resultSymbol, "checkmark.circle")
        XCTAssertEqual(forced.resultSymbol, "exclamationmark.triangle.fill")
    }

    func testChapterWithoutHeadingUsesStableNumberInsteadOfProseAsTitle() {
        let url = URL(fileURLWithPath: "/tmp/ch_01.md")
        let chapter = ChapterInfo.parse(
            number: 1,
            url: url,
            text: "The rain started before midnight. It kept Mara awake.\n\nA second paragraph."
        )

        XCTAssertEqual(chapter.title, "Chapter 01")
        XCTAssertEqual(chapter.excerpt, "The rain started before midnight. It kept Mara awake.")
        XCTAssertEqual(chapter.words, 12)
    }

    func testChapterHeadingBecomesTitleAndExcerptRemainsSeparate() {
        let url = URL(fileURLWithPath: "/tmp/ch_12.md")
        let chapter = ChapterInfo.parse(
            number: 12,
            url: url,
            text: "# The Vanishing Road\n\nMara folded the impossible map."
        )

        XCTAssertEqual(chapter.title, "The Vanishing Road")
        XCTAssertEqual(chapter.excerpt, "Mara folded the impossible map.")
        XCTAssertEqual(chapter.numberLabel, "12")
    }

    func testProviderPresetInferenceSupportsLocalAndCustomEndpoints() {
        XCTAssertEqual(
            ProviderPreset.infer(apiProtocol: .openAICompatible, baseURL: "http://127.0.0.1:8081"),
            .local
        )
        XCTAssertEqual(
            ProviderPreset.infer(apiProtocol: .openAICompatible, baseURL: "https://models.example.org"),
            .custom
        )
        XCTAssertEqual(
            ProviderPreset.infer(apiProtocol: .anthropic, baseURL: "https://gateway.example.org"),
            .anthropic
        )
    }

    func testSettingsLoadDoesNotApplyPresetToSavedURL() {
        var form = ProviderConfiguration()
        XCTAssertEqual(form.preset, .local)
        XCTAssertEqual(form.baseURL, ProviderPreset.local.defaultBaseURL)

        var savedAnthropic = ProviderConfiguration()
        savedAnthropic.preset = .anthropic
        savedAnthropic.apiProtocol = .anthropic
        savedAnthropic.baseURL = "https://gateway.example.org"
        savedAnthropic.contextSize = 1_000_000
        form = savedAnthropic
        XCTAssertEqual(form.preset, .anthropic)
        XCTAssertEqual(form.baseURL, "https://gateway.example.org")
        XCTAssertNotEqual(form.baseURL, ProviderPreset.anthropic.defaultBaseURL)

        var savedOllama = ProviderConfiguration()
        savedOllama.preset = .ollama
        savedOllama.apiProtocol = .openAICompatible
        savedOllama.baseURL = "http://192.168.1.5:11434"
        form = savedOllama
        XCTAssertEqual(form.preset, .ollama)
        XCTAssertEqual(form.baseURL, "http://192.168.1.5:11434")
        XCTAssertNotEqual(form.baseURL, ProviderPreset.ollama.defaultBaseURL)

        form.applyPreset(.local)
        XCTAssertEqual(form.preset, .local)
        XCTAssertEqual(form.apiProtocol, .openAICompatible)
        XCTAssertEqual(form.baseURL, "http://127.0.0.1:8080")

        form.applyPreset(.anthropic)
        XCTAssertEqual(form.preset, .anthropic)
        XCTAssertEqual(form.apiProtocol, .anthropic)
        XCTAssertEqual(form.baseURL, "https://api.anthropic.com")
    }

    func testProviderValidationLimitsNoAuthenticationToLocalhost() throws {
        var configuration = ProviderConfiguration()
        configuration.baseURL = "http://127.0.0.1:11434"
        configuration.writerModel = "writer"
        configuration.judgeModel = "judge"
        configuration.reviewModel = "reviewer"
        configuration.credentialMode = .none

        XCTAssertNoThrow(try configuration.validated())

        configuration.baseURL = "https://models.example.org/v1"
        XCTAssertThrowsError(try configuration.validated())
    }

    func testEnvironmentUpdatePreservesUnrelatedConfiguration() {
        let source = "# Keep this comment\nFAL_KEY=existing\nAUTONOVEL_LLM_PROVIDER=anthropic\n"
        let updated = EnvironmentFileStore.updating(
            source,
            with: [
                "AUTONOVEL_LLM_PROVIDER": "openai",
                "AUTONOVEL_API_BASE_URL": "https://models.example.org/v1",
            ]
        )

        XCTAssertTrue(updated.contains("# Keep this comment"))
        XCTAssertTrue(updated.contains("FAL_KEY=existing"))
        XCTAssertTrue(updated.contains("AUTONOVEL_LLM_PROVIDER=openai"))
        XCTAssertTrue(updated.contains("AUTONOVEL_API_BASE_URL=https://models.example.org/v1"))
    }

    func testManagedProviderCredentialLivesInSecretStoreNotProjectFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("autonovel-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "FAL_KEY=preserve-me\nAUTONOVEL_API_KEY=old-plaintext\n".write(
            to: root.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )

        var configuration = ProviderConfiguration()
        configuration.baseURL = "http://127.0.0.1:8081"
        configuration.writerModel = "writer-model"
        configuration.judgeModel = "judge-model"
        configuration.reviewModel = "review-model"
        configuration.credentialMode = .managedKey
        configuration.pendingAPIKey = "private-test-key"

        let secrets = MemorySecretStore()
        let environmentStore = EnvironmentFileStore(projectURL: root, secretStore: secrets)
        let saved = try environmentStore.save(configuration)
        let envText = try String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8)
        let values = EnvironmentFileStore.values(in: envText)
        let keyURL = root.appendingPathComponent(EnvironmentFileStore.managedKeyPath)

        XCTAssertTrue(saved.hasManagedAPIKey)
        XCTAssertEqual(try secrets.read(), "private-test-key")
        XCTAssertEqual(values["FAL_KEY"], "preserve-me")
        XCTAssertEqual(values["AUTONOVEL_API_KEY_FILE"], KeychainSecretStore.sentinel)
        XCTAssertNil(values["AUTONOVEL_API_KEY"])
        XCTAssertFalse(envText.contains("private-test-key"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: keyURL.path))
    }

    func testLegacyManagedKeyFileMigratesIntoSecretStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("autonovel-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keyURL = root.appendingPathComponent(EnvironmentFileStore.managedKeyPath)
        try FileManager.default.createDirectory(
            at: keyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "legacy-file-key\n".write(to: keyURL, atomically: true, encoding: .utf8)
        try "AUTONOVEL_API_KEY_FILE=\(EnvironmentFileStore.managedKeyPath)\n".write(
            to: root.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )

        let secrets = MemorySecretStore()
        let loaded = EnvironmentFileStore(projectURL: root, secretStore: secrets).load()

        XCTAssertEqual(loaded.credentialMode, .managedKey)
        XCTAssertTrue(loaded.hasManagedAPIKey)
        XCTAssertEqual(try secrets.read(), "legacy-file-key")
        XCTAssertFalse(FileManager.default.fileExists(atPath: keyURL.path))
    }

    func testPipelineEnvironmentInjectsKeyAndDropsKeyFilePointer() {
        let environment = PipelineRunner.processEnvironment(
            base: [
                "PATH": "/usr/bin",
                "AUTONOVEL_API_KEY_FILE": KeychainSecretStore.sentinel,
            ],
            extra: ["AUTONOVEL_API_KEY": "from-keychain"]
        )

        XCTAssertEqual(environment["AUTONOVEL_API_KEY"], "from-keychain")
        XCTAssertEqual(environment["PYTHONUNBUFFERED"], "1")
        XCTAssertNil(environment["AUTONOVEL_API_KEY_FILE"])
        XCTAssertEqual(environment["PATH"], "/usr/bin")
    }

    func testProcessEnvironmentPrependsResolvedUVDirectoryToPATH() {
        let uvDirectory = "/tmp/fake-uv-bin"
        let environment = PipelineRunner.processEnvironment(
            base: [
                "PATH": "/usr/bin",
                "AUTONOVEL_API_KEY_FILE": KeychainSecretStore.sentinel,
            ],
            extra: ["AUTONOVEL_API_KEY": "from-keychain"],
            pathPrepend: [uvDirectory]
        )

        XCTAssertTrue(environment["PATH"]?.hasPrefix(uvDirectory + ":") == true)
        XCTAssertEqual(environment["PYTHONUNBUFFERED"], "1")
        XCTAssertEqual(environment["AUTONOVEL_API_KEY"], "from-keychain")
        XCTAssertNil(environment["AUTONOVEL_API_KEY_FILE"])
    }

    func testPipelineEnvironmentDoesNotInjectLeftoverKeychainSecretOutsideManagedKey() throws {
        let secrets = MemorySecretStore()
        try secrets.write("leftover-keychain-secret")
        let store = EnvironmentFileStore(
            projectURL: FileManager.default.temporaryDirectory,
            secretStore: secrets
        )

        XCTAssertEqual(
            store.pipelineEnvironment(credentialMode: .managedKey),
            ["AUTONOVEL_API_KEY": "leftover-keychain-secret"]
        )

        for mode in CredentialMode.allCases where mode != .managedKey {
            let extra = store.pipelineEnvironment(credentialMode: mode)
            XCTAssertTrue(extra.isEmpty, "Unexpected extra environment for \(mode.rawValue)")
            let environment = PipelineRunner.processEnvironment(
                base: [
                    "PATH": "/usr/bin",
                    "AUTONOVEL_API_KEY_FILE": "/tmp/user.key",
                ],
                extra: extra
            )
            XCTAssertEqual(environment["AUTONOVEL_API_KEY_FILE"], "/tmp/user.key")
            XCTAssertNil(environment["AUTONOVEL_API_KEY"])
        }
    }

    func testOlderEmptyManagedKeyAssignmentIsRemovedWithoutAnotherSave() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("autonovel-empty-key-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "AUTONOVEL_API_KEY_FILE=\(KeychainSecretStore.sentinel)\nAUTONOVEL_API_KEY=\nFAL_KEY=preserve-me\n".write(
            to: root.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )

        let secrets = MemorySecretStore()
        try secrets.write("from-keychain")
        let store = EnvironmentFileStore(projectURL: root, secretStore: secrets)
        let loaded = store.load()
        let extra = store.pipelineEnvironment(credentialMode: .managedKey)
        let envText = try String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8)
        let values = EnvironmentFileStore.values(in: envText)

        XCTAssertEqual(loaded.credentialMode, .managedKey)
        XCTAssertEqual(extra, ["AUTONOVEL_API_KEY": "from-keychain"])
        XCTAssertNil(values["AUTONOVEL_API_KEY"])
        XCTAssertFalse(envText.contains("AUTONOVEL_API_KEY="))
        XCTAssertEqual(values["FAL_KEY"], "preserve-me")
        XCTAssertEqual(values["AUTONOVEL_API_KEY_FILE"], KeychainSecretStore.sentinel)
    }

    func testKeychainRoundTripWhenAvailable() throws {
        let store = KeychainSecretStore(
            service: "org.nousresearch.autonovelstudio.tests",
            account: "test-\(UUID().uuidString)"
        )
        do {
            try store.write("round-trip-secret")
        } catch {
            throw XCTSkip("Keychain unavailable: \(error)")
        }
        defer { try? store.delete() }
        XCTAssertEqual(try store.read(), "round-trip-secret")
    }
}
