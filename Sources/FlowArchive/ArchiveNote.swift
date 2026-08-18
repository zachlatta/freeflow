import Foundation

struct ArchiveNote: Identifiable, Hashable {
    var id: String { markdownURL.path }
    var title: String
    var date: Date
    var durationSeconds: Int
    var tags: [String]
    var summary: [String]
    var transcript: String
    var markdownURL: URL
    var audioURL: URL?
    var relativeFolder: String
    var hash: String
    var sourceVolume: String?

    var snippet: String {
        if let first = summary.first, !first.isEmpty { return first }
        let collapsed = transcript.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count > 80 {
            return String(collapsed.prefix(80)) + "…"
        }
        return collapsed
    }

    var durationLabel: String {
        let minutes = Double(durationSeconds) / 60.0
        if durationSeconds >= 60 {
            return String(format: "%.1f mins", minutes)
        }
        return "\(durationSeconds)s"
    }
}

enum ArchiveSidebarItem: Hashable {
    case inbox
    case today
    case folder(String)
    case tag(String)

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .folder(let name): return name.split(separator: "/").last.map(String.init) ?? name
        case .tag(let tag): return "#\(tag)"
        }
    }
}
