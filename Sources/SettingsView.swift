import SwiftUI
import AVFoundation
import ServiceManagement

// MARK: - Shared Helpers

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private let iso8601DayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

struct ProviderSettingsFields: View {
    @EnvironmentObject var appState: AppState
    @Binding var apiBaseURLInput: String
    @FocusState private var isEditingAPIBaseURL: Bool
    @FocusState private var isEditingTranscriptionModel: Bool
    @FocusState private var isEditingPostProcessingModel: Bool
    @FocusState private var isEditingPostProcessingFallbackModel: Bool
    @FocusState private var isEditingContextModel: Bool
    @State private var transcriptionModelDraft: String = ""
    @State private var postProcessingModelDraft: String = ""
    @State private var postProcessingFallbackModelDraft: String = ""
    @State private var contextModelDraft: String = ""

    let showsModelDescription: Bool

    private func commitAPIBaseURL() {
        let trimmed = apiBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseURL = trimmed.isEmpty ? AppState.defaultAPIBaseURL : trimmed
        apiBaseURLInput = resolvedBaseURL
        appState.apiBaseURL = resolvedBaseURL
    }

    private func commitTranscriptionModel() {
        let trimmed = transcriptionModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriptionModelDraft = trimmed
        guard appState.transcriptionModel != trimmed else { return }
        appState.transcriptionModel = trimmed
    }

    private func commitPostProcessingModel() {
        let trimmed = postProcessingModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        postProcessingModelDraft = trimmed
        guard appState.postProcessingModel != trimmed else { return }
        appState.postProcessingModel = trimmed
    }

    private func commitPostProcessingFallbackModel() {
        let trimmed = postProcessingFallbackModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        postProcessingFallbackModelDraft = trimmed
        guard appState.postProcessingFallbackModel != trimmed else { return }
        appState.postProcessingFallbackModel = trimmed
    }

    private func commitContextModel() {
        let trimmed = contextModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        contextModelDraft = trimmed
        guard appState.contextModel != trimmed else { return }
        appState.contextModel = trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Base URL")
                .font(.caption.weight(.semibold))

            Text("Change this to use a different OpenAI-compatible API provider.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(AppState.defaultAPIBaseURL, text: $apiBaseURLInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($isEditingAPIBaseURL)
                    .onSubmit {
                        commitAPIBaseURL()
                    }
                    .onChange(of: isEditingAPIBaseURL) { isEditing in
                        if !isEditing {
                            commitAPIBaseURL()
                        }
                    }

                Button("Reset to Default") {
                    apiBaseURLInput = AppState.defaultAPIBaseURL
                    appState.apiBaseURL = AppState.defaultAPIBaseURL
                }
                .font(.caption)
            }

            if showsModelDescription {
                Text("If you use another provider, enter that provider's model IDs here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription Model")
                    .font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    TextField(AppState.defaultTranscriptionModel, text: $transcriptionModelDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingTranscriptionModel)
                        .onSubmit {
                            commitTranscriptionModel()
                        }
                        .onChange(of: isEditingTranscriptionModel) { isEditing in
                            if !isEditing {
                                commitTranscriptionModel()
                            }
                        }
                    Button("Reset to Default") {
                        transcriptionModelDraft = AppState.defaultTranscriptionModel
                        appState.transcriptionModel = AppState.defaultTranscriptionModel
                    }
                    .font(.caption)
                }
                Text("Used for speech-to-text transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Post-Processing Model")
                    .font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    TextField(AppState.defaultPostProcessingModel, text: $postProcessingModelDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingPostProcessingModel)
                        .onSubmit {
                            commitPostProcessingModel()
                        }
                        .onChange(of: isEditingPostProcessingModel) { isEditing in
                            if !isEditing {
                                commitPostProcessingModel()
                            }
                        }
                    Button("Reset to Default") {
                        postProcessingModelDraft = AppState.defaultPostProcessingModel
                        appState.postProcessingModel = AppState.defaultPostProcessingModel
                    }
                    .font(.caption)
                }
                Text("Used for transcript cleanup and Edit Mode transforms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Post-Processing Fallback Model")
                    .font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    TextField(AppState.defaultPostProcessingFallbackModel, text: $postProcessingFallbackModelDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingPostProcessingFallbackModel)
                        .onSubmit {
                            commitPostProcessingFallbackModel()
                        }
                        .onChange(of: isEditingPostProcessingFallbackModel) { isEditing in
                            if !isEditing {
                                commitPostProcessingFallbackModel()
                            }
                        }
                    Button("Reset to Default") {
                        postProcessingFallbackModelDraft = AppState.defaultPostProcessingFallbackModel
                        appState.postProcessingFallbackModel = AppState.defaultPostProcessingFallbackModel
                    }
                    .font(.caption)
                }
                Text("Used as the explicit retry model for transcript cleanup and Edit Mode transforms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Context Model")
                    .font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    TextField(AppState.defaultContextModel, text: $contextModelDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingContextModel)
                        .onSubmit {
                            commitContextModel()
                        }
                        .onChange(of: isEditingContextModel) { isEditing in
                            if !isEditing {
                                commitContextModel()
                            }
                        }
                    Button("Reset to Default") {
                        contextModelDraft = AppState.defaultContextModel
                        appState.contextModel = AppState.defaultContextModel
                    }
                    .font(.caption)
                }
                Text("Used for context inference, with a text-only retry when screenshot analysis fails.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            transcriptionModelDraft = appState.transcriptionModel
            postProcessingModelDraft = appState.postProcessingModel
            postProcessingFallbackModelDraft = appState.postProcessingFallbackModel
            contextModelDraft = appState.contextModel
        }
        .onChange(of: appState.transcriptionModel) { value in
            if !isEditingTranscriptionModel {
                transcriptionModelDraft = value
            }
        }
        .onChange(of: appState.postProcessingModel) { value in
            if !isEditingPostProcessingModel {
                postProcessingModelDraft = value
            }
        }
        .onChange(of: appState.postProcessingFallbackModel) { value in
            if !isEditingPostProcessingFallbackModel {
                postProcessingFallbackModelDraft = value
            }
        }
        .onChange(of: appState.contextModel) { value in
            if !isEditingContextModel {
                contextModelDraft = value
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        appState.selectedSettingsTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(appState.selectedSettingsTab == tab
                                          ? Color.accentColor.opacity(0.15)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 180)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch appState.selectedSettingsTab {
                case .general, .none:
                    GeneralSettingsView()
                case .prompts:
                    PromptsSettingsView()
                case .macros:
                    VoiceMacrosSettingsView()
                case .runLog:
                    RunLogView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    @AppStorage("show_menu_bar_icon") private var showMenuBarIcon = true
    @State private var apiKeyInput: String = ""
    @State private var apiBaseURLInput: String = ""
    @State private var advancedProviderSettingsExpanded = false
    @State private var isValidatingKey = false
    @State private var keyValidationError: String?
    @State private var keyValidationSuccess = false
    @State private var customVocabularyInput: String = ""
    @State private var micPermissionGranted = false
    @State private var showMutedHint = false
    @State private var copiedBuildInfo = false
    @State private var copiedBuildInfoResetWorkItem: DispatchWorkItem?
    @StateObject private var githubCache = GitHubMetadataCache.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    private let freeflowRepoURL = URL(string: "https://github.com/zachlatta/freeflow")!

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "FreeFlow"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var appBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "FreeFlowBuildTag") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
    }

    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var appArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private var buildDiagnosticsText: String {
        "\(appDisplayName) \(appVersion) (\(appBuildNumber))\nmacOS \(macOSVersion) (\(appArchitecture))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App branding header
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)

                    Text("FreeFlow")
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Text("v\(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // GitHub card
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            AsyncImage(url: URL(string: "https://avatars.githubusercontent.com/u/992248")) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())

                            Button {
                                openURL(freeflowRepoURL)
                            } label: {
                                Text("zachlatta/freeflow")
                                    .font(.system(.caption, design: .monospaced).weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption2)
                                if githubCache.isLoading {
                                    ProgressView().scaleEffect(0.5)
                                } else if let count = githubCache.starCount {
                                    Text("\(count.formatted()) \(count == 1 ? "star" : "stars")")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.yellow.opacity(0.14)))

                            Button {
                                openURL(freeflowRepoURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "star")
                                    Text("Star")
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.yellow.opacity(0.18)))
                            }
                            .buttonStyle(.plain)
                        }

                        if !githubCache.recentStargazers.isEmpty {
                            Divider()
                            HStack(spacing: 8) {
                                HStack(spacing: -6) {
                                    ForEach(githubCache.recentStargazers) { star in
                                        Button {
                                            openURL(star.user.htmlUrl)
                                        } label: {
                                            AsyncImage(url: star.user.avatarThumbnailUrl) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                default:
                                                    Color.gray.opacity(0.2)
                                                }
                                            }
                                            .frame(width: 22, height: 22)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .clipped()
                                Text("recently starred")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize()
                                Spacer()
                            }
                            .clipped()
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 4)

                SettingsCard("App", icon: "power") {
                    startupSection
                }
                SettingsCard("Updates", icon: "arrow.triangle.2.circlepath") {
                    updatesSection
                }
                SettingsCard("API Key", icon: "key.fill") {
                    apiKeySection
                }
                SettingsCard("Dictation Shortcuts", icon: "keyboard.fill") {
                    hotkeySection
                }
                SettingsCard("Edit Mode", icon: "pencil") {
                    commandModeSection
                }
                SettingsCard("Clipboard", icon: "doc.on.clipboard") {
                    clipboardSection
                }
                SettingsCard("Microphone", icon: "mic.fill") {
                    microphoneSection
                }
                SettingsCard("Sound Volume", icon: "speaker.wave.2.fill") {
                    soundVolumeSection
                }
                SettingsCard("Custom Vocabulary", icon: "text.book.closed.fill") {
                    vocabularySection
                }
                SettingsCard("Permissions", icon: "lock.shield.fill") {
                    permissionsSection
                }
                SettingsCard("Build", icon: "info.circle.fill") {
                    buildInfoSection
                }
            }
            .padding(24)
        }
        .onAppear {
            apiKeyInput = appState.apiKey
            apiBaseURLInput = appState.apiBaseURL
            customVocabularyInput = appState.customVocabulary
            checkMicPermission()
            appState.refreshLaunchAtLoginStatus()
            Task { await githubCache.fetchIfNeeded() }
        }
    }

    // MARK: Startup

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch FreeFlow at login", isOn: $appState.launchAtLogin)
            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)

            if SMAppService.mainApp.status == .requiresApproval {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Login item requires approval in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updateManager.autoCheckEnabled },
                set: { updateManager.autoCheckEnabled = $0 }
            ))

            HStack(spacing: 10) {
                Button {
                    Task {
                        await updateManager.checkForUpdates(userInitiated: true)
                    }
                } label: {
                    if updateManager.isChecking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking...")
                        }
                    } else {
                        Text("Check for Updates Now")
                    }
                }
                .disabled(updateManager.isChecking || updateManager.updateStatus != .idle)

                if let lastCheck = updateManager.lastCheckDate {
                    Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if updateManager.updateAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    switch updateManager.updateStatus {
                    case .downloading:
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Downloading update...")
                                    .font(.caption.weight(.semibold))
                                ProgressView(value: updateManager.downloadProgress ?? 0)
                                    .progressViewStyle(.linear)
                                if let progress = updateManager.downloadProgress {
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Cancel") {
                                updateManager.cancelDownload()
                            }
                            .font(.caption)
                        }

                    case .installing:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing update...")
                                .font(.caption.weight(.semibold))
                        }

                    case .readyToRelaunch:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Relaunching...")
                                .font(.caption.weight(.semibold))
                        }

                    case .error(let message):
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Retry") {
                                updateManager.updateStatus = .idle
                                if let release = updateManager.latestRelease {
                                    updateManager.downloadAndInstall(release: release)
                                }
                            }
                            .font(.caption)
                        }

                    case .idle:
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            Text("A new version of FreeFlow is available!")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Update Now") {
                                if let release = updateManager.latestRelease {
                                    updateManager.downloadAndInstall(release: release)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }

    // MARK: Build

    private var buildInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Build number")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(appBuildNumber)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 12) {
                Text(buildDiagnosticsText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer()

                Button {
                    copyBuildDiagnostics()
                } label: {
                    Label(copiedBuildInfo ? "Copied" : "Copy", systemImage: copiedBuildInfo ? "checkmark" : "doc.on.doc")
                }
                .font(.caption)
            }
        }
    }

    private func copyBuildDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(buildDiagnosticsText, forType: .string)
        copiedBuildInfo = true

        copiedBuildInfoResetWorkItem?.cancel()

        let resetWorkItem = DispatchWorkItem {
            copiedBuildInfo = false
            copiedBuildInfoResetWorkItem = nil
        }
        copiedBuildInfoResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }

    // MARK: API Key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FreeFlow uses the configured transcription model with your selected OpenAI-compatible provider.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                SecureField("Enter your Groq API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isValidatingKey)
                    .onChange(of: apiKeyInput) { _ in
                        keyValidationError = nil
                        keyValidationSuccess = false
                    }

                Button(isValidatingKey ? "Validating..." : "Save") {
                    validateAndSaveKey()
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingKey)
            }

            if let error = keyValidationError {
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if keyValidationSuccess {
                Label("API key saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            DisclosureGroup(isExpanded: $advancedProviderSettingsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    ProviderSettingsFields(
                        apiBaseURLInput: $apiBaseURLInput,
                        showsModelDescription: false
                    )
                }
            } label: {
                HStack {
                    Text("Advanced Provider Settings")
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    advancedProviderSettingsExpanded.toggle()
                }
            }
            .padding(.top, 4)
        }
    }

    private func validateAndSaveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = apiBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidatingKey = true
        keyValidationError = nil
        keyValidationSuccess = false

        Task {
            let valid = await TranscriptionService.validateAPIKey(
                key,
                baseURL: baseURL.isEmpty ? AppState.defaultAPIBaseURL : baseURL
            )
            await MainActor.run {
                isValidatingKey = false
                if valid {
                    appState.apiKey = key
                    keyValidationSuccess = true
                } else {
                    keyValidationError = "Validation failed. Please check your API key and provider settings, then try again."
                }
            }
        }
    }

    // MARK: Dictation Shortcuts

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DictationShortcutEditor { isCapturing in
                if isCapturing {
                    appState.suspendHotkeyMonitoringForShortcutCapture()
                } else {
                    appState.resumeHotkeyMonitoringAfterShortcutCapture()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shortcut Start Delay")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(appState.shortcutStartDelayMilliseconds) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $appState.shortcutStartDelay,
                    in: 0...0.5,
                    step: 0.025
                )

                Text("Applies before recording starts for both hold and tap shortcuts. Stopping still happens immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var commandModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Edit Mode", isOn: Binding(
                get: { appState.isCommandModeEnabled },
                set: { newValue in
                    _ = appState.setCommandModeEnabled(newValue)
                }
            ))

            Text("Transform highlighted text with a spoken instruction instead of dictating over it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Invocation Style", selection: Binding(
                get: { appState.commandModeStyle },
                set: { newValue in
                    _ = appState.setCommandModeStyle(newValue)
                }
            )) {
                ForEach(CommandModeStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!appState.isCommandModeEnabled)

            Group {
                switch appState.commandModeStyle {
                case .automatic:
                    Text("If text is selected, your normal dictation shortcut transforms the selection instead of dictating over it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .manual:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hold the extra modifier together with your normal dictation shortcut to transform selected text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Extra Modifier", selection: Binding(
                            get: { appState.commandModeManualModifier },
                            set: { newValue in
                                _ = appState.setCommandModeManualModifier(newValue)
                            }
                        )) {
                            ForEach(CommandModeManualModifier.allCases) { modifier in
                                Text(modifier.title).tag(modifier)
                            }
                        }
                        .disabled(!appState.isCommandModeEnabled || appState.commandModeStyle != .manual)
                    }
                }
            }
            .opacity(appState.isCommandModeEnabled ? 1 : 0.5)

            if let validationMessage = appState.commandModeManualModifierValidationMessage {
                Label(validationMessage, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: Clipboard

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Preserve clipboard after paste", isOn: $appState.preserveClipboard)

            Text("FreeFlow will temporarily place the transcript on your clipboard to paste it, then restore whatever was there before. If you copy something else before the restore happens, FreeFlow leaves it alone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 2)

            Toggle("Say \"press enter\" to submit after paste", isOn: $appState.isPressEnterVoiceCommandEnabled)

            Text("When the transcription ends with \"press enter\", FreeFlow removes those words before cleanup, pastes the remaining transcript, then presses Return.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Microphone

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select which microphone to use for recording.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                MicrophoneOptionRow(
                    name: "System Default",
                    isSelected: appState.selectedMicrophoneID == "default" || appState.selectedMicrophoneID.isEmpty,
                    action: { appState.selectedMicrophoneID = "default" }
                )
                ForEach(appState.availableMicrophones) { device in
                    MicrophoneOptionRow(
                        name: device.name,
                        isSelected: appState.selectedMicrophoneID == device.uid,
                        action: { appState.selectedMicrophoneID = device.uid }
                    )
                }
            }
        }
        .onAppear {
            appState.refreshAvailableMicrophones()
        }
    }

    // MARK: Sound Volume

    private var soundVolumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Play alert sounds", isOn: $appState.alertSoundsEnabled)

            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(value: $appState.soundVolume, in: 0...1, step: 0.1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("\(Int(appState.soundVolume * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .disabled(!appState.alertSoundsEnabled)
            .opacity(appState.alertSoundsEnabled ? 1 : 0.5)

            HStack(spacing: 8) {
                Button("Preview") {
                    let muted = SystemAudioStatus.isDefaultOutputMuted()
                    let volume = SystemAudioStatus.defaultOutputVolume()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMutedHint = muted || (volume ?? 1) < 0.10
                    }
                    appState.playAlertSound(named: "Tink")
                }
                .font(.caption)
                .disabled(!appState.alertSoundsEnabled)

                if showMutedHint {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundStyle(.orange)
                        Text("System volume is muted or very low. Unmute to hear the preview.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .transition(.opacity)
                }
            }
        }
        .onChange(of: appState.alertSoundsEnabled) { enabled in
            if !enabled { showMutedHint = false }
        }
    }

    // MARK: Custom Vocabulary

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Words and phrases to preserve during post-processing.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $customVocabularyInput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: customVocabularyInput) { newValue in
                    appState.customVocabulary = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                }

            Text("Separate entries with commas, new lines, or semicolons.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionRow(
                title: "Microphone",
                icon: "mic.fill",
                granted: micPermissionGranted,
                action: {
                    appState.requestMicrophoneAccess { granted in
                        micPermissionGranted = granted
                    }
                }
            )

            permissionRow(
                title: "Accessibility",
                icon: "hand.raised.fill",
                granted: appState.hasAccessibility,
                action: {
                    appState.openAccessibilitySettings()
                }
            )

            permissionRow(
                title: "Screen Recording",
                icon: "camera.viewfinder",
                granted: appState.hasScreenRecordingPermission,
                action: {
                    appState.requestScreenCapturePermission()
                }
            )
        }
    }

    private func permissionRow(title: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.blue)
            Text(title)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Grant Access") {
                    action()
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func checkMicPermission() {
        micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

}

// MARK: - Microphone Option Row

struct MicrophoneOptionRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prompts Settings

struct PromptsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var customSystemPromptInput: String = ""
    @State private var customContextPromptInput: String = ""
    @State private var showDefaultSystemPrompt = false
    @State private var showDefaultContextPrompt = false

    // System prompt test state
    @State private var systemTestInput: String = "Um, so I was like, thinking we should uh, refactor the authentication module, you know?"
    @State private var systemTestRunning = false
    @State private var systemTestOutput: String? = nil
    @State private var systemTestError: String? = nil
    @State private var systemTestPrompt: String? = nil

    // Context prompt test state
    @State private var contextTestRunning = false
    @State private var contextTestOutput: String? = nil
    @State private var contextTestError: String? = nil
    @State private var contextTestPrompt: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard("System Prompt", icon: "text.bubble.fill") {
                    systemPromptSection
                }
                SettingsCard("Context Prompt", icon: "eye.fill") {
                    contextPromptSection
                }
            }
            .padding(24)
        }
        .onAppear {
            customSystemPromptInput = appState.customSystemPrompt.isEmpty
                ? PostProcessingService.defaultSystemPrompt
                : appState.customSystemPrompt
            customContextPromptInput = appState.customContextPrompt.isEmpty
                ? AppContextService.defaultContextPrompt
                : appState.customContextPrompt
        }
    }

    // MARK: System Prompt

    private var systemPromptSection: some View {
        let isCustom = !appState.customSystemPrompt.isEmpty
        let hasNewerDefault = isCustom
            && !appState.customSystemPromptLastModified.isEmpty
            && appState.customSystemPromptLastModified < PostProcessingService.defaultSystemPromptDate

        return VStack(alignment: .leading, spacing: 10) {
            Text("Controls how raw transcriptions are cleaned up.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if hasNewerDefault {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                    Text("A newer default prompt is available.")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("View Default") {
                        showDefaultSystemPrompt.toggle()
                    }
                    .font(.caption)
                    Button("Switch to Default") {
                        customSystemPromptInput = PostProcessingService.defaultSystemPrompt
                        appState.customSystemPrompt = ""
                        appState.customSystemPromptLastModified = ""
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            if showDefaultSystemPrompt {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Default System Prompt")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("Hide") {
                            showDefaultSystemPrompt = false
                        }
                        .font(.caption)
                    }
                    Text(PostProcessingService.defaultSystemPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }

            TextEditor(text: $customSystemPromptInput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: customSystemPromptInput) { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let defaultTrimmed = PostProcessingService.defaultSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed == defaultTrimmed || trimmed.isEmpty {
                        if !appState.customSystemPrompt.isEmpty {
                            appState.customSystemPrompt = ""
                            appState.customSystemPromptLastModified = ""
                        }
                    } else {
                        appState.customSystemPrompt = trimmed
                        let today = iso8601DayFormatter.string(from: Date())
                        if appState.customSystemPromptLastModified != today {
                            appState.customSystemPromptLastModified = today
                        }
                    }
                }

            HStack {
                if isCustom {
                    Label("Using custom prompt", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Label("Using default", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCustom {
                    Button("Reset to Default") {
                        customSystemPromptInput = PostProcessingService.defaultSystemPrompt
                        appState.customSystemPrompt = ""
                        appState.customSystemPromptLastModified = ""
                    }
                    .font(.caption)
                }
            }

            Divider()

            // Test section
            VStack(alignment: .leading, spacing: 8) {
                Text("Test System Prompt")
                    .font(.caption.weight(.semibold))
                Text("Enter sample text to see how the current prompt cleans it up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $systemTestInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                Button {
                    runSystemPromptTest()
                } label: {
                    HStack(spacing: 6) {
                        if systemTestRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Running...")
                        } else {
                            Image(systemName: "play.fill")
                            Text("Test System Prompt")
                        }
                    }
                }
                .disabled(systemTestRunning || appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || systemTestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("API key required to test", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = systemTestError {
                    Label(error, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let output = systemTestOutput {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Result:")
                            .font(.caption.weight(.semibold))
                        Text(output.isEmpty ? "(empty — no output)" : output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.08))
                            .cornerRadius(6)
                    }
                }

                if let prompt = systemTestPrompt {
                    DisclosureGroup("Full prompt sent") {
                        Text(prompt)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func runSystemPromptTest() {
        systemTestRunning = true
        systemTestOutput = nil
        systemTestError = nil
        systemTestPrompt = nil

        let service = PostProcessingService(
            apiKey: appState.apiKey,
            baseURL: appState.apiBaseURL,
            preferredModel: appState.postProcessingModel,
            preferredFallbackModel: appState.postProcessingFallbackModel
        )
        let input = systemTestInput
        let customPrompt = appState.customSystemPrompt
        let vocabulary = appState.customVocabulary

        let context = AppContext(
            appName: "FreeFlow Settings",
            bundleIdentifier: "com.zachlatta.freeflow",
            windowTitle: "System Prompt Test",
            selectedText: nil,
            currentActivity: "User is testing the system prompt in FreeFlow settings.",
            contextSystemPrompt: nil,
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: nil
        )

        Task {
            do {
                let result = try await service.postProcess(
                    transcript: input,
                    context: context,
                    customVocabulary: vocabulary,
                    customSystemPrompt: customPrompt
                )
                await MainActor.run {
                    systemTestOutput = result.transcript
                    systemTestPrompt = result.prompt
                    systemTestRunning = false
                }
            } catch {
                await MainActor.run {
                    systemTestError = error.localizedDescription
                    systemTestRunning = false
                }
            }
        }
    }

    // MARK: Context Prompt

    private var contextPromptSection: some View {
        let isCustom = !appState.customContextPrompt.isEmpty
        let hasNewerDefault = isCustom
            && !appState.customContextPromptLastModified.isEmpty
            && appState.customContextPromptLastModified < AppContextService.defaultContextPromptDate

        return VStack(alignment: .leading, spacing: 10) {
            Text("Controls how FreeFlow infers your current activity from app metadata and screenshots.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if hasNewerDefault {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                    Text("A newer default prompt is available.")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("View Default") {
                        showDefaultContextPrompt.toggle()
                    }
                    .font(.caption)
                    Button("Switch to Default") {
                        customContextPromptInput = AppContextService.defaultContextPrompt
                        appState.customContextPrompt = ""
                        appState.customContextPromptLastModified = ""
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            if showDefaultContextPrompt {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Default Context Prompt")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("Hide") {
                            showDefaultContextPrompt = false
                        }
                        .font(.caption)
                    }
                    Text(AppContextService.defaultContextPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }

            TextEditor(text: $customContextPromptInput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: customContextPromptInput) { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let defaultTrimmed = AppContextService.defaultContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed == defaultTrimmed || trimmed.isEmpty {
                        if !appState.customContextPrompt.isEmpty {
                            appState.customContextPrompt = ""
                            appState.customContextPromptLastModified = ""
                        }
                    } else {
                        appState.customContextPrompt = trimmed
                        let today = iso8601DayFormatter.string(from: Date())
                        if appState.customContextPromptLastModified != today {
                            appState.customContextPromptLastModified = today
                        }
                    }
                }

            HStack {
                if isCustom {
                    Label("Using custom prompt", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Label("Using default", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCustom {
                    Button("Reset to Default") {
                        customContextPromptInput = AppContextService.defaultContextPrompt
                        appState.customContextPrompt = ""
                        appState.customContextPromptLastModified = ""
                    }
                    .font(.caption)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Screenshot Resolution")
                    .font(.caption.weight(.semibold))

                Text("Controls the maximum image dimension sent for context inference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $appState.contextScreenshotMaxDimension) {
                    ForEach(AppState.contextScreenshotDimensionOptions, id: \.self) { dimension in
                        Text("\(dimension) px").tag(dimension)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Screenshot Resolution")

                HStack {
                    if appState.contextScreenshotMaxDimension == AppState.defaultContextScreenshotMaxDimension {
                        Label("Using default", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Using custom value", systemImage: "pencil")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    if appState.contextScreenshotMaxDimension != AppState.defaultContextScreenshotMaxDimension {
                        Button("Reset to Default") {
                            appState.contextScreenshotMaxDimension = AppState.defaultContextScreenshotMaxDimension
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()

            // Test section
            VStack(alignment: .leading, spacing: 8) {
                Text("Test Context Prompt")
                    .font(.caption.weight(.semibold))
                Text("Captures a screenshot and metadata from the frontmost app, then runs the context prompt to infer activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    runContextPromptTest()
                } label: {
                    HStack(spacing: 6) {
                        if contextTestRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Running...")
                        } else {
                            Image(systemName: "play.fill")
                            Text("Test Context Prompt")
                        }
                    }
                }
                .disabled(contextTestRunning || appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("API key required to test", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = contextTestError {
                    Label(error, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let output = contextTestOutput {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Result:")
                            .font(.caption.weight(.semibold))
                        Text(output.isEmpty ? "(empty — no output)" : output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.08))
                            .cornerRadius(6)
                    }
                }

                if let prompt = contextTestPrompt {
                    DisclosureGroup("Full prompt sent") {
                        Text(prompt)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func runContextPromptTest() {
        contextTestRunning = true
        contextTestOutput = nil
        contextTestError = nil
        contextTestPrompt = nil

        let service = appState.makeAppContextService()

        Task {
            let context = await service.collectContext()
            await MainActor.run {
                if let prompt = context.contextPrompt {
                    contextTestOutput = context.contextSummary
                    contextTestPrompt = prompt
                } else {
                    contextTestError = "Context inference returned no result. This may be a permissions issue or the API could not be reached."
                    contextTestOutput = context.contextSummary
                }
                contextTestRunning = false
            }
        }
    }

}

// MARK: - Run Log

struct RunLogView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run Log")
                        .font(.headline)
                    Text("Stored locally. Only the \(appState.maxPipelineHistoryCount) most recent runs are kept.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Clear History") {
                    appState.clearPipelineHistory()
                }
                .disabled(appState.pipelineHistory.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if appState.pipelineHistory.isEmpty {
                VStack {
                    Spacer()
                    Text("No runs yet. Use dictation to populate history.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appState.pipelineHistory) { item in
                            RunLogEntryView(item: item)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

// MARK: - Run Log Entry

struct RunLogEntryView: View {
    private let actionIconSize: CGFloat = 28
    let item: PipelineHistoryItem
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false
    @State private var isRetrying = false
    @State private var showContextPrompt = false
    @State private var showPostProcessingPrompt = false

    private var isError: Bool {
        item.postProcessingStatus.hasPrefix("Error:")
    }

    @ViewBuilder
    private func actionIconButton(
        systemName: String,
        color: Color = .secondary,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: actionIconSize, height: actionIconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: actionIconSize, height: actionIconSize)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        if isError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.timestamp.formatted(date: .numeric, time: .standard))
                                .font(.subheadline.weight(.semibold))
                            Text(item.postProcessedTranscript.isEmpty ? "(no transcript)" : item.postProcessedTranscript)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    if isError && item.audioFileName != nil {
                        Button {
                            appState.retryTranscription(item: item)
                        } label: {
                            if isRetrying {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: actionIconSize, height: actionIconSize)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .frame(width: actionIconSize, height: actionIconSize)
                                    .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isRetrying)
                        .help("Retry transcription")
                    } else {
                        Color.clear
                            .frame(width: actionIconSize, height: actionIconSize)
                    }

                    actionIconButton(systemName: "square.and.arrow.up", help: "Export run log") {
                        TestCaseExporter.exportWithSavePanel(
                            item: item,
                            audioDirURL: AppState.audioStorageDirectory()
                        )
                    }

                    actionIconButton(systemName: "trash", help: "Delete this run") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.deleteHistoryEntry(id: item.id)
                        }
                    }
                }
            }
            .padding(12)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 16) {
                    // Audio player
                    if let audioFileName = item.audioFileName {
                        let audioURL = AppState.audioStorageDirectory().appendingPathComponent(audioFileName)
                        AudioPlayerView(audioURL: audioURL)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("No audio recorded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Custom vocabulary
                    if !item.customVocabulary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom Vocabulary")
                                .font(.caption.weight(.semibold))
                            FlowLayout(spacing: 4) {
                                ForEach(parseVocabulary(item.customVocabulary), id: \.self) { word in
                                    Text(word)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    // Pipeline steps
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pipeline")
                            .font(.caption.weight(.semibold))

                        // Step 1: Context Capture
                        PipelineStepView(
                            number: 1,
                            title: "Capture Context",
                            content: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let dataURL = item.contextScreenshotDataURL,
                                       let image = imageFromDataURL(dataURL) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxHeight: 120)
                                            .cornerRadius(4)
                                    }

                                    if let prompt = item.contextPrompt, !prompt.isEmpty {
                                        Button {
                                            showContextPrompt.toggle()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(showContextPrompt ? "Hide Prompt" : "Show Prompt")
                                                    .font(.caption)
                                                Image(systemName: showContextPrompt ? "chevron.up" : "chevron.down")
                                                    .font(.caption2)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Color.accentColor)

                                        if showContextPrompt {
                                            Text(prompt)
                                                .font(.system(.caption2, design: .monospaced))
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(4)
                                        }
                                    }

                                    if !item.contextSummary.isEmpty {
                                        Text(item.contextSummary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    } else {
                                        Text("No context captured")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        )

                        // Step 2: Transcribe Audio
                        PipelineStepView(
                            number: 2,
                            title: "Transcribe Audio",
                            content: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sent audio to the configured transcription model")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    if !item.rawTranscript.isEmpty {
                                        Text(item.rawTranscript)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .cornerRadius(4)
                                    } else {
                                        Text("(empty transcript)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        )

                        // Step 3: Post-Process
                        PipelineStepView(
                            number: 3,
                            title: "Post-Process",
                            content: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.postProcessingStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                    if let prompt = item.postProcessingPrompt, !prompt.isEmpty {
                                        Button {
                                            showPostProcessingPrompt.toggle()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(showPostProcessingPrompt ? "Hide Prompt" : "Show Prompt")
                                                    .font(.caption)
                                                Image(systemName: showPostProcessingPrompt ? "chevron.up" : "chevron.down")
                                                    .font(.caption2)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Color.accentColor)

                                        if showPostProcessingPrompt {
                                            Text(prompt)
                                                .font(.system(.caption2, design: .monospaced))
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(4)
                                        }
                                    }

                                    if !item.postProcessedTranscript.isEmpty {
                                        Text(item.postProcessedTranscript)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        )
                    }

                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isError ? Color.red.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onReceive(appState.$retryingItemIDs) { ids in
            isRetrying = ids.contains(item.id)
        }
    }

    private func parseVocabulary(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Pipeline Step View

struct PipelineStepView<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Audio Player

class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.onFinish?()
        }
    }
}

struct AudioPlayerView: View {
    let audioURL: URL
    @State private var player: AVAudioPlayer?
    @State private var delegate = AudioPlayerDelegate()
    @State private var isPlaying = false
    @State private var duration: TimeInterval = 0
    @State private var elapsed: TimeInterval = 0
    @State private var progressTimer: Timer?

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(elapsed / duration, 1.0)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, geo.size.width * progress), height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 28)

            Text("\(formatDuration(elapsed)) / \(formatDuration(duration))")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .onAppear {
            loadDuration()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func loadDuration() {
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
        if let p = try? AVAudioPlayer(contentsOf: audioURL) {
            duration = p.duration
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
            do {
                let p = try AVAudioPlayer(contentsOf: audioURL)
                delegate.onFinish = {
                    self.stopPlayback()
                }
                p.delegate = delegate
                p.play()
                player = p
                isPlaying = true
                elapsed = 0
                startProgressTimer()
            } catch {}
        }
    }

    private func stopPlayback() {
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        elapsed = 0
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let p = player, p.isPlaying {
                elapsed = p.currentTime
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let pos = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Voice Macros Settings

struct VoiceMacrosSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddMacro = false
    @State private var editingMacro: VoiceMacro?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard("Voice Macros", icon: "music.mic") {
                    macrosSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingAddMacro, onDismiss: { editingMacro = nil }) {
            VoiceMacroEditorView(isPresented: $showingAddMacro, macro: $editingMacro)
        }
    }

    private var macrosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bypass post-processing and immediately paste your predefined text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { showingAddMacro = true }) {
                    Text("Add Macro")
                }
            }

            if appState.voiceMacros.isEmpty {
                VStack {
                    Image(systemName: "music.mic")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                    Text("No Voice Macros Yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Click 'Add Macro' to define your first voice macro.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(appState.voiceMacros.enumerated()), id: \.element.id) { index, macro in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(macro.command)
                                    .font(.headline)
                                Spacer()
                                Button("Edit") {
                                    editingMacro = macro
                                    showingAddMacro = true
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                
                                Button("Delete") {
                                    appState.voiceMacros.removeAll { $0.id == macro.id }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                            Text(macro.payload)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    }
                }
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }
}

struct VoiceMacroEditorView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @Binding var macro: VoiceMacro?

    @State private var command: String = ""
    @State private var payload: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(macro == nil ? "Add Macro" : "Edit Macro")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Voice Command (What you say)")
                    .font(.caption.weight(.semibold))
                TextField("e.g. debugging prompt", text: $command)
                    .textFieldStyle(.roundedBorder)

                Text("Text (What gets pasted)")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 8)
                TextEditor(text: $payload)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                    macro = nil
                }
                Spacer()
                Button("Save") {
                    let newMacro = VoiceMacro(
                        id: macro?.id ?? UUID(),
                        command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                        payload: payload
                    )
                    
                    if let existingIndex = appState.voiceMacros.firstIndex(where: { $0.id == newMacro.id }) {
                        appState.voiceMacros[existingIndex] = newMacro
                    } else {
                        appState.voiceMacros.append(newMacro)
                    }
                    isPresented = false
                    macro = nil
                }
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || payload.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let m = macro {
                command = m.command
                payload = m.payload
            }
        }
    }
}
