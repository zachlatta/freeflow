import CryptoKit
import Foundation

struct IngestManifest: Codable, Equatable {
    var files: [String: String]

    init(files: [String: String] = [:]) {
        self.files = files
    }
}

struct IngestHasher {
    var home: URL
    var fileManager: FileManager

    init(home: URL, fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }

    var rawCache: URL { ArchivePaths.rawCache(home: home) }
    var manifestURL: URL { ArchivePaths.manifestURL(home: home) }

    func loadManifest() -> IngestManifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(IngestManifest.self, from: data)
        else { return IngestManifest() }
        return manifest
    }

    func saveManifest(_ manifest: IngestManifest) throws {
        try ArchivePaths.ensureDirectory(ArchivePaths.cacheRoot(home: home), fileManager: fileManager)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func ingestIfNew(url: URL) throws -> URL? {
        try ArchivePaths.ensureDirectory(rawCache, fileManager: fileManager)
        let hash = try Self.sha256Hex(of: url)
        var manifest = loadManifest()
        if manifest.files[hash] != nil {
            return nil
        }

        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension.lowercased()
        let destination = rawCache.appendingPathComponent("\(hash).\(ext)")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: url, to: destination)
        manifest.files[hash] = url.lastPathComponent
        try saveManifest(manifest)
        return destination
    }

    func remember(hash: String, originalName: String) throws {
        var manifest = loadManifest()
        manifest.files[hash] = originalName
        try saveManifest(manifest)
    }

    func contains(hash: String) -> Bool {
        loadManifest().files[hash] != nil
    }
}
