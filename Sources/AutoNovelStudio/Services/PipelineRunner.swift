import Foundation
import Observation

@MainActor
@Observable
final class PipelineRunner {
    private(set) var isRunning = false
    private(set) var label = "Idle"
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

    init(projectURL: URL) {
        self.projectURL = projectURL
    }

    func run(label: String, pythonArguments: [String]) {
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
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
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

        installReader(for: stdout)
        installReader(for: stderr)
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
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
        label = "Idle"
    }

    private func installReader(for pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.append(text) }
        }
    }

    private func append(_ text: String) {
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
}
