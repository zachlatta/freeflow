import Foundation
import Security

public enum SharedStorageKeys {
    public static let appGroup = "group.com.shebetoff.freeflow"
    public static let keychainAccessGroup = "com.shebetoff.freeflow.shared"
    public static let keychainService = "com.shebetoff.freeflow"

    public static let apiKey = "groq_api_key"
    public static let apiBaseURL = "api_base_url"
    public static let transcriptionModel = "transcription_model"
    public static let postProcessingModel = "post_processing_model"
    public static let postProcessingFallbackModel = "post_processing_fallback_model"
    public static let customSystemPrompt = "custom_system_prompt"
    public static let customSystemPromptLastModified = "custom_system_prompt_last_modified"
    public static let customVocabulary = "custom_vocabulary"
    public static let voiceMacros = "voice_macros"

    public static let primedDurationSeconds = "primed_duration_seconds"
    public static let sessionPrimedUntil = "session_primed_until"
    public static let commandID = "command_id"
    public static let commandAction = "command_action"
    public static let resultID = "result_id"
    public static let resultText = "result_text"
    public static let resultError = "result_error"
    public static let recorderState = "recorder_state"
    public static let primeCallerBundleID = "prime_caller_bundle_id"
}

public enum DarwinNotifications {
    public static let prime = "com.shebetoff.freeflow.prime"
    public static let command = "com.shebetoff.freeflow.command"
    public static let result = "com.shebetoff.freeflow.result"
    public static let state = "com.shebetoff.freeflow.state"

    public static func post(_ name: String) {
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            cfName,
            nil,
            nil,
            true
        )
    }
}

public final class SharedStorage {
    public static let shared = SharedStorage()

    private let defaults: UserDefaults
    private let hasAppGroup: Bool

    public init() {
        if let grouped = UserDefaults(suiteName: SharedStorageKeys.appGroup) {
            self.defaults = grouped
            self.hasAppGroup = true
        } else {
            self.defaults = .standard
            self.hasAppGroup = false
        }
    }

    public var appGroupAvailable: Bool { hasAppGroup }

    public var apiKey: String {
        get { keychainRead(key: SharedStorageKeys.apiKey) ?? "" }
        set { keychainWrite(key: SharedStorageKeys.apiKey, value: newValue) }
    }

    public var apiBaseURL: String {
        get { defaults.string(forKey: SharedStorageKeys.apiBaseURL) ?? "https://api.groq.com/openai/v1" }
        set { defaults.set(newValue, forKey: SharedStorageKeys.apiBaseURL) }
    }

    public var transcriptionModel: String {
        get { defaults.string(forKey: SharedStorageKeys.transcriptionModel) ?? "whisper-large-v3" }
        set { defaults.set(newValue, forKey: SharedStorageKeys.transcriptionModel) }
    }

    public var postProcessingModel: String {
        get { defaults.string(forKey: SharedStorageKeys.postProcessingModel) ?? "" }
        set { defaults.set(newValue, forKey: SharedStorageKeys.postProcessingModel) }
    }

    public var postProcessingFallbackModel: String {
        get { defaults.string(forKey: SharedStorageKeys.postProcessingFallbackModel) ?? "" }
        set { defaults.set(newValue, forKey: SharedStorageKeys.postProcessingFallbackModel) }
    }

    public var customSystemPrompt: String {
        get { defaults.string(forKey: SharedStorageKeys.customSystemPrompt) ?? "" }
        set {
            defaults.set(newValue, forKey: SharedStorageKeys.customSystemPrompt)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            defaults.set(formatter.string(from: Date()), forKey: SharedStorageKeys.customSystemPromptLastModified)
        }
    }

    public var customSystemPromptLastModified: String {
        defaults.string(forKey: SharedStorageKeys.customSystemPromptLastModified) ?? Prompts.defaultSystemPromptDate
    }

    public var customVocabulary: String {
        get { defaults.string(forKey: SharedStorageKeys.customVocabulary) ?? "" }
        set { defaults.set(newValue, forKey: SharedStorageKeys.customVocabulary) }
    }

    public var primedDurationSeconds: Double {
        get {
            let value = defaults.double(forKey: SharedStorageKeys.primedDurationSeconds)
            return value > 0 ? value : 300
        }
        set { defaults.set(newValue, forKey: SharedStorageKeys.primedDurationSeconds) }
    }

    public var sessionPrimedUntil: Date? {
        get {
            let ts = defaults.double(forKey: SharedStorageKeys.sessionPrimedUntil)
            guard ts > 0 else { return nil }
            return Date(timeIntervalSince1970: ts)
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: SharedStorageKeys.sessionPrimedUntil) }
    }

    public var isSessionPrimed: Bool {
        guard let until = sessionPrimedUntil else { return false }
        return until > Date()
    }

    public func issueCommand(action: String) -> String {
        let id = UUID().uuidString
        defaults.set(action, forKey: SharedStorageKeys.commandAction)
        defaults.set(id, forKey: SharedStorageKeys.commandID)
        DarwinNotifications.post(DarwinNotifications.command)
        return id
    }

    public func readCommand() -> (id: String, action: String)? {
        guard let id = defaults.string(forKey: SharedStorageKeys.commandID),
              let action = defaults.string(forKey: SharedStorageKeys.commandAction) else {
            return nil
        }
        return (id, action)
    }

    public func writeResult(id: String, text: String?, error: String?) {
        defaults.set(id, forKey: SharedStorageKeys.resultID)
        defaults.set(text ?? "", forKey: SharedStorageKeys.resultText)
        defaults.set(error ?? "", forKey: SharedStorageKeys.resultError)
        DarwinNotifications.post(DarwinNotifications.result)
    }

    public func readResult() -> (id: String, text: String, error: String)? {
        guard let id = defaults.string(forKey: SharedStorageKeys.resultID) else { return nil }
        let text = defaults.string(forKey: SharedStorageKeys.resultText) ?? ""
        let error = defaults.string(forKey: SharedStorageKeys.resultError) ?? ""
        return (id, text, error)
    }

    public var recorderState: String {
        get { defaults.string(forKey: SharedStorageKeys.recorderState) ?? "idle" }
        set {
            defaults.set(newValue, forKey: SharedStorageKeys.recorderState)
            DarwinNotifications.post(DarwinNotifications.state)
        }
    }

    public var voiceMacros: [VoiceMacro] {
        get {
            guard let data = defaults.data(forKey: SharedStorageKeys.voiceMacros) else { return [] }
            return (try? JSONDecoder().decode([VoiceMacro].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: SharedStorageKeys.voiceMacros)
        }
    }

    public var resolvedSystemPrompt: String {
        let trimmed = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Prompts.defaultSystemPrompt : trimmed
    }

    public func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStorageKeys.appGroup)
    }

    private func keychainQuery(key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedStorageKeys.keychainService,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        #if !targetEnvironment(simulator)
        if let prefix = appIdentifierPrefix() {
            query[kSecAttrAccessGroup as String] = "\(prefix)\(SharedStorageKeys.keychainAccessGroup)"
        }
        #endif
        return query
    }

    private func appIdentifierPrefix() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "bundleSeedID",
            kSecAttrService as String: "bundleSeedID",
            kSecReturnAttributes as String: true
        ]
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            status = SecItemAdd(query as CFDictionary, &result)
        }
        guard status == errSecSuccess, let attrs = result as? [String: Any],
              let accessGroup = attrs[kSecAttrAccessGroup as String] as? String else {
            return nil
        }
        let components = accessGroup.split(separator: ".")
        guard let prefix = components.first else { return nil }
        return "\(prefix)."
    }

    private func keychainRead(key: String) -> String? {
        var query = keychainQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainWrite(key: String, value: String) {
        let query = keychainQuery(key: key)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = Data(value.utf8)
            SecItemAdd(insertQuery as CFDictionary, nil)
        } else if status != errSecSuccess {
            SecItemDelete(query as CFDictionary)
            var insertQuery = query
            insertQuery[kSecValueData as String] = Data(value.utf8)
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }
}
