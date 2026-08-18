import Foundation

enum RecorderVolumeMatcher {
    static let defaultNameTokens = ["IC RECORDER", "IC_RECORDER", "RECORDER", "RECORDS"]
    static let structureHints = ["REC_FILE", "VOICE", "FOLDER01"]

    static func matches(
        volumeName: String,
        extraNames: [String] = [],
        hasRecorderStructure: Bool = false
    ) -> Bool {
        let name = volumeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return hasRecorderStructure }

        let upper = name.uppercased()
        for extra in extraNames {
            let token = extra.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            if upper.contains(token.uppercased()) { return true }
        }
        for token in defaultNameTokens {
            if upper.contains(token) { return true }
        }
        return hasRecorderStructure
    }

    static func hasRecorderStructure(at url: URL, fileManager: FileManager = .default) -> Bool {
        guard let items = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return items.contains { item in
            let name = item.lastPathComponent.uppercased()
            return structureHints.contains(where: { name.contains($0) }) || name.hasPrefix("FOLDER")
        }
    }

    static func searchRoots(at volume: URL, fileManager: FileManager = .default) -> [URL] {
        guard let items = try? fileManager.contentsOfDirectory(
            at: volume,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [volume] }

        let matches = items.filter { item in
            let name = item.lastPathComponent.uppercased()
            return structureHints.contains(where: { name.contains($0) }) || name.hasPrefix("FOLDER")
        }
        return matches.isEmpty ? [volume] : matches
    }
}
