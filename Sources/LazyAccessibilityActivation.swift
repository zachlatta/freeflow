import AppKit
import ApplicationServices
import Foundation

/// Chromium and Electron build their accessibility trees only after a client opts in. Until then,
/// AXSelectedText reads fail and Edit Mode falls back to dictation (issue #237).
enum LazyAccessibilityActivationCore {
    static let electronAttribute = "AXManualAccessibility"
    static let chromiumBrowserAttribute = "AXEnhancedUserInterface"

    /// AXEnhancedUserInterface can disturb window managers, so it is limited to these browsers.
    /// Each entry also matches its channel variants, such as `com.google.Chrome.canary`.
    static let chromiumBrowserBundleIdentifiers = [
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera"
    ]

    static func isChromiumBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return chromiumBrowserBundleIdentifiers.contains { known in
            bundleIdentifier == known || bundleIdentifier.hasPrefix(known + ".")
        }
    }

    /// Returns the opt-in attributes to set, in order. `isElectronApp` is consulted only when needed.
    static func attributes(bundleIdentifier: String?, isElectronApp: () -> Bool) -> [String] {
        if isChromiumBrowser(bundleIdentifier: bundleIdentifier) {
            return [electronAttribute, chromiumBrowserAttribute]
        }
        return isElectronApp() ? [electronAttribute] : []
    }

    /// Sets each attribute independently so one failure cannot skip the other. Nothing is cached:
    /// re-applying on each activation is idempotent and avoids trusting a reused process ID.
    @discardableResult
    static func activate(
        bundleIdentifier: String?,
        isElectronApp: () -> Bool,
        setTrue: (String) -> Bool
    ) -> [(attribute: String, succeeded: Bool)] {
        attributes(bundleIdentifier: bundleIdentifier, isElectronApp: isElectronApp).map {
            ($0, setTrue($0))
        }
    }

    static func isElectronBundle(at bundleURL: URL?, fileExists: (String) -> Bool) -> Bool {
        guard let bundleURL else { return false }
        let framework = bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework", isDirectory: true)
        return fileExists(framework.path)
    }
}

enum LazyAccessibilityActivation {
    /// Writes only boolean opt-in flags; reads no content. Call off the main thread.
    static func activate(processIdentifier: pid_t, bundleIdentifier: String?, bundleURL: URL?) {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        LazyAccessibilityActivationCore.activate(
            bundleIdentifier: bundleIdentifier,
            isElectronApp: {
                LazyAccessibilityActivationCore.isElectronBundle(at: bundleURL) {
                    FileManager.default.fileExists(atPath: $0)
                }
            },
            setTrue: { attribute in
                AXUIElementSetAttributeValue(appElement, attribute as CFString, kCFBooleanTrue) == .success
            }
        )
    }
}
