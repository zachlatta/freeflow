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
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        var depth = 0
        while let item = enumerator.nextObject() as? URL {
            if enumerator.level > 3 { enumerator.skipDescendants() }
            depth += 1
            if depth > 80 { break }
            let name = item.lastPathComponent.uppercased()
            if structureHints.contains(where: { name.contains($0) }) {
                return true
            }
        }
        return false
    }
}
