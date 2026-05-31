import Foundation
import Security

enum AppSettingsStorage {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.zachlatta.freeflow"

    private static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appName = AppName.displayName
        let dir = appSupport.appendingPathComponent(appName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static var settingsFileURL: URL {
        storageDirectory.appendingPathComponent(".settings")
    }

    // MARK: - Public API

    static func load(account: String) -> String? {
        migratePlaintextSettingToKeychainIfNeeded(account: account)
        return loadFromKeychain(account: account)
    }

    static func save(_ value: String, account: String) {
        removePlaintextSetting(account: account)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteFromKeychain(account: account)
        } else {
            saveToKeychain(value, account: account)
        }
    }

    static func delete(account: String) {
        deleteFromKeychain(account: account)
        removePlaintextSetting(account: account)
    }

    // MARK: - File I/O

    private static func loadSettings() -> [String: String] {
        let url = settingsFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func writeSettings(_ dict: [String: String]) {
        let url = settingsFileURL
        guard !dict.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: url, options: [.atomic])
        // Restrict to owner-only read/write (0600)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    // MARK: - Plaintext migration

    private static func migratePlaintextSettingToKeychainIfNeeded(account: String) {
        var dict = loadSettings()
        guard let plaintextValue = dict[account] else { return }

        let existingKeychainValue = loadFromKeychain(account: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingKeychainValue.isEmpty,
           !plaintextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveToKeychain(plaintextValue, account: account)
        }

        dict.removeValue(forKey: account)
        dict.removeValue(forKey: "keychain_migration_done")
        writeSettings(dict)
    }

    private static func removePlaintextSetting(account: String) {
        var dict = loadSettings()
        guard dict[account] != nil || dict["keychain_migration_done"] != nil else { return }
        dict.removeValue(forKey: account)
        dict.removeValue(forKey: "keychain_migration_done")
        writeSettings(dict)
    }

    // MARK: - Keychain helpers

    private static func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: bundleID,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func saveToKeychain(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: bundleID,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: bundleID,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: bundleID,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
