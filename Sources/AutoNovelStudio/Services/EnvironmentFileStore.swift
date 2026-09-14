import Foundation

struct EnvironmentFileStore {
    static let managedKeyPath = ".autonovel/secrets/text-model-api-key"

    let projectURL: URL

    private var environmentURL: URL { projectURL.appendingPathComponent(".env") }
    private var managedKeyURL: URL { projectURL.appendingPathComponent(Self.managedKeyPath) }

    func load() -> ProviderConfiguration {
        let text = (try? String(contentsOf: environmentURL, encoding: .utf8)) ?? ""
        let values = Self.values(in: text)
        let apiProtocol = ModelAPIProtocol(rawValue: values["AUTONOVEL_LLM_PROVIDER"] ?? "")
            ?? ((values["AUTONOVEL_API_BASE_URL"] ?? "").contains("anthropic.com") ? .anthropic : .openAICompatible)
        let defaultURL = apiProtocol == .anthropic ? "https://api.anthropic.com" : "https://api.openai.com"
        let baseURL = values["AUTONOVEL_API_BASE_URL"] ?? defaultURL
        let keyFilePath = values["AUTONOVEL_API_KEY_FILE"] ?? ""
        let managedKeyExists = FileManager.default.fileExists(atPath: managedKeyURL.path)
        let directCredentialKeys = ["AUTONOVEL_API_KEY", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"]
        let directCredentialExists = directCredentialKeys.contains {
            !(values[$0] ?? ProcessInfo.processInfo.environment[$0] ?? "").isEmpty
        }

        let credentialMode: CredentialMode
        if keyFilePath == Self.managedKeyPath || URL(fileURLWithPath: keyFilePath).standardizedFileURL == managedKeyURL.standardizedFileURL {
            credentialMode = .managedKey
        } else if !keyFilePath.isEmpty {
            credentialMode = .keyFile
        } else if directCredentialExists {
            credentialMode = .existingEnvironment
        } else {
            credentialMode = .none
        }

        return ProviderConfiguration(
            preset: ProviderPreset.infer(apiProtocol: apiProtocol, baseURL: baseURL),
            apiProtocol: apiProtocol,
            baseURL: baseURL,
            writerModel: values["AUTONOVEL_WRITER_MODEL"] ?? "",
            judgeModel: values["AUTONOVEL_JUDGE_MODEL"] ?? values["AUTONOVEL_WRITER_MODEL"] ?? "",
            reviewModel: values["AUTONOVEL_REVIEW_MODEL"] ?? values["AUTONOVEL_WRITER_MODEL"] ?? "",
            contextSize: Int(values["AUTONOVEL_CONTEXT_SIZE"] ?? "") ?? (apiProtocol == .anthropic ? 1_000_000 : 32_768),
            credentialMode: credentialMode,
            keyFilePath: keyFilePath,
            pendingAPIKey: "",
            hasManagedAPIKey: managedKeyExists,
            hasEnvironmentCredential: directCredentialExists
        )
    }

    func save(_ proposedConfiguration: ProviderConfiguration) throws -> ProviderConfiguration {
        var configuration = try proposedConfiguration.validated()
        var updates = [
            "AUTONOVEL_LLM_PROVIDER": configuration.apiProtocol.rawValue,
            "AUTONOVEL_API_BASE_URL": configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            "AUTONOVEL_WRITER_MODEL": configuration.writerModel.trimmingCharacters(in: .whitespacesAndNewlines),
            "AUTONOVEL_JUDGE_MODEL": configuration.judgeModel.trimmingCharacters(in: .whitespacesAndNewlines),
            "AUTONOVEL_REVIEW_MODEL": configuration.reviewModel.trimmingCharacters(in: .whitespacesAndNewlines),
            "AUTONOVEL_CONTEXT_SIZE": String(configuration.contextSize),
        ]

        switch configuration.credentialMode {
        case .existingEnvironment:
            updates["AUTONOVEL_API_KEY_FILE"] = ""
        case .managedKey:
            let pendingKey = configuration.pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pendingKey.isEmpty {
                try writeManagedKey(pendingKey)
            }
            updates["AUTONOVEL_API_KEY_FILE"] = Self.managedKeyPath
            configuration.hasManagedAPIKey = true
        case .keyFile:
            updates["AUTONOVEL_API_KEY_FILE"] = configuration.keyFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        case .none:
            updates["AUTONOVEL_API_KEY_FILE"] = ""
            updates["AUTONOVEL_API_KEY"] = ""
            updates["ANTHROPIC_API_KEY"] = ""
            updates["OPENAI_API_KEY"] = ""
        }

        let existing = (try? String(contentsOf: environmentURL, encoding: .utf8)) ?? ""
        let updated = Self.updating(existing, with: updates)
        try updated.write(to: environmentURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: environmentURL.path)
        configuration.pendingAPIKey = ""
        return configuration
    }

    private func writeManagedKey(_ key: String) throws {
        let directory = managedKeyURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try (key + "\n").write(to: managedKeyURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: managedKeyURL.path)
    }

    static func values(in text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"") || value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = value
        }
        return values
    }

    static func updating(_ text: String, with updates: [String: String]) -> String {
        var seen = Set<String>()
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            guard let key = assignmentKey(in: line), let value = updates[key] else {
                lines.append(line)
                continue
            }
            guard !seen.contains(key) else { continue }
            lines.append("\(key)=\(dotenvValue(value))")
            seen.insert(key)
        }

        let missing = updates.keys.sorted().filter { !seen.contains($0) }
        if !missing.isEmpty {
            while lines.last?.isEmpty == true { lines.removeLast() }
            if !lines.isEmpty { lines.append("") }
            lines.append("# Managed by AutoNovel Studio")
            for key in missing {
                lines.append("\(key)=\(dotenvValue(updates[key] ?? ""))")
            }
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func assignmentKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { return nil }
        let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    private static func dotenvValue(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#\"'"))) != nil else {
            return value
        }
        return "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
