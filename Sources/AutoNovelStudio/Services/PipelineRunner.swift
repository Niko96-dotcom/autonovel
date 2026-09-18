import Foundation
import Observation

@MainActor
@Observable
final class PipelineRunner {
    private(set) var isRunning = false
    private(set) var label = "Ready"
    private(set) var output = ""
    private(set) var exitCode: Int32?
    private(set) var startedAt: Date?
    private(set) var lastSuccessfulCheck: Date?
    var errorMessage: String?

    var modelStatus: String? { Self.latestModelStatus(in: output) }

    nonisolated static func latestModelStatus(in output: String) -> String? {
        // Only use complete lines: pipe chunks may split a progress message.
        for line in output.components(separatedBy: "\n").dropLast().reversed() {
            for prefix in ["[LLM progress] ", "[LLM request] "] where line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private let projectURL: URL
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutDecoder = UTF8StreamDecoder()
    private var stderrDecoder = UTF8StreamDecoder()

    init(projectURL: URL) {
        self.projectURL = projectURL
    }

    nonisolated static func processEnvironment(
        base: [String: String],
        extra: [String: String] = [:],
        pathPrepend: [String] = []
    ) -> [String: String] {
        var environment = base
        environment["PYTHONUNBUFFERED"] = "1"
        if extra.keys.contains("AUTONOVEL_API_KEY") {
            environment.removeValue(forKey: "AUTONOVEL_API_KEY_FILE")
        }
        for (key, value) in extra {
            environment[key] = value
        }
        if !pathPrepend.isEmpty {
            var components: [String] = []
            if let path = environment["PATH"], !path.isEmpty {
                components = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            }
            for directory in pathPrepend.reversed() where !directory.isEmpty {
                if components.first != directory {
                    components.insert(directory, at: 0)
                }
            }
            environment["PATH"] = components.joined(separator: ":")
        }
        return environment
    }

    func run(label: String, pythonArguments: [String], extraEnvironment: [String: String] = [:]) {
        guard !isRunning else { return }
        guard let uv = resolveUV() else {
            errorMessage = "Could not find uv. Expected it in ~/.local/bin or Homebrew."
            return
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = uv
        process.arguments = ["run", "python"] + pythonArguments
        process.currentDirectoryURL = projectURL
        process.environment = Self.processEnvironment(
            base: ProcessInfo.processInfo.environment,
            extra: extraEnvironment,
            pathPrepend: [uv.deletingLastPathComponent().path]
        )
        process.standardOutput = stdout
        process.standardError = stderr

        output = "$ uv run python \(pythonArguments.joined(separator: " "))\n\n"
        self.label = label
        exitCode = nil
        errorMessage = nil
        startedAt = Date()
        isRunning = true
        self.process = process
        stdoutPipe = stdout
        stderrPipe = stderr
        stdoutDecoder = UTF8StreamDecoder()
        stderrDecoder = UTF8StreamDecoder()

        let stdoutDecoder = self.stdoutDecoder
        let stderrDecoder = self.stderrDecoder
        installReader(for: stdout, decoder: stdoutDecoder)
        installReader(for: stderr, decoder: stderrDecoder)
        process.terminationHandler = { [weak self] finished in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let extraStdout = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
            let extraStderr = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
            Task { @MainActor in
                guard let self else { return }
                self.append(stdoutDecoder.consume(extraStdout, flush: true))
                self.append(stderrDecoder.consume(extraStderr, flush: true))
                self.isRunning = false
                self.exitCode = finished.terminationStatus
                if finished.terminationStatus == 0 {
                    self.label = "Finished"
                    if pythonArguments == ["check_llm.py"] {
                        self.lastSuccessfulCheck = Date()
                    }
                } else {
                    self.label = "Failed"
                    self.errorMessage = "The command exited with code \(finished.terminationStatus)."
                }
                self.releasePipes()
            }
        }

        do {
            try process.run()
        } catch {
            isRunning = false
            self.label = "Failed"
            errorMessage = error.localizedDescription
            releasePipes()
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        append("\n[Stopping at your request…]\n")
        process.interrupt()
    }

    func clearOutput() {
        guard !isRunning else { return }
        output = ""
        exitCode = nil
        errorMessage = nil
        label = "Ready"
    }

    private func installReader(for pipe: Pipe, decoder: UTF8StreamDecoder) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = decoder.consume(data)
            guard !text.isEmpty else { return }
            Task { @MainActor in self?.append(text) }
        }
    }

    private func append(_ text: String) {
        guard !text.isEmpty else { return }
        output += text
        if output.count > 120_000 {
            output = String(output.suffix(100_000))
        }
    }

    private func releasePipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        stdoutDecoder = UTF8StreamDecoder()
        stderrDecoder = UTF8StreamDecoder()
    }

    private func resolveUV() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/uv"),
            URL(fileURLWithPath: "/opt/homebrew/bin/uv"),
            URL(fileURLWithPath: "/usr/local/bin/uv"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Decodes UTF-8 from pipe chunks that may split a code point across callbacks.
    final class UTF8StreamDecoder: @unchecked Sendable {
        private var leftover: [UInt8] = []
        private let lock = NSLock()

        func consume(_ data: Data, flush: Bool = false) -> String {
            lock.lock()
            defer { lock.unlock() }
            if !data.isEmpty {
                leftover.append(contentsOf: data)
            }
            guard !leftover.isEmpty else { return "" }

            if flush {
                let text = String(decoding: leftover, as: UTF8.self)
                leftover.removeAll(keepingCapacity: true)
                return text
            }

            if let text = String(bytes: leftover, encoding: .utf8) {
                leftover.removeAll(keepingCapacity: true)
                return text
            }

            let prefixLength = Self.completePrefixLength(leftover)
            guard prefixLength > 0 else { return "" }
            let prefix = leftover.prefix(prefixLength)
            leftover.removeFirst(prefixLength)
            return String(bytes: prefix, encoding: .utf8)
                ?? String(decoding: prefix, as: UTF8.self)
        }

        private static func completePrefixLength(_ bytes: [UInt8]) -> Int {
            let count = bytes.count
            guard count > 0 else { return 0 }

            var idx = count - 1
            var continuationBytes = 0
            while idx >= 0, bytes[idx] & 0b1100_0000 == 0b1000_0000 {
                continuationBytes += 1
                if continuationBytes == 3 || idx == 0 { break }
                idx -= 1
            }

            let lead = bytes[idx]
            let expectedContinuations: Int
            if lead & 0b1000_0000 == 0 {
                expectedContinuations = 0
            } else if lead & 0b1110_0000 == 0b1100_0000 {
                expectedContinuations = 1
            } else if lead & 0b1111_0000 == 0b1110_0000 {
                expectedContinuations = 2
            } else if lead & 0b1111_1000 == 0b1111_0000 {
                expectedContinuations = 3
            } else {
                return count
            }

            if continuationBytes < expectedContinuations {
                return idx
            }
            return count
        }
    }
}
