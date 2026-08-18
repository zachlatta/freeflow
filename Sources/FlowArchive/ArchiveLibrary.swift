import Foundation

final class ArchiveLibrary {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan(libraryRoot: URL) -> [ArchiveNote] {
        guard fileManager.fileExists(atPath: libraryRoot.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: libraryRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var notes: [ArchiveNote] = []
        while let item = enumerator.nextObject() as? URL {
            if item.path.contains("/_drop/") { continue }
            guard item.pathExtension.lowercased() == "md" else { continue }
            guard let parsed = parseNote(at: item, libraryRoot: libraryRoot) else { continue }
            notes.append(parsed)
        }
        return notes.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func folders(from notes: [ArchiveNote]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for note in notes {
            let folder = note.relativeFolder
            if seen.insert(folder).inserted {
                result.append(folder)
            }
        }
        return result.sorted()
    }

    func tags(from notes: [ArchiveNote]) -> [String] {
        var seen = Set<String>()
        for note in notes {
            for tag in note.tags { seen.insert(tag.lowercased()) }
        }
        return seen.sorted()
    }

    private func parseNote(at markdownURL: URL, libraryRoot: URL) -> ArchiveNote? {
        guard let text = try? String(contentsOf: markdownURL, encoding: .utf8),
              let parsed = ArchiveMarkdownWriter.parse(text)
        else { return nil }

        let audioURL = markdownURL.deletingLastPathComponent()
            .appendingPathComponent(parsed.frontMatter.audio)
        let audioExists = fileManager.fileExists(atPath: audioURL.path)

        let relative = relativeFolder(for: markdownURL, libraryRoot: libraryRoot)
        return ArchiveNote(
            title: parsed.frontMatter.title,
            date: parsed.frontMatter.date,
            durationSeconds: parsed.frontMatter.durationSeconds,
            tags: parsed.frontMatter.tags,
            summary: parsed.summary,
            transcript: parsed.transcript,
            markdownURL: markdownURL,
            audioURL: audioExists ? audioURL : nil,
            relativeFolder: relative,
            hash: parsed.frontMatter.hash,
            sourceVolume: parsed.frontMatter.sourceVolume
        )
    }

    private func relativeFolder(for markdownURL: URL, libraryRoot: URL) -> String {
        let folder = markdownURL.deletingLastPathComponent()
        let rootPath = libraryRoot.standardizedFileURL.path
        let folderPath = folder.standardizedFileURL.path
        if folderPath == rootPath { return FolderRouter.inbox }
        if folderPath.hasPrefix(rootPath + "/") {
            let relative = String(folderPath.dropFirst(rootPath.count + 1))
            return relative.isEmpty ? FolderRouter.inbox : relative
        }
        return FolderRouter.inbox
    }
}
