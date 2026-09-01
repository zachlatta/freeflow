import Combine
import CryptoKit
import Foundation

struct LocalParakeetModelAsset: Equatable {
    let relativePath: String
    let byteCount: Int64
    let sha256: String
}

struct LocalParakeetModelStore {
    static let repositoryDirectoryName = "mweinbach1_parakeet-tdt-0.6b-v3-coreml"
    static let legacyMarkerContents = "freeflow-parakeet-coreml-v1\n"
    static let downloadByteCount: Int64 = 480_766_756
    static let pinnedAssets = [
        LocalParakeetModelAsset(
            relativePath: "encoder.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            byteCount: 625_663,
            sha256: "2e4e6b54f32029d7b2a69549c2cedf5cd9c6daa8e5274a2b357fc7911747204b"
        ),
        LocalParakeetModelAsset(
            relativePath: "encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            byteCount: 444_016_768,
            sha256: "23867a834223ee6484d0b7b9b703530e8606546efa8e710535163d51ed9aac04"
        ),
        LocalParakeetModelAsset(
            relativePath: "encoder.mlpackage/Manifest.json",
            byteCount: 617,
            sha256: "9fd1153994eb4bdae923626ffc4684c6e0ce547ab393f0d15010c0c3ed14ece7"
        ),
        LocalParakeetModelAsset(
            relativePath: "decoder.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            byteCount: 12_897,
            sha256: "8d068618a9fd3a981d6cbc09ae9643a25b2e382f2c3e05d3b9412b9c25a4372e"
        ),
        LocalParakeetModelAsset(
            relativePath: "decoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            byteCount: 24_425_600,
            sha256: "36cd656ebf1105ee5aa85d1e55c00f25669327aef8b39346333a19260ca78018"
        ),
        LocalParakeetModelAsset(
            relativePath: "decoder.mlpackage/Manifest.json",
            byteCount: 617,
            sha256: "ef610fe0ccaff752f58f086772207ffb08970e67bf41fd07c923f9e006f8e4ec"
        ),
        LocalParakeetModelAsset(
            relativePath: "joint.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            byteCount: 4_025,
            sha256: "cde4d7c509e8053ec7c90d04368f2d4bb5ad8db87a28b550de80541193100a39"
        ),
        LocalParakeetModelAsset(
            relativePath: "joint.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            byteCount: 10_510_028,
            sha256: "d83381f8a19ac296033554a7cfec355063b8f3225129cb8bed013c92f6ab141f"
        ),
        LocalParakeetModelAsset(
            relativePath: "joint.mlpackage/Manifest.json",
            byteCount: 617,
            sha256: "977190c2261e2040f081fd0669fa3da7c4089c7d3f04c04a3c2b25e63f77f45c"
        ),
        LocalParakeetModelAsset(
            relativePath: "tokenizer.json",
            byteCount: 1_159_960,
            sha256: "bd321b096832a3f270bd3b2a88823957920f1a5c5ada71114a26ea729d0cbe91"
        ),
    ]

    let cacheRoot: URL
    let assets: [LocalParakeetModelAsset]

    init(cacheRoot: URL = Self.defaultCacheRoot(), assets: [LocalParakeetModelAsset] = Self.pinnedAssets) {
        self.cacheRoot = cacheRoot
        self.assets = assets
    }

    static func defaultCacheRoot() -> URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return cache.appendingPathComponent("com.parakeet-tdt", isDirectory: true)
    }

    var modelDirectory: URL {
        cacheRoot
            .appendingPathComponent("hf-models", isDirectory: true)
            .appendingPathComponent(Self.repositoryDirectoryName, isDirectory: true)
    }

    private var verifiedMarkerURL: URL {
        modelDirectory.appendingPathComponent(".freeflow-verified", isDirectory: false)
    }

    private var compiledCacheRoot: URL {
        cacheRoot.appendingPathComponent("mlmodelc", isDirectory: true)
    }

    var isInstalled: Bool {
        guard installationMarker != nil else { return false }
        return assets.allSatisfy { asset in
            let url = modelDirectory.appendingPathComponent(asset.relativePath)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value == asset.byteCount
        }
    }

    func validateDownloadedModel() throws {
        for asset in assets {
            let url = modelDirectory.appendingPathComponent(asset.relativePath)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.int64Value == asset.byteCount,
                  try Self.sha256(of: url) == asset.sha256 else {
                throw LocalParakeetModelError.integrityCheckFailed
            }
        }
    }

    func markInstalled(compiledCacheDirectories: Set<String> = []) throws {
        let marker = LocalParakeetInstallationMarker(
            version: 2,
            compiledCacheDirectories: compiledCacheDirectories.sorted()
        )
        try JSONEncoder().encode(marker).write(to: verifiedMarkerURL, options: .atomic)
    }

    func downloadedByteCount() -> Int64 {
        byteCount(in: modelDirectory)
    }

    func installedByteCount() -> Int64 {
        let compiledBytes = installationMarker?.compiledCacheDirectories.reduce(Int64(0)) { total, name in
            guard Self.isSafeCompiledCacheName(name) else { return total }
            return total + byteCount(in: compiledCacheRoot.appendingPathComponent(name, isDirectory: true))
        } ?? 0
        return byteCount(in: modelDirectory) + compiledBytes
    }

    func removeModel() throws {
        let fileManager = FileManager.default
        let compiledDirectories = Set(installationMarker?.compiledCacheDirectories ?? [])
        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.removeItem(at: modelDirectory)
        }
        try removeCompiledCacheDirectories(compiledDirectories)
    }

    func removeCompiledCacheDirectories(_ names: Set<String>) throws {
        let fileManager = FileManager.default
        for name in names where Self.isSafeCompiledCacheName(name) {
            let url = compiledCacheRoot.appendingPathComponent(name, isDirectory: true)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    func compiledCacheDirectoryNames() -> Set<String> {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: compiledCacheRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return Set(urls.compactMap { url in
            guard Self.isSafeCompiledCacheName(url.lastPathComponent),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return url.lastPathComponent
        })
    }

    private var installationMarker: LocalParakeetInstallationMarker? {
        guard let data = try? Data(contentsOf: verifiedMarkerURL) else { return nil }
        if let marker = try? JSONDecoder().decode(LocalParakeetInstallationMarker.self, from: data),
           marker.version == 2 {
            return marker
        }
        guard String(data: data, encoding: .utf8) == Self.legacyMarkerContents else { return nil }
        return LocalParakeetInstallationMarker(
            version: 1,
            compiledCacheDirectories: legacyCompiledCacheDirectoryNames().sorted()
        )
    }

    func legacyCompiledCacheDirectoryNames() -> Set<String> {
        let relativePackages = Set(assets.compactMap { asset -> String? in
            let components = asset.relativePath.split(separator: "/")
            guard let index = components.firstIndex(where: { $0.hasSuffix(".mlpackage") }) else {
                return nil
            }
            return components[...index].joined(separator: "/")
        })
        return Set(relativePackages.compactMap { relativePath in
            Self.compiledCacheName(
                for: modelDirectory.appendingPathComponent(relativePath, isDirectory: true)
            )
        })
    }

    // Mirrors the pinned helper's content-addressed ModelCache key so legacy
    // FreeFlow markers can claim only caches compiled from their own packages.
    private static func compiledCacheName(for source: URL) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        var hasher = SHA256()
        hasher.update(data: Data(source.resolvingSymlinksInPath().path.utf8))
        if let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                ) else { continue }
                hasher.update(data: Data(url.lastPathComponent.utf8))
                if let size = values.fileSize {
                    Swift.withUnsafeBytes(of: Int64(size)) { hasher.update(data: Data($0)) }
                }
                if let modified = values.contentModificationDate {
                    Swift.withUnsafeBytes(of: modified.timeIntervalSince1970) {
                        hasher.update(data: Data($0))
                    }
                }
            }
        }
        return hasher.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func isSafeCompiledCacheName(_ name: String) -> Bool {
        name.count == 24 && name.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private func byteCount(in directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct LocalParakeetInstallationMarker: Codable {
    let version: Int
    let compiledCacheDirectories: [String]
}

enum LocalParakeetModelState: Equatable {
    case unavailable(String)
    case notInstalled
    case downloading(Double)
    case verifying
    case preparing
    case ready(Int64)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .preparing: return true
        default: return false
        }
    }
}

final class LocalParakeetModelManager: ObservableObject {
    @Published private(set) var state: LocalParakeetModelState

    let store: LocalParakeetModelStore
    private let executableURL: URL?
    private let platformSupported: Bool

    init(
        store: LocalParakeetModelStore = LocalParakeetModelStore(),
        executableURL: URL? = LocalParakeetModelManager.bundledExecutableURL(),
        platformSupported: Bool = LocalParakeetModelManager.isPlatformSupported
    ) {
        self.store = store
        self.executableURL = executableURL
        self.platformSupported = platformSupported
        if !platformSupported {
            self.state = .unavailable("Requires Apple silicon and macOS 15 or newer.")
        } else if executableURL == nil {
            self.state = .unavailable("This build does not include the local transcription engine.")
        } else if store.isInstalled {
            self.state = .ready(store.installedByteCount())
        } else {
            self.state = .notInstalled
        }
    }

    static var isPlatformSupported: Bool {
#if arch(arm64)
        if #available(macOS 15.0, *) { return true }
#endif
        return false
    }

    static func bundledExecutableURL() -> URL? {
        guard let mainExecutable = Bundle.main.executableURL else { return nil }
        let url = mainExecutable.deletingLastPathComponent()
            .appendingPathComponent("freeflow-local-asr", isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    @MainActor
    func refresh() {
        guard platformSupported, executableURL != nil else { return }
        guard !state.isBusy else { return }
        state = store.isInstalled ? .ready(store.installedByteCount()) : .notInstalled
    }

    @MainActor
    func install() async -> Bool {
        guard platformSupported, let executableURL else { return false }
        guard !state.isBusy else { return false }
        if store.isInstalled {
            state = .ready(store.installedByteCount())
            return true
        }

        do {
            state = .downloading(downloadProgress)
            try await run(
                executableURL: executableURL,
                arguments: ["download"],
                monitorsDownload: true
            )
            state = .downloading(1)
            state = .verifying
            let store = store
            try await Task.detached(priority: .userInitiated) {
                try store.validateDownloadedModel()
            }.value
            state = .preparing
            let compiledCacheDirectoriesBeforePreparation = store.compiledCacheDirectoryNames()
            let transcriptionService = try LocalParakeetTranscriptionService(
                modelDirectory: store.modelDirectory,
                executableURL: executableURL
            )
            do {
                try await transcriptionService.prewarm()
            } catch {
                try? store.removeCompiledCacheDirectories(
                    store.compiledCacheDirectoryNames()
                        .subtracting(compiledCacheDirectoriesBeforePreparation)
                )
                throw error
            }
            let preparedDirectories = store.compiledCacheDirectoryNames()
                .subtracting(compiledCacheDirectoriesBeforePreparation)
            do {
                try store.markInstalled(compiledCacheDirectories: preparedDirectories)
            } catch {
                try? store.removeCompiledCacheDirectories(preparedDirectories)
                throw error
            }
            state = .ready(store.installedByteCount())
            return true
        } catch is CancellationError {
            state = .failed("Model download was cancelled.")
        } catch {
            state = .failed(error.localizedDescription)
        }
        return false
    }

    @MainActor
    func removeModel() {
        guard !state.isBusy else { return }
        do {
            try store.removeModel()
            state = .notInstalled
        } catch {
            state = .failed("Could not remove the local model: \(error.localizedDescription)")
        }
    }

    private var downloadProgress: Double {
        min(1, Double(store.downloadedByteCount()) / Double(LocalParakeetModelStore.downloadByteCount))
    }

    @MainActor
    private func run(executableURL: URL, arguments: [String], monitorsDownload: Bool) async throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        do {
            while process.isRunning {
                try await Task.sleep(nanoseconds: 200_000_000)
                if monitorsDownload {
                    state = .downloading(downloadProgress)
                }
            }
        } catch {
            if process.isRunning { process.terminate() }
            throw error
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw LocalParakeetModelError.helperFailed(process.terminationStatus)
        }
    }
}

enum LocalParakeetModelError: LocalizedError {
    case helperFailed(Int32)
    case integrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .helperFailed(let status):
            return "Local model setup failed (engine exit \(status))."
        case .integrityCheckFailed:
            return "The downloaded model failed its integrity check. Remove it and try again."
        }
    }
}
