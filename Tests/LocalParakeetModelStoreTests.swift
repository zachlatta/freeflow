import Foundation

enum LocalParakeetModelStoreTests {
    static func run() {
        validatesMarksAndRemovesOnlyTheModelCache()
        legacyMarkerRemovesOnlyMatchingCompiledCache()
        rejectsModifiedModelAssets()
    }

    private static func validatesMarksAndRemovesOnlyTheModelCache() {
        withStore { store, assetURL in
            try Data("hello".utf8).write(to: assetURL)
            try store.validateDownloadedModel()
            let compiledRoot = store.cacheRoot.appendingPathComponent("mlmodelc", isDirectory: true)
            let ownedName = "0123456789abcdef01234567"
            let unrelatedName = "89abcdef0123456701234567"
            let owned = compiledRoot.appendingPathComponent(ownedName, isDirectory: true)
            let unrelatedCompiled = compiledRoot.appendingPathComponent(unrelatedName, isDirectory: true)
            try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: unrelatedCompiled, withIntermediateDirectories: true)
            try Data("mine".utf8).write(to: owned.appendingPathComponent("model.bin"))
            try Data("other".utf8).write(to: unrelatedCompiled.appendingPathComponent("model.bin"))
            try store.markInstalled(compiledCacheDirectories: [ownedName])
            TestSupport.expect(store.isInstalled, "Verified local model was not reported as installed")
            TestSupport.expectEqual(store.installedByteCount(), 9)

            let unrelated = store.cacheRoot.appendingPathComponent("keep-me.txt")
            try Data("safe".utf8).write(to: unrelated)
            try store.removeModel()
            TestSupport.expect(!store.isInstalled, "Removed local model remains installed")
            TestSupport.expect(
                FileManager.default.fileExists(atPath: unrelated.path),
                "Removing the model deleted an unrelated cache file"
            )
            TestSupport.expect(
                !FileManager.default.fileExists(atPath: owned.path),
                "Removing the model left its recorded compiled cache"
            )
            TestSupport.expect(
                FileManager.default.fileExists(atPath: unrelatedCompiled.path),
                "Removing the model deleted an unrelated compiled cache"
            )
        }
    }

    private static func rejectsModifiedModelAssets() {
        withStore { store, assetURL in
            try Data("HELLO".utf8).write(to: assetURL)
            do {
                try store.validateDownloadedModel()
                TestSupport.expect(false, "Modified model asset passed its SHA-256 check")
            } catch LocalParakeetModelError.integrityCheckFailed {
                TestSupport.expect(true, "Modified model asset correctly rejected")
            }
        }
    }

    private static func legacyMarkerRemovesOnlyMatchingCompiledCache() {
        withStore(relativePath: "encoder.mlpackage/Data/model.bin") { store, assetURL in
            try Data("hello".utf8).write(to: assetURL)
            let names = store.legacyCompiledCacheDirectoryNames()
            TestSupport.expectEqual(names.count, 1)
            guard let ownedName = names.first else { return }
            let compiledRoot = store.cacheRoot.appendingPathComponent("mlmodelc", isDirectory: true)
            let owned = compiledRoot.appendingPathComponent(ownedName, isDirectory: true)
            let unrelated = compiledRoot.appendingPathComponent(
                "89abcdef0123456701234567",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
            try Data(LocalParakeetModelStore.legacyMarkerContents.utf8).write(
                to: store.modelDirectory.appendingPathComponent(".freeflow-verified")
            )

            try store.removeModel()
            TestSupport.expect(
                !FileManager.default.fileExists(atPath: owned.path),
                "Legacy removal left the matching compiled cache"
            )
            TestSupport.expect(
                FileManager.default.fileExists(atPath: unrelated.path),
                "Legacy removal deleted an unrelated compiled cache"
            )
        }
    }

    private static func withStore(
        relativePath: String = "test/asset.bin",
        _ body: (LocalParakeetModelStore, URL) throws -> Void
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freeflow-local-model-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = LocalParakeetModelAsset(
            relativePath: relativePath,
            byteCount: 5,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        let store = LocalParakeetModelStore(cacheRoot: root, assets: [asset])
        let assetURL = store.modelDirectory.appendingPathComponent(asset.relativePath)
        do {
            try FileManager.default.createDirectory(
                at: assetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try body(store, assetURL)
        } catch {
            fatalError("Local model store test failed: \(error)")
        }
    }
}
