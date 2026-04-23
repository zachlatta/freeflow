import SwiftUI

@main
struct FreeFlowApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { url in
                    guard url.scheme == "freeflow" else { return }
                    switch url.host {
                    case "prime":
                        RecordingSession.shared.prime(suspendAfter: true)
                    default:
                        break
                    }
                }
        }
    }
}

final class AppStore: ObservableObject {
    @Published var apiKey: String
    @Published var apiBaseURL: String
    @Published var transcriptionModel: String
    @Published var postProcessingModel: String
    @Published var postProcessingFallbackModel: String
    @Published var customSystemPrompt: String
    @Published var customVocabulary: String
    @Published var voiceMacros: [VoiceMacro]
    @Published var primedDurationMinutes: Double
    @Published var apiKeyValid: Bool?

    private let storage = SharedStorage.shared

    init() {
        self.apiKey = storage.apiKey
        self.apiBaseURL = storage.apiBaseURL
        self.transcriptionModel = storage.transcriptionModel
        self.postProcessingModel = storage.postProcessingModel
        self.postProcessingFallbackModel = storage.postProcessingFallbackModel
        self.customSystemPrompt = storage.customSystemPrompt
        self.customVocabulary = storage.customVocabulary
        self.voiceMacros = storage.voiceMacros
        self.primedDurationMinutes = storage.primedDurationSeconds / 60.0
    }

    func persistApiKey() {
        storage.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func persistAll() {
        storage.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.apiBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.transcriptionModel = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.postProcessingModel = postProcessingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.postProcessingFallbackModel = postProcessingFallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.customSystemPrompt = customSystemPrompt
        storage.customVocabulary = customVocabulary
        storage.voiceMacros = voiceMacros
        storage.primedDurationSeconds = max(60, primedDurationMinutes * 60.0)
    }

    func resolvedSystemPromptLastModified() -> String {
        storage.customSystemPromptLastModified
    }

    func validateApiKey() async {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://api.groq.com/openai/v1"
            : apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await TranscriptionService.validateAPIKey(trimmed, baseURL: baseURL)
        await MainActor.run { self.apiKeyValid = ok }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("Setup", systemImage: "checkmark.seal") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
        }
    }
}
