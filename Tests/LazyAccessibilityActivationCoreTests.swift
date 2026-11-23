import Foundation

enum LazyAccessibilityActivationCoreTests {
    static func run() {
        testChromiumBrowserMatching()
        testChromiumBrowserGetsBothAttributesInOrder()
        testElectronAppGetsOnlyManualAccessibility()
        testNativeAppIsNeverWritten()
        testFailedWriteDoesNotSkipLaterAttribute()
        testActivationIsReappliedEachTime()
        testElectronBundleDetection()
    }

    private static let core = LazyAccessibilityActivationCore.self

    private static func testChromiumBrowserMatching() {
        for bundleIdentifier in [
            "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac.Beta",
            "com.brave.Browser", "company.thebrowser.Browser", "org.chromium.Chromium"
        ] {
            TestSupport.expect(core.isChromiumBrowser(bundleIdentifier: bundleIdentifier),
                               "Known Chromium browsers and their channels should be recognized")
        }
        for bundleIdentifier in [
            nil, "", "com.google.ChromeRemoteDesktop", "com.apple.Safari",
            "com.microsoft.VSCode", "com.example.chrome", "org.mozilla.firefox"
        ] as [String?] {
            TestSupport.expect(!core.isChromiumBrowser(bundleIdentifier: bundleIdentifier),
                               "Window-manager-sensitive flag must stay limited to known browsers")
        }
    }

    private static func testChromiumBrowserGetsBothAttributesInOrder() {
        var electronChecks = 0
        var writes: [String] = []
        let result = core.activate(
            bundleIdentifier: "com.google.Chrome",
            isElectronApp: { electronChecks += 1; return false },
            setTrue: { writes.append($0); return true }
        )
        TestSupport.expectEqual(writes, ["AXManualAccessibility", "AXEnhancedUserInterface"])
        TestSupport.expectEqual(result.map(\.succeeded), [true, true])
        TestSupport.expectEqual(electronChecks, 0)
    }

    private static func testElectronAppGetsOnlyManualAccessibility() {
        var writes: [String] = []
        core.activate(
            bundleIdentifier: "com.example.synthetic-editor",
            isElectronApp: { true },
            setTrue: { writes.append($0); return true }
        )
        TestSupport.expectEqual(writes, ["AXManualAccessibility"])
    }

    private static func testNativeAppIsNeverWritten() {
        for bundleIdentifier in ["com.apple.TextEdit", nil] as [String?] {
            var writes: [String] = []
            let result = core.activate(
                bundleIdentifier: bundleIdentifier,
                isElectronApp: { false },
                setTrue: { writes.append($0); return true }
            )
            TestSupport.expect(writes.isEmpty && result.isEmpty,
                               "Native apps must not receive Chromium/Electron opt-in attributes")
        }
    }

    private static func testFailedWriteDoesNotSkipLaterAttribute() {
        var writes: [String] = []
        let result = core.activate(
            bundleIdentifier: "com.brave.Browser",
            isElectronApp: { false },
            setTrue: { attribute in
                writes.append(attribute)
                return attribute != "AXManualAccessibility"
            }
        )
        TestSupport.expectEqual(writes, ["AXManualAccessibility", "AXEnhancedUserInterface"])
        TestSupport.expectEqual(result.map(\.succeeded), [false, true])
    }

    private static func testActivationIsReappliedEachTime() {
        // A reused process ID or a tree the browser later disabled must not be skipped by a cache.
        var writes = 0
        for _ in 0..<3 {
            core.activate(
                bundleIdentifier: "com.google.Chrome",
                isElectronApp: { false },
                setTrue: { _ in writes += 1; return true }
            )
        }
        TestSupport.expectEqual(writes, 6)
    }

    private static func testElectronBundleDetection() {
        let bundle = URL(fileURLWithPath: "/Applications/Synthetic Editor.app", isDirectory: true)
        var checkedPaths: [String] = []
        let detected = core.isElectronBundle(at: bundle) { path in
            checkedPaths.append(path)
            return true
        }
        TestSupport.expect(detected, "Bundles containing the Electron framework should be detected")
        TestSupport.expectEqual(
            checkedPaths,
            ["/Applications/Synthetic Editor.app/Contents/Frameworks/Electron Framework.framework"]
        )
        TestSupport.expect(!core.isElectronBundle(at: bundle) { _ in false },
                           "Bundles without the framework are not Electron")
        TestSupport.expect(!core.isElectronBundle(at: nil) { _ in true },
                           "Processes without a bundle are not Electron")
    }
}
