import Foundation

enum APIProvider: String, CaseIterable, Identifiable {
    case groq
    case openai
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openai: return "OpenAI"
        case .custom: return "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .groq: return "https://api.groq.com/openai/v1"
        case .openai: return "https://api.openai.com/v1"
        case .custom: return ""
        }
    }

    var transcriptionModel: String {
        switch self {
        case .groq: return "whisper-large-v3"
        case .openai: return "whisper-1"
        case .custom: return "whisper-large-v3"
        }
    }

    var chatModel: String {
        switch self {
        case .groq: return "meta-llama/llama-4-scout-17b-16e-instruct"
        case .openai: return "gpt-5-mini-2025-08-07"
        case .custom: return "meta-llama/llama-4-scout-17b-16e-instruct"
        }
    }

    var visionModel: String {
        chatModel
    }

    var apiKeyStorageKey: String {
        switch self {
        case .groq: return "groq_api_key"
        case .openai: return "openai_api_key"
        case .custom: return "custom_api_key"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .groq: return "Paste your Groq API key"
        case .openai: return "Paste your OpenAI API key"
        case .custom: return "Paste your API key"
        }
    }

    var keyInstructionURL: String {
        switch self {
        case .groq: return "https://console.groq.com/keys"
        case .openai: return "https://platform.openai.com/api-keys"
        case .custom: return ""
        }
    }

    var keyInstructionDisplayURL: String {
        switch self {
        case .groq: return "console.groq.com/keys"
        case .openai: return "platform.openai.com/api-keys"
        case .custom: return ""
        }
    }
}
