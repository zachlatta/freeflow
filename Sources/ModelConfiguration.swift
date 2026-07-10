import Foundation

public struct ModelConfig {
    public let maxCompletionTokens: Int?
    public let reasoningEffort: String?
    public let includeReasoning: Bool?
    public let shouldStripThinkTags: Bool
}

public struct ModelConfiguration {
    public static let llmModels = [
        "llama-3.3-70b-versatile",
        "llama-3.1-8b-instant",
        "meta-llama/llama-4-scout-17b-16e-instruct",
        "openai/gpt-oss-20b",
        "openai/gpt-oss-120b",
        "openai/gpt-oss-safeguard-20b",
        "qwen/qwen3-32b",
        "qwen/qwen3.6-27b",
        "allam-2-7b",
        "groq/compound",
        "groq/compound-mini",
        "canopylabs/orpheus-arabic-saudi",
        "canopylabs/orpheus-v1-english",
        "meta-llama/llama-prompt-guard-2-22m",
        "meta-llama/llama-prompt-guard-2-86m"
    ]

    public static let transcriptionModels = [
        "whisper-large-v3",
        "whisper-large-v3-turbo"
    ]

    public static func config(for model: String) -> ModelConfig {
        var cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Normalize providerless aliases
        if cleanModel == "qwen3-32b" { cleanModel = "qwen/qwen3-32b" }
        else if cleanModel == "qwen3.6-27b" { cleanModel = "qwen/qwen3.6-27b" }
        else if cleanModel == "gpt-oss-20b" { cleanModel = "openai/gpt-oss-20b" }
        else if cleanModel == "gpt-oss-120b" { cleanModel = "openai/gpt-oss-120b" }
        else if cleanModel == "gpt-oss-safeguard-20b" { cleanModel = "openai/gpt-oss-safeguard-20b" }
        
        if cleanModel == "openai/gpt-oss-20b" {
            return ModelConfig(
                maxCompletionTokens: 4096,
                reasoningEffort: "low",
                includeReasoning: false,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "openai/gpt-oss-120b" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "openai/gpt-oss-safeguard-20b" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "qwen/qwen3-32b" {
 // Model that requires sanitization of thought tags
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: true
            )
        } else if cleanModel == "qwen/qwen3.6-27b" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: true
            )
        } else if cleanModel == "llama-3.1-8b-instant" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "llama-3.3-70b-versatile" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "meta-llama/llama-4-scout-17b-16e-instruct" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "meta-llama/llama-prompt-guard-2-22m" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "meta-llama/llama-prompt-guard-2-86m" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "allam-2-7b" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "canopylabs/orpheus-arabic-saudi" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "canopylabs/orpheus-v1-english" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "groq/compound" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "groq/compound-mini" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "whisper-large-v3" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        } else if cleanModel == "whisper-large-v3-turbo" {
            return ModelConfig(
                maxCompletionTokens: nil,
                reasoningEffort: nil,
                includeReasoning: nil,
                shouldStripThinkTags: false
            )
        }
        
        // Fallback genérico para qualquer outro modelo que não esteja na lista acima
        return ModelConfig(
            maxCompletionTokens: nil,
            reasoningEffort: nil,
            includeReasoning: nil,
            shouldStripThinkTags: false
        )
    }
    
    /// Utility method to remove <think>...</think> tags and everything inside them.
    /// This also handles unclosed tags gracefully (e.g. if the model runs out of tokens).
    public static func stripThinkTags(_ text: String) -> String {
        var cleaned = text
        
        // First, replace fully closed tags: <think>...</think>
        // We use a group with + to catch multiple consecutive think blocks.
        let closedRegexPattern = "^(?:\\s*<think>[\\s\\S]*?</think>)+"
        if let regex = try? NSRegularExpression(pattern: closedRegexPattern, options: []) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // Next, if there is an unclosed <think> tag remaining (meaning it started thinking but got truncated),
        // we strip from the opening <think> tag to the very end of the string.
        let openRegexPattern = "^\\s*<think>[\\s\\S]*$"
        if let regex = try? NSRegularExpression(pattern: openRegexPattern, options: []) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
