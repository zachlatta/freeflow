import Foundation

enum ArchivePaths {
    static func cacheRoot(home: URL) -> URL {
        home.appendingPathComponent(".flowarchive").appendingPathComponent("cache")
    }

    static func rawCache(home: URL) -> URL {
        cacheRoot(home: home).appendingPathComponent("raw")
    }

    static func manifestURL(home: URL) -> URL {
        cacheRoot(home: home).appendingPathComponent("manifest.json")
    }

    static func libraryRoot(in parent: URL) -> URL {
        if parent.lastPathComponent.caseInsensitiveCompare("FlowArchive") == .orderedSame {
            return parent
        }
        return parent.appendingPathComponent("FlowArchive", isDirectory: true)
    }

    static func inbox(in libraryRoot: URL) -> URL {
        libraryRoot.appendingPathComponent("Inbox", isDirectory: true)
    }

    static func dropFolder(in libraryRoot: URL) -> URL {
        inbox(in: libraryRoot).appendingPathComponent("_drop", isDirectory: true)
    }

    static func ensureDirectory(_ url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
