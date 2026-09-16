import XCTest
@testable import AutoNovelStudio

final class AutoNovelStudioTests: XCTestCase {
    func testLatestModelStatusTracksNewRequestAndIgnoresIncompleteLines() {
        let output = "[LLM progress] Response complete: 100 words.\nChecking chapter\n[LLM request] Reading context...\n[LLM progress] 2 wor"
        XCTAssertEqual(PipelineRunner.latestModelStatus(in: output), "Reading context...")
        XCTAssertEqual(PipelineRunner.latestModelStatus(in: output + "ds received.\n"), "2 words received.")
        XCTAssertNil(PipelineRunner.latestModelStatus(in: "Starting pipeline\n"))
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

        XCTAssertTrue(failed.isFailure)
        XCTAssertEqual(failed.resultSymbol, "exclamationmark.triangle.fill")
        XCTAssertTrue(discarded.isDiscarded)
        XCTAssertEqual(discarded.resultSymbol, "arrow.counterclockwise.circle")
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
