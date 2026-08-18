import Foundation

struct FolderRule: Codable, Equatable, Identifiable {
    var id: UUID
    var keyword: String
    var folder: String

    init(id: UUID = UUID(), keyword: String, folder: String) {
        self.id = id
        self.keyword = keyword
        self.folder = folder
    }
}

enum FolderRouter {
    static let inbox = "Inbox"

    static func relativeFolder(
        tags: [String],
        transcript: String,
        rules: [FolderRule]
    ) -> String {
        let tagSet = Set(tags.map { $0.lowercased() })
        let haystack = (tags.joined(separator: " ") + " " + transcript).lowercased()

        for rule in rules {
            let key = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if tagSet.contains(key.lowercased()) {
                return sanitizeRelativePath(rule.folder)
            }
            if haystack.contains(key.lowercased()) {
                return sanitizeRelativePath(rule.folder)
            }
        }
        return inbox
    }

    static func sanitizeRelativePath(_ path: String) -> String {
        if path.contains("..") { return inbox }
        let parts = path
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." }
        if parts.isEmpty { return inbox }
        return parts.joined(separator: "/")
    }
}
