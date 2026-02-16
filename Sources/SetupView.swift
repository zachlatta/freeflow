import SwiftUI
import AVFoundation
import Foundation
import ServiceManagement

struct SetupView: View {
    var onComplete: () -> Void
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    private let freeflowRepoURL = URL(string: "https://github.com/zachlatta/freeflow")!
    private let freeflowRepoAPIURL = URL(string: "https://api.github.com/repos/zachlatta/freeflow")!
    private let freeflowRecentStargazersAPIURL = URL(string: "https://api.github.com/repos/zachlatta/freeflow/stargazers?per_page=3")!
    private enum SetupStep: Int, CaseIterable {
        case welcome = 0
        case apiKey
        case micPermission
        case accessibility
        case screenRecording
        case hotkey
        case vocabulary
        case launchAtLogin
        case ready
    }

    @State private var currentStep = SetupStep.welcome
    @State private var micPermissionGranted = false
    @State private var accessibilityGranted = false
    @State private var apiKeyInput: String = ""
    @State private var isValidatingKey = false
    @State private var keyValidationError: String?
    @State private var accessibilityTimer: Timer?
    @State private var customVocabularyInput: String = ""
    @StateObject private var githubCache = GitHubMetadataCache.shared
    private let totalSteps: [SetupStep] = SetupStep.allCases

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .apiKey:
                    apiKeyStep
                case .micPermission:
                    micPermissionStep
                case .accessibility:
                    accessibilityStep
                case .screenRecording:
                    screenRecordingStep
                case .hotkey:
                    hotkeyStep
                case .vocabulary:
                    vocabularyStep
                case .launchAtLogin:
                    launchAtLoginStep
                case .ready:
                    readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)

            Divider()

            HStack {
                if currentStep != .welcome {
                    Button("Back") {
                        keyValidationError = nil
                        withAnimation {
                            currentStep = previousStep(currentStep)
                        }
                    }
                    .disabled(isValidatingKey)
                }
                Spacer()
                if currentStep != .ready {
                    if currentStep == .apiKey {
                        // API key step: validate before continuing
                        Button(isValidatingKey ? "Validating..." : "Continue") {
                            validateAndContinue()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingKey)
                    } else if currentStep == .vocabulary {
                        Button("Continue") {
                            saveCustomVocabularyAndContinue()
                        }
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Continue") {
                            withAnimation {
                                currentStep = nextStep(currentStep)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 520)
        .onAppear {
            apiKeyInput = appState.apiKey
            customVocabularyInput = appState.customVocabulary
            checkMicPermission()
            checkAccessibility()
            Task {
                await fetchRepositoryMetadata()
            }
        }
        .onDisappear {
            accessibilityTimer?.invalidate()
        }
    }

    // MARK: - Steps

    var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)

            VStack(spacing: 6) {
                Text("Welcome to FreeFlow")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("Dictate text anywhere on your Mac.\nHold a key to record, release to transcribe.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                    .frame(width: 26, height: 26)
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
                                    AsyncImage(url: star.user.avatarUrl) { phase in
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
                        Text("recently starred")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
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

            stepIndicator
        }
    }

    var apiKeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Groq API Key")
                .font(.title)
                .fontWeight(.bold)

            Text("FreeFlow uses Groq for fast, high-accuracy transcription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to get a free API key:")
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        instructionRow(number: "1", text: "Go to [console.groq.com/keys](https://console.groq.com/keys)")
                        instructionRow(number: "2", text: "Create a free account (if you don't have one)")
                        instructionRow(number: "3", text: "Click **Create API Key** and copy it")
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.06))
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.headline)
                    SecureField("Paste your Groq API key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(isValidatingKey)
                        .onChange(of: apiKeyInput) { _ in
                            keyValidationError = nil
                        }

                    if let error = keyValidationError {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            stepIndicator
        }
    }

    var micPermissionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Microphone Access")
                .font(.title)
                .fontWeight(.bold)

            Text("FreeFlow needs access to your microphone to record audio for transcription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "mic.fill")
                    .frame(width: 24)
                    .foregroundStyle(.blue)
                Text("Microphone")
                Spacer()
                if micPermissionGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Granted")
                        .foregroundStyle(.green)
                } else {
                    Button("Grant Access") {
                        requestMicPermission()
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            stepIndicator
        }
    }

    var accessibilityStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Accessibility Access")
                .font(.title)
                .fontWeight(.bold)

            Text("FreeFlow needs Accessibility access to paste transcribed text into your apps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "hand.raised.fill")
                    .frame(width: 24)
                    .foregroundStyle(.blue)
                Text("Accessibility")
                Spacer()
                if accessibilityGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Granted")
                        .foregroundStyle(.green)
                } else {
                    Button("Open Settings") {
                        requestAccessibility()
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            if !accessibilityGranted {
                Text("Note: If you rebuilt the app, you may need to\nremove and re-add it in Accessibility settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            stepIndicator
        }
        .onAppear {
            startAccessibilityPolling()
        }
        .onDisappear {
            accessibilityTimer?.invalidate()
        }
    }

    var screenRecordingStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Screen Recording")
                .font(.title)
                .fontWeight(.bold)

            Text("FreeFlow captures a screenshot for context-aware transcription, improving accuracy based on what's on screen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "camera.viewfinder")
                    .frame(width: 24)
                    .foregroundStyle(.blue)
                Text("Screen Recording")
                Spacer()
                if appState.hasScreenRecordingPermission {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Granted")
                        .foregroundStyle(.green)
                } else {
                    Button("Grant Access") {
                        appState.requestScreenCapturePermission()
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            stepIndicator
        }
    }

    var hotkeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Push-to-Talk Key")
                .font(.title)
                .fontWeight(.bold)

            Text("Choose which key to hold while speaking.\nPress and hold to record, release to transcribe.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(HotkeyOption.allCases) { option in
                    HotkeyOptionRow(
                        option: option,
                        isSelected: appState.selectedHotkey == option,
                        action: {
                            appState.selectedHotkey = option
                        }
                    )
                }
            }
            .padding(.top, 10)

            if appState.selectedHotkey == .fnKey {
                Text("Tip: If Fn opens Emoji picker, go to\nSystem Settings > Keyboard and change\n\"Press fn key to\" to \"Do Nothing\".")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            stepIndicator
        }
    }

    var vocabularyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Custom Vocabulary")
                .font(.title)
                .fontWeight(.bold)

            Text("Add words and phrases that should be preserved in post-processing.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Vocabulary")
                    .font(.headline)

                TextEditor(text: $customVocabularyInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 130)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                Text("Separate entries with commas, new lines, or semicolons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            stepIndicator
        }
    }

    var launchAtLoginStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Launch at Login")
                .font(.title)
                .fontWeight(.bold)

            Text("Start FreeFlow automatically when you log in so it's always ready.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "sunrise.fill")
                    .frame(width: 24)
                    .foregroundStyle(.blue)
                Toggle("Launch FreeFlow at login", isOn: $appState.launchAtLogin)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            stepIndicator
        }
    }

    var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("FreeFlow lives in your menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HowToRow(icon: "keyboard", text: "Hold \(appState.selectedHotkey.displayName) to record")
                HowToRow(icon: "hand.raised", text: "Release to stop and transcribe")
                HowToRow(icon: "doc.on.clipboard", text: "Text is typed at your cursor & copied")
            }
            .padding(.top, 10)

            stepIndicator
        }
    }

    var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(totalSteps, id: \.rawValue) { step in
                Circle()
                    .fill(step == currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Helpers

    private func instructionRow(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number + ".")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.subheadline)
                .tint(.blue)
        }
    }

    // MARK: - Actions

    func validateAndContinue() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidatingKey = true
        keyValidationError = nil

        Task {
            let valid = await TranscriptionService.validateAPIKey(key)
            await MainActor.run {
                isValidatingKey = false
                if valid {
                    appState.apiKey = key
                    withAnimation {
                        currentStep = nextStep(currentStep)
                    }
                } else {
                    keyValidationError = "Invalid API key. Please check and try again."
                }
            }
        }
    }

    func saveCustomVocabularyAndContinue() {
        appState.customVocabulary = customVocabularyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation {
            currentStep = nextStep(currentStep)
        }
    }

    private func previousStep(_ step: SetupStep) -> SetupStep {
        let previous = SetupStep(rawValue: step.rawValue - 1)
        return previous ?? .welcome
    }

    private func nextStep(_ step: SetupStep) -> SetupStep {
        let next = SetupStep(rawValue: step.rawValue + 1)
        return next ?? .ready
    }

    func checkMicPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micPermissionGranted = true
        default:
            break
        }
    }

    func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micPermissionGranted = granted
            }
        }
    }

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                checkAccessibility()
            }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func fetchRepositoryMetadata() async {
        githubCache.isLoading = true
        var starsCount: Int?
        var recent: [GitHubStarRecord] = []

        do {
            let repoResult = try await URLSession.shared.data(from: freeflowRepoAPIURL)
            guard let repoHTTP = repoResult.1 as? HTTPURLResponse,
                  (200..<300).contains(repoHTTP.statusCode) else {
                throw URLError(.badServerResponse)
            }
            starsCount = try JSONDecoder().decode(GitHubRepoInfo.self, from: repoResult.0).stargazersCount

            var request = URLRequest(url: freeflowRecentStargazersAPIURL)
            request.setValue("application/vnd.github.v3.star+json", forHTTPHeaderField: "Accept")
            let starredResult = try await URLSession.shared.data(for: request)
            if let starredHTTP = starredResult.1 as? HTTPURLResponse,
               (200..<300).contains(starredHTTP.statusCode) {
                recent = try JSONDecoder().decode([GitHubStarRecord].self, from: starredResult.0)
            }

            await MainActor.run {
                githubCache.starCount = starsCount
                githubCache.recentStargazers = recent
                githubCache.isLoading = false
            }
        } catch {
            await MainActor.run {
                githubCache.isLoading = false
            }
        }
    }
}

struct GitHubRepoInfo: Decodable {
    let stargazersCount: Int

    private enum CodingKeys: String, CodingKey {
        case stargazersCount = "stargazers_count"
    }
}

struct GitHubStarRecord: Decodable, Identifiable {
    let user: GitHubStarUser

    var id: Int {
        user.id
    }
}

struct GitHubStarUser: Decodable {
    let id: Int
    let login: String
    let avatarUrl: URL
    let htmlUrl: URL

    private enum CodingKeys: String, CodingKey {
        case id
        case login
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
    }
}

@MainActor
class GitHubMetadataCache: ObservableObject {
    static let shared = GitHubMetadataCache()

    @Published var starCount: Int?
    @Published var githubCache.recentStargazers: [GitHubStarRecord] = []
    @Published var isLoading = true

    private var lastFetchDate: Date?
    private let cacheDuration: TimeInterval = 5 * 60 // 5 minutes
    private let repoAPIURL = URL(string: "https://api.github.com/repos/zachlatta/freeflow")!
    private let stargazersAPIURL = URL(string: "https://api.github.com/repos/zachlatta/freeflow/stargazers?per_page=3")!

    private init() {}

    func fetchIfNeeded() async {
        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < cacheDuration {
            return
        }

        isLoading = true

        do {
            let repoResult = try await URLSession.shared.data(from: repoAPIURL)
            guard let repoHTTP = repoResult.1 as? HTTPURLResponse,
                  (200..<300).contains(repoHTTP.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let count = try JSONDecoder().decode(GitHubRepoInfo.self, from: repoResult.0).stargazersCount

            var request = URLRequest(url: stargazersAPIURL)
            request.setValue("application/vnd.github.v3.star+json", forHTTPHeaderField: "Accept")
            let starredResult = try await URLSession.shared.data(for: request)
            var recent: [GitHubStarRecord] = []
            if let starredHTTP = starredResult.1 as? HTTPURLResponse,
               (200..<300).contains(starredHTTP.statusCode) {
                recent = try JSONDecoder().decode([GitHubStarRecord].self, from: starredResult.0)
            }

            starCount = count
            githubCache.recentStargazers = recent
            isLoading = false
            lastFetchDate = Date()
        } catch {
            isLoading = false
        }
    }
}

struct HotkeyOptionRow: View {
    let option: HotkeyOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(option.displayName)
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

struct HowToRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
