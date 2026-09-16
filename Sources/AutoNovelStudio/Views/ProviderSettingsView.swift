import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case provider
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: "Provider"
        case .about: "About"
        }
    }
}

struct ProviderSettingsView: View {
    @Bindable var store: StudioStore

    @State private var configuration = ProviderConfiguration()
    @State private var didLoad = false
    @State private var pane = SettingsPane.provider
    @State private var saveMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch pane {
                case .provider:
                    providerScroll
                case .about:
                    aboutView
                }
            }
            .navigationTitle(pane.title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Settings pane", selection: $pane) {
                        ForEach(SettingsPane.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minWidth: 220)
                }
                if pane == .provider {
                    ToolbarItem(placement: .automatic) {
                        Button("Save") { save() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save & Check Connection") {
                            if save() { store.runModelCheck() }
                        }
                        .disabled(store.runner.isRunning)
                    }
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 540, idealHeight: 720)
        .focusedValue(\.studioSaveAction, pane == .provider ? { save() } : nil)
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

    private var providerScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                settingsHeader
                statusBanner
                Divider().padding(.vertical, 20)
                authenticationSection
                Divider().padding(.vertical, 20)
                providerSection
                Divider().padding(.vertical, 20)
                modelsSection
            }
            .padding(26)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .padding(.top, 16)
        } else if let saveMessage {
            Label(saveMessage, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.top, 16)
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
            number: "02",
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

            VStack(alignment: .leading, spacing: 6) {
                Text("API base URL")
                    .font(.subheadline.weight(.semibold))
                TextField("API base URL", text: $configuration.baseURL, prompt: Text("https://api.example.com"))
                    .textFieldStyle(.roundedBorder)
            }

            Label(configuration.apiProtocol.detail, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelsSection: some View {
        SettingsSection(
            number: "03",
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
            number: "01",
            title: "Authentication",
            detail: "Secrets never appear in the interface after saving. Managed keys live in the Keychain, not in the project."
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
                Label("Stored in the macOS Keychain for this project. Pipeline runs receive it through the process environment.", systemImage: "lock.fill")
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

    private var aboutView: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.accentColor)
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
                .foregroundStyle(.secondary)
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
