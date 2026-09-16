import Foundation

enum ModelAPIProtocol: String, CaseIterable, Identifiable {
    case openAICompatible = "openai"
    case anthropic = "anthropic"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible: "OpenAI compatible"
        case .anthropic: "Anthropic Messages"
        }
    }

    var detail: String {
        switch self {
        case .openAICompatible: "Works with OpenAI, llama.cpp, Ollama, LM Studio, vLLM, and compatible gateways"
        case .anthropic: "Anthropic Messages API"
        }
    }
}

enum ProviderPreset: String, CaseIterable, Identifiable {
    case local
    case openAI
    case anthropic
    case ollama
    case lmStudio
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: "Local server"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .custom: "Custom endpoint"
        }
    }

    var symbol: String {
        switch self {
        case .local: "desktopcomputer"
        case .openAI: "cloud"
        case .anthropic: "sparkles"
        case .ollama: "shippingbox"
        case .lmStudio: "macwindow"
        case .custom: "network"
        }
    }

    var apiProtocol: ModelAPIProtocol {
        self == .anthropic ? .anthropic : .openAICompatible
    }

    var defaultBaseURL: String? {
        switch self {
        case .local: "http://127.0.0.1:8080"
        case .openAI: "https://api.openai.com"
        case .anthropic: "https://api.anthropic.com"
        case .ollama: "http://127.0.0.1:11434"
        case .lmStudio: "http://127.0.0.1:1234"
        case .custom: nil
        }
    }

    static func infer(apiProtocol: ModelAPIProtocol, baseURL: String) -> ProviderPreset {
        guard apiProtocol == .openAICompatible else { return .anthropic }
        let normalized = baseURL.lowercased()
        if normalized.contains("api.openai.com") { return .openAI }
        if normalized.contains(":11434") { return .ollama }
        if normalized.contains(":1234") { return .lmStudio }
        if ["127.0.0.1", "localhost", "::1"].contains(URL(string: normalized)?.host ?? "") {
            return .local
        }
        return .custom
    }
}

enum CredentialMode: String, CaseIterable, Identifiable {
    case existingEnvironment
    case managedKey
    case keyFile
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existingEnvironment: "Existing environment"
        case .managedKey: "Private API key"
        case .keyFile: "Existing key file"
        case .none: "No authentication"
        }
    }
}

struct ProviderConfiguration: Equatable {
    var preset: ProviderPreset = .local
    var apiProtocol: ModelAPIProtocol = .openAICompatible
    var baseURL = "http://127.0.0.1:8080"
    var writerModel = ""
    var judgeModel = ""
    var reviewModel = ""
    var contextSize = 32_768
    var credentialMode: CredentialMode = .none
    var keyFilePath = ""
    var pendingAPIKey = ""
    var hasManagedAPIKey = false
    var hasEnvironmentCredential = false

    mutating func applyPreset(_ newPreset: ProviderPreset) {
        preset = newPreset
        guard newPreset != .custom else { return }
        apiProtocol = newPreset.apiProtocol
        if let defaultBaseURL = newPreset.defaultBaseURL {
            baseURL = defaultBaseURL
        }
        if newPreset == .anthropic, contextSize == 32_768 {
            contextSize = 1_000_000
        } else if newPreset != .anthropic, contextSize == 1_000_000 {
            contextSize = 32_768
        }
    }

    func validated() throws -> ProviderConfiguration {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedBaseURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            throw ProviderConfigurationError("Enter a complete HTTP or HTTPS API base URL.")
        }
        guard !writerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderConfigurationError("Enter the model used for writing.")
        }
        guard !judgeModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderConfigurationError("Enter the model used for chapter evaluation.")
        }
        guard !reviewModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderConfigurationError("Enter the model used for whole-book review.")
        }
        guard contextSize >= 1_024 else {
            throw ProviderConfigurationError("The context window must be at least 1,024 tokens.")
        }
        if credentialMode == .none {
            let localHosts = ["127.0.0.1", "localhost", "::1"]
            guard apiProtocol == .openAICompatible,
                  let host = url.host?.lowercased(),
                  localHosts.contains(host)
            else {
                throw ProviderConfigurationError("No authentication is only available for a localhost OpenAI-compatible server.")
            }
        }
        if credentialMode == .keyFile,
           keyFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProviderConfigurationError("Choose the file that contains the API key.")
        }
        if credentialMode == .existingEnvironment, !hasEnvironmentCredential {
            throw ProviderConfigurationError("No existing environment credential was detected.")
        }
        if credentialMode == .managedKey,
           pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !hasManagedAPIKey {
            throw ProviderConfigurationError("Enter an API key to store privately on this Mac.")
        }
        return self
    }
}

struct ProviderConfigurationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
