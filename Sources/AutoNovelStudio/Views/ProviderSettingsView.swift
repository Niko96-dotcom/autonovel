import SwiftUI

struct ProviderSettingsView: View {
    @Bindable var store: StudioStore

    @State private var configuration = ProviderConfiguration()
    @State private var didLoad = false
    @State private var saveMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    settingsHeader
                    Divider().padding(.vertical, 20)
                    providerSection
                    Divider().padding(.vertical, 20)
                    modelsSection
                    Divider().padding(.vertical, 20)
                    authenticationSection
                }
                .padding(26)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
            .tabItem { Label("Model Provider", systemImage: "server.rack") }

            aboutView
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 660, height: 650)
        .task {
            store.reloadProviderConfiguration()
            configuration = store.providerConfiguration
            didLoad = true
        }
        .onChange(of: configuration.preset) { previous, selected in
            guard didLoad, previous != selected else { return }
            configuration.applyPreset(selected)
            saveMessage = nil
            errorMessage = nil
        }
        .onChange(of: configuration.apiProtocol) { _, selected in
            guard didLoad, configuration.preset.apiProtocol != selected else { return }
            configuration.preset = .custom
        }
        .onChange(of: configuration.baseURL) { _, selected in
            guard didLoad,
                  configuration.preset != .custom,
                  let expected = configuration.preset.defaultBaseURL,
                  expected.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    != selected.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            else { return }
            configuration.preset = .custom
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(StudioTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                SectionEyebrow(text: "Intelligence")
                Text("Choose the mind behind the manuscript")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text("Use a hosted API, a private local model, or any endpoint that speaks one of AutoNovel’s supported protocols.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var providerSection: some View {
        SettingsSection(
            number: "01",
            title: "Provider",
            detail: "Presets fill the endpoint and protocol; every value stays editable."
        ) {
            Picker("Provider", selection: $configuration.preset) {
                ForEach(ProviderPreset.allCases) { preset in
                    Label(preset.title, systemImage: preset.symbol).tag(preset)
                }
            }
            .pickerStyle(.menu)

            Picker("API protocol", selection: $configuration.apiProtocol) {
                ForEach(ModelAPIProtocol.allCases) { apiProtocol in
                    Text(apiProtocol.title).tag(apiProtocol)
                }
            }
            .pickerStyle(.menu)

            TextField("https://api.example.com", text: $configuration.baseURL, prompt: Text("API base URL"))
                .textFieldStyle(.roundedBorder)

            Label(configuration.apiProtocol.detail, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelsSection: some View {
        SettingsSection(
            number: "02",
            title: "Model roles",
            detail: "Use one model everywhere or assign different models to writing, judging, and review."
        ) {
            modelField("Writer", detail: "Drafts and revisions", text: $configuration.writerModel)
            modelField("Judge", detail: "Chapter-level evaluation", text: $configuration.judgeModel)
            modelField("Reviewer", detail: "Whole-book critique", text: $configuration.reviewModel)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Context window").font(.subheadline.weight(.medium))
                    Text("The maximum tokens your selected backend accepts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Tokens", value: $configuration.contextSize, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var authenticationSection: some View {
        SettingsSection(
            number: "03",
            title: "Authentication",
            detail: "Secrets never appear in the interface after saving and are excluded from Git."
        ) {
            Picker("Credential source", selection: $configuration.credentialMode) {
                ForEach(CredentialMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            switch configuration.credentialMode {
            case .existingEnvironment:
                Label(
                    configuration.hasEnvironmentCredential
                        ? "Using a credential already defined in .env."
                        : "No existing environment credential was detected.",
                    systemImage: configuration.hasEnvironmentCredential ? "checkmark.circle.fill" : "exclamationmark.triangle"
                )
                .foregroundStyle(configuration.hasEnvironmentCredential ? StudioTheme.success : .orange)
                .font(.subheadline)
            case .managedKey:
                SecureField(
                    configuration.hasManagedAPIKey ? "Stored key — enter only to replace" : "Paste API key",
                    text: $configuration.pendingAPIKey
                )
                .textFieldStyle(.roundedBorder)
                Label("Stored in a private 0600 file inside .autonovel/secrets.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .keyFile:
                TextField("/absolute/path/to/api-key", text: $configuration.keyFilePath)
                    .textFieldStyle(.roundedBorder)
                Text("The pipeline reads the first non-empty value from this file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .none:
                Label("Only choose this for a trusted localhost server that does not require authentication.", systemImage: "house.and.flag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            Group {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if let saveMessage {
                    Label(saveMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(StudioTheme.success)
                } else {
                    Text("Settings apply to every pipeline command in this project.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(2)

            Spacer()

            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Save & Check Connection", systemImage: "bolt.horizontal.circle") {
                if save() { store.runModelCheck() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.runner.isRunning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThickMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var aboutView: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(StudioTheme.accent)
            Text("AutoNovel Studio")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
            Text("An open, local-first writing studio for building, evaluating, revising, and exporting complete novels.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Text("Your manuscript and provider configuration stay in the project you control.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func modelField(_ title: String, detail: String, text: Binding<String>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            TextField("Model identifier", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try store.saveProviderConfiguration(configuration)
            configuration = store.providerConfiguration
            errorMessage = nil
            saveMessage = "Configuration saved"
            return true
        } catch {
            saveMessage = nil
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let number: String
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(number: String, title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(number)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
