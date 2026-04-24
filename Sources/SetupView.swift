import SwiftUI
import AVFoundation
import Combine
import Foundation
import ServiceManagement

private struct SetupProviderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var apiBaseURLInput: String
    @Binding var transcriptionAPIURLInput: String
    @Binding var transcriptionAPIKeyInput: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Advanced Provider Settings")
                    .font(.title2.weight(.semibold))
                Text("Use these fields when pointing FreeFlow at another OpenAI-compatible provider or when you need custom model IDs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            ScrollView {
                ProviderSettingsFields(
                    apiBaseURLInput: $apiBaseURLInput,
                    transcriptionAPIURLInput: $transcriptionAPIURLInput,
                    transcriptionAPIKeyInput: $transcriptionAPIKeyInput,
                    showsModelDescription: true
                )
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
    }
}

struct SetupView: View {
    var onComplete: () -> Void
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    private let freeflowRepoURL = URL(string: "https://github.com/zachlatta/freeflow")!
    private enum SetupStep: Int, CaseIterable {
        case welcome = 0
        case apiKey
        case micPermission
        case accessibility
        case screenRecording
        case holdShortcut
        case toggleShortcut
        case commandMode
        case vocabulary
        case launchAtLogin
        case testTranscription
        case ready
    }

    @State private var currentStep = SetupStep.welcome
    @State private var micPermissionGranted = false
    @State private var accessibilityGranted = false
    @State private var apiKeyInput: String = ""
    @State private var apiBaseURLInput: String = ""
    @State private var transcriptionAPIURLInput: String = ""
    @State private var transcriptionAPIKeyInput: String = ""
    @State private var isValidatingKey = false
    @State private var keyValidationError: String?
    @State private var showingProviderSettingsSheet = false
    @State private var accessibilityTimer: Timer?
    @State private var screenRecordingTimer: Timer?
    @State private var customVocabularyInput: String = ""
    @StateObject private var githubCache = GitHubMetadataCache.shared

    // Test transcription state
    private enum TestPhase: Equatable {
        case idle, recording, transcribing, done
    }
    @State private var testPhase: TestPhase = .idle
    @State private var testAudioRecorder: AudioRecorder? = nil
    @State private var testAudioLevel: Float = 0.0
    @State private var testTranscript: String = ""
    @State private var testError: String? = nil
    @State private var testAudioLevelCancellable: AnyCancellable? = nil
    @State private var testMicPulsing = false
    @State private var holdShortcutValidationMessage: String?
    @State private var toggleShortcutValidationMessage: String?
    @State private var isCapturingHoldShortcut = false
    @State private var isCapturingToggleShortcut = false
    @StateObject private var testHotkeyHarness = SetupTestHotkeyHarness()

    private let totalSteps: [SetupStep] = SetupStep.allCases
    private var isCapturingShortcut: Bool {
        isCapturingHoldShortcut || isCapturingToggleShortcut
    }

    var body: some View {
        VStack(spacing: 0) {
            currentStepView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.vertical, 32)

            Divider()

            ZStack {
                stepIndicator

                HStack(alignment: .center) {
                    Group {
                        if currentStep != .welcome {
                            Button("Back") {
                                keyValidationError = nil
                                withAnimation {
                                    currentStep = previousStep(currentStep)
                                }
                            }
                            .disabled(isValidatingKey)
                        }
                    }

                    Spacer()

                    Group {
                        if currentStep != .ready {
                            if currentStep == .apiKey {
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
                            } else if currentStep == .testTranscription {
                                HStack(spacing: 10) {
                                    Button("Skip") {
                                        stopTestHotkeyMonitoring()
                                        withAnimation {
                                            currentStep = nextStep(currentStep)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)

                                    Button("Continue") {
                                        stopTestHotkeyMonitoring()
                                        withAnimation {
                                            currentStep = nextStep(currentStep)
                                        }
                                    }
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(testPhase != .done || testTranscript.isEmpty || testError != nil)
                                }
                            } else {
                                Button("Continue") {
                                    withAnimation {
                                        currentStep = nextStep(currentStep)
                                    }
                                }
                                .keyboardShortcut(.defaultAction)
                                .disabled(!canContinueFromCurrentStep)
                            }
                        } else {
                            Button("Get Started") {
                                onComplete()
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 520, height: 680)
        .onAppear {
            apiKeyInput = appState.apiKey
            apiBaseURLInput = appState.apiBaseURL
            transcriptionAPIURLInput = appState.transcriptionAPIURL
            transcriptionAPIKeyInput = appState.transcriptionAPIKey
            customVocabularyInput = appState.customVocabulary
            checkMicPermission()
            checkAccessibility()
            Task {
                await githubCache.fetchIfNeeded()
            }
        }
        .onDisappear {
            accessibilityTimer?.invalidate()
            screenRecordingTimer?.invalidate()
            appState.resumeHotkeyMonitoringAfterShortcutCapture()
        }
        .sheet(isPresented: $showingProviderSettingsSheet) {
            SetupProviderSettingsSheet(
                apiBaseURLInput: $apiBaseURLInput,
                transcriptionAPIURLInput: $transcriptionAPIURLInput,
                transcriptionAPIKeyInput: $transcriptionAPIKeyInput
            )
                .environmentObject(appState)
        }
        .onChange(of: isCapturingShortcut) { isCapturing in
            if isCapturing {
                appState.suspendHotkeyMonitoringForShortcutCapture()
            } else {
                appState.resumeHotkeyMonitoringAfterShortcutCapture()
            }
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
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
        case .holdShortcut:
            holdShortcutStep
        case .toggleShortcut:
            toggleShortcutStep
        case .commandMode:
            commandModeStep
        case .vocabulary:
            vocabularyStep
        case .launchAtLogin:
            launchAtLoginStep
        case .testTranscription:
            testTranscriptionStep
        case .ready:
            readyStep
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
                Text("Welcome to \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FreeFlow")")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("Dictate text anywhere on your Mac.\nHold to talk or tap to toggle dictation.")
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
    }

    var apiKeyStep: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("API Key")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Enter an API key for your OpenAI-compatible provider. If you are not using Groq, expand the advanced provider settings and enter that provider's base URL and model IDs before continuing.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Using Groq?")
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
                        SecureField("Paste your API key", text: $apiKeyInput)
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

                    Button {
                        showingProviderSettingsSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Advanced Provider Settings")
                                    .foregroundStyle(.primary)
                                Text("Base URL and model IDs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: 440)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            Text("FreeFlow intelligently adapts the transcription to the current app you're working in (ex. spelling names in an email correctly).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("It needs this permission to see which app you're working in and any in-progress work. Nothing is stored on FreeFlow's servers (FreeFlow doesn't have servers).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
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

        }
        .onAppear {
            startScreenRecordingPolling()
        }
        .onDisappear {
            screenRecordingTimer?.invalidate()
        }
    }

    var holdShortcutStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Hold to Talk Shortcut")
                .font(.title)
                .fontWeight(.bold)

            Text("Choose the shortcut you want to hold while speaking.\nRelease it to stop unless you latch into tap mode later, or disable hold-to-talk entirely.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ShortcutRoleSection(
                role: .hold,
                selection: appState.holdShortcut,
                validationMessage: holdShortcutValidationMessage,
                isCapturing: $isCapturingHoldShortcut,
                onSelect: { binding in
                    holdShortcutValidationMessage = appState.setShortcut(binding, for: .hold)
                }
            )
                .padding(.top, 10)

            if appState.holdShortcut.usesFnKey {
                Text("Tip: If Fn opens Emoji picker, go to System Settings > Keyboard and change \"Press fn key to\" to \"Do Nothing\".")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

        }
    }

    var toggleShortcutStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "switch.2")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Tap to Toggle Shortcut")
                .font(.title)
                .fontWeight(.bold)

            Text("Choose the shortcut you want to tap once to start dictating and tap again to stop.\nIf this shortcut becomes active while you are holding the hold shortcut, FreeFlow latches into tap mode. You can also disable tap-to-toggle entirely.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ShortcutRoleSection(
                role: .toggle,
                selection: appState.toggleShortcut,
                validationMessage: toggleShortcutValidationMessage,
                isCapturing: $isCapturingToggleShortcut,
                onSelect: { binding in
                    toggleShortcutValidationMessage = appState.setShortcut(binding, for: .toggle)
                }
            )
                .padding(.top, 10)

            if appState.toggleShortcut.usesFnKey {
                Text("Tip: If Fn opens Emoji picker, go to System Settings > Keyboard and change \"Press fn key to\" to \"Do Nothing\".")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

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

        }
    }

    var commandModeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "pencil")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Edit Mode")
                .font(.title)
                .fontWeight(.bold)

            Text("Transform selected text with a spoken instruction instead of dictating over it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Enable Edit Mode", isOn: Binding(
                    get: { appState.isCommandModeEnabled },
                    set: { newValue in
                        _ = appState.setCommandModeEnabled(newValue)
                    }
                ))

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
                        Text("Automatic mode uses your normal dictation shortcut. If text is selected, FreeFlow transforms that selection instead of dictating new text.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .manual:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Manual mode only triggers when you hold an extra modifier together with your normal dictation shortcut.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
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

        }
    }

    var testTranscriptionStep: some View {
        VStack(spacing: 20) {
            // Microphone picker
            VStack(spacing: 4) {
                Picker("Microphone:", selection: $appState.selectedMicrophoneID) {
                    Text("System Default").tag("default")
                    ForEach(appState.availableMicrophones) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .frame(maxWidth: 340)

                Text("You can change this later in the menu bar or settings.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Group {
                switch testPhase {
                case .idle:
                    VStack(spacing: 20) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                            .scaleEffect(testMicPulsing ? 1.15 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: testMicPulsing)

                        Text("Let's Try It Out!")
                            .font(.title)
                            .fontWeight(.bold)

                        Text(testShortcutPrompt)
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)

                        Text("Say anything — a sentence or two is perfect.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                case .recording:
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.65))
                                .frame(width: 100, height: 100)

                            Circle()
                                .stroke(Color.blue.opacity(0.8), lineWidth: 3)
                                .frame(width: 100, height: 100)
                                .shadow(color: .blue.opacity(0.5), radius: 10)

                            WaveformView(audioLevel: testAudioLevel)
                        }

                        Text("Listening...")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }

                case .transcribing:
                    VStack(spacing: 20) {
                        InlineTranscribingDots()

                        Text("Transcribing...")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }

                case .done:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        if let error = testError {
                            Text("Something went wrong")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Text(retryShortcutPrompt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else if testTranscript.isEmpty {
                            Text("No speech detected")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text(retryShortcutPrompt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Perfect — FreeFlow is ready to go.")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(testTranscript)
                                .font(.body)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(10)
                                .transition(.move(edge: .bottom).combined(with: .opacity))

                            Text(retryShortcutPrompt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .transition(.opacity)
            .id(testPhase)

            Spacer()
        }
        .onAppear {
            appState.refreshAvailableMicrophones()
            testMicPulsing = true
            startTestHotkeyMonitoring()
        }
        .onDisappear {
            stopTestHotkeyMonitoring()
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
                if appState.hasEnabledHoldShortcut {
                    HowToRow(icon: "keyboard", text: "Hold \(appState.holdShortcut.displayName) to record")
                }
                if appState.hasEnabledToggleShortcut {
                    HowToRow(icon: "switch.2", text: "Tap \(appState.toggleShortcut.displayName) to start and stop")
                }
                if appState.hasEnabledHoldShortcut && appState.hasEnabledToggleShortcut {
                    HowToRow(icon: "arrow.triangle.branch", text: "While holding, press the toggle shortcut to latch on")
                }
                if appState.isCommandModeEnabled {
                    switch appState.commandModeStyle {
                    case .automatic:
                        HowToRow(icon: "wand.and.stars", text: "With text selected, your normal shortcut transforms the selection")
                    case .manual:
                        HowToRow(
                            icon: "wand.and.stars",
                            text: "Hold \(appState.commandModeManualModifier.title) with your normal shortcut to transform selected text"
                        )
                    }
                }
                HowToRow(icon: "doc.on.clipboard", text: "Text is typed at your cursor & copied")
            }
            .padding(.top, 10)

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
    }

    private var canContinueFromCurrentStep: Bool {
        switch currentStep {
        case .micPermission:
            return micPermissionGranted
        case .accessibility:
            return accessibilityGranted
        case .screenRecording:
            return appState.hasScreenRecordingPermission
        case .testTranscription:
            return testPhase == .done && !testTranscript.isEmpty && testError == nil
        default:
            return true
        }
    }

    private var testShortcutPrompt: String {
        switch (appState.hasEnabledHoldShortcut, appState.hasEnabledToggleShortcut) {
        case (true, true):
            return "Hold \(appState.holdShortcut.displayName) or tap \(appState.toggleShortcut.displayName)"
        case (true, false):
            return "Hold \(appState.holdShortcut.displayName)"
        case (false, true):
            return "Tap \(appState.toggleShortcut.displayName)"
        case (false, false):
            return "Use Start Dictating from the menu bar"
        }
    }

    private var retryShortcutPrompt: String {
        "\(testShortcutPrompt) to try again"
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
        let baseURL = apiBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseURL = baseURL.isEmpty ? AppState.defaultAPIBaseURL : baseURL
        appState.apiBaseURL = resolvedBaseURL
        isValidatingKey = true
        keyValidationError = nil

        Task {
            let valid = await TranscriptionService.validateAPIKey(key, baseURL: resolvedBaseURL)
            await MainActor.run {
                isValidatingKey = false
                if valid {
                    appState.apiKey = key
                    withAnimation {
                        currentStep = nextStep(currentStep)
                    }
                } else {
                    keyValidationError = "Validation failed. Please check your API key and provider settings, then try again."
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
        appState.requestMicrophoneAccess { granted in
            micPermissionGranted = granted
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
        appState.openAccessibilitySettings()
    }

    func startScreenRecordingPolling() {
        screenRecordingTimer?.invalidate()
        screenRecordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                appState.hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
            }
        }
    }

    // MARK: - Test Transcription

    private func startTestHotkeyMonitoring() {
        testHotkeyHarness.onAction = { action in
            switch action {
            case .start:
                guard testPhase == .idle || testPhase == .done else { return }
                if testPhase == .done {
                    resetTest()
                }
                do {
                    let recorder = AudioRecorder()
                    recorder.onRecordingFailure = { [weak recorder] error in
                        guard let recorder else { return }
                        Task { @MainActor in
                            testAudioLevelCancellable?.cancel()
                            testAudioLevelCancellable = nil
                            testAudioLevel = 0.0
                            testHotkeyHarness.isTranscribing = false
                            testAudioRecorder = nil
                            testError = error.localizedDescription
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                testPhase = .done
                            }
                            recorder.cleanup()
                        }
                    }
                    try recorder.startRecording(deviceUID: appState.selectedMicrophoneID)
                    testAudioRecorder = recorder
                    testError = nil
                    testAudioLevelCancellable = recorder.$audioLevel
                        .receive(on: DispatchQueue.main)
                        .sink { level in
                            testAudioLevel = level
                        }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        testPhase = .recording
                    }
                } catch {
                    testHotkeyHarness.resetSession()
                    testError = error.localizedDescription
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        testPhase = .done
                    }
                }

            case .stop:
                guard testPhase == .recording, let recorder = testAudioRecorder else { return }
                testAudioLevelCancellable?.cancel()
                testAudioLevelCancellable = nil
                testAudioLevel = 0.0
                testHotkeyHarness.isTranscribing = true

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    testPhase = .transcribing
                }
                recorder.stopRecording { url in
                    guard let url else {
                        Task { @MainActor in
                            testHotkeyHarness.isTranscribing = false
                            testAudioRecorder = nil
                            if testError == nil {
                                testError = "No audio file was created."
                            }
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                testPhase = .done
                            }
                            recorder.cleanup()
                        }
                        return
                    }

                    Task {
                        do {
                            let service = try appState.makeTranscriptionService()
                            let transcript = try await service.transcribe(fileURL: url)
                            await MainActor.run {
                                testHotkeyHarness.isTranscribing = false
                                testAudioRecorder = nil
                                testTranscript = transcript
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    testPhase = .done
                                }
                            }
                        } catch {
                            await MainActor.run {
                                testHotkeyHarness.isTranscribing = false
                                testAudioRecorder = nil
                                testError = error.localizedDescription
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    testPhase = .done
                                }
                            }
                        }
                        await MainActor.run {
                            recorder.cleanup()
                        }
                    }
                }

            case .switchedToToggle:
                break
            }
        }

        do {
            try testHotkeyHarness.start(configuration: ShortcutConfiguration(
                hold: appState.holdShortcut,
                toggle: appState.toggleShortcut
            ), startDelay: appState.shortcutStartDelay)
        } catch {
            testError = error.localizedDescription
            testPhase = .done
        }
    }

    private func stopTestHotkeyMonitoring() {
        testHotkeyHarness.stop()
        testAudioLevelCancellable?.cancel()
        testAudioLevelCancellable = nil
        if let recorder = testAudioRecorder, recorder.isRecording {
            recorder.cancelRecording()
        }
        testAudioRecorder = nil
    }

    private func resetTest() {
        testPhase = .idle
        testTranscript = ""
        testError = nil
        testAudioLevel = 0.0
        testMicPulsing = true
        testHotkeyHarness.isTranscribing = false
        testHotkeyHarness.resetSession()
        if let recorder = testAudioRecorder {
            if recorder.isRecording {
                recorder.cancelRecording()
            }
            testAudioRecorder = nil
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

    /// Avatar URL resized to 44px (2x for 22pt display) for efficient loading
    var avatarThumbnailUrl: URL {
        // GitHub avatar URLs already have query params, so append with &
        let separator = avatarUrl.absoluteString.contains("?") ? "&" : "?"
        return URL(string: avatarUrl.absoluteString + "\(separator)s=44") ?? avatarUrl
    }

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
    @Published var recentStargazers: [GitHubStarRecord] = []
    @Published var isLoading = true

    private var lastFetchDate: Date?
    private let cacheDuration: TimeInterval = 5 * 60 // 5 minutes
    private let repoAPIURL = URL(string: "https://api.github.com/repos/zachlatta/freeflow")!

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

            var recent: [GitHubStarRecord] = []
            if count > 0 {
                let perPage = 100
                let lastPage = max(1, Int(ceil(Double(count) / Double(perPage))))
                let stargazersURL = URL(string: "https://api.github.com/repos/zachlatta/freeflow/stargazers?per_page=\(perPage)&page=\(lastPage)")!
                var request = URLRequest(url: stargazersURL)
                request.setValue("application/vnd.github.v3.star+json", forHTTPHeaderField: "Accept")
                let starredResult = try await URLSession.shared.data(for: request)
                if let starredHTTP = starredResult.1 as? HTTPURLResponse,
                   (200..<300).contains(starredHTTP.statusCode) {
                    let all = try JSONDecoder().decode([GitHubStarRecord].self, from: starredResult.0)
                    recent = Array(all.suffix(15).reversed())
                }
            }

            starCount = count
            recentStargazers = recent
            isLoading = false
            lastFetchDate = Date()
        } catch {
            isLoading = false
        }
    }
}

private struct InlineTranscribingDots: View {
    @State private var activeDot = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.blue.opacity(activeDot == index ? 1.0 : 0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(activeDot == index ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: activeDot)
            }
        }
        .onReceive(timer) { _ in
            activeDot = (activeDot + 1) % 3
        }
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
