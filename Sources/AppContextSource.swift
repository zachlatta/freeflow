import Foundation
import AppKit
import ApplicationServices

/// Model for the "App Context" feature: the three UserDefaults settings (mode, screenshot scope,
/// allowlist), the effective-source decision, the "App summary" line, and the browser-URL AX reads.
/// All static / value-typed so it can be read from any thread (leaves read UserDefaults; the UI writes
/// via `@AppStorage`). Defaults reproduce upstream (Screenshot + all apps), so a fresh install is unchanged.
enum AppContextSource {

    // MARK: - UserDefaults keys

    /// Context source mode: `"off" | "metadata" | "screenshot"`.
    static let modeKey = "appContextMode"
    /// Per-app screenshot scope: `"all" | "specific"`.
    static let scopeKey = "appContextScreenshotScope"
    /// Screenshot allowlist: an array of bundle identifiers.
    static let appsKey = "appContextScreenshotApps"

    // MARK: - Settings enums

    /// The chosen context source. `screenshot` is the upstream default.
    enum Mode: String, CaseIterable {
        /// No context is sent.
        case off
        /// A one-line on-device text summary; no image, no vision model.
        case metadata
        /// Capture the window and ask the vision model (upstream behavior).
        case screenshot
    }

    /// Whether Screenshot mode applies to every app or only an allowlisted subset.
    enum Scope: String, CaseIterable {
        /// Every app takes a screenshot.
        case all
        /// Only allowlisted apps; the rest fall back to `metadata`.
        case specific
    }

    /// The resolved source for one `collectContext()` call.
    enum EffectiveSource {
        /// Capture + vision model.
        case screenshot
        /// One-line metadata summary; no image, no LLM.
        case metadata
        /// No context.
        case off
    }

    // MARK: - Settings reads (default = upstream behavior)

    /// Current mode; defaults to `.screenshot`.
    static var currentMode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .screenshot
    }

    /// Current scope; defaults to `.all`.
    static var currentScope: Scope {
        Scope(rawValue: UserDefaults.standard.string(forKey: scopeKey) ?? "") ?? .all
    }

    /// Current allowlist (bundle ids); empty by default. `UserDefaults` stores `[String]` natively.
    static var allowlist: [String] {
        UserDefaults.standard.array(forKey: appsKey) as? [String] ?? []
    }

    // MARK: - Effective source

    /// Resolves the source for one call from the frontmost app's bundle id.
    /// In Screenshot+specific, apps outside the allowlist (or a `nil` id) fall back to `.metadata`.
    static func effectiveSource(forBundleID id: String?) -> EffectiveSource {
        switch currentMode {
        case .off:
            return .off
        case .metadata:
            return .metadata
        case .screenshot:
            if currentScope == .all { return .screenshot }
            if let id, allowlist.contains(id) { return .screenshot }
            return .metadata
        }
    }

    // MARK: - Deterministic metadata summary (App summary mode)

    /// Builds the "App summary" one-line activity string (offline, no LLM, pure — testable without AX).
    /// Forms: `on <host> in <app>` (collapsed to `in <app>` when the host matches the app name),
    /// `in the <app> address bar`, `on "<title>" in <app>` (web app with no readable URL), else `in <app>`.
    /// - Parameters:
    ///   - appName: Frontmost app's localized name.
    ///   - pageTitle: Focused window/page title (cleaned here).
    ///   - webHost: Current page host (e.g. `github.com`), or `nil`.
    ///   - isWebApp: Whether the app renders web content.
    ///   - addressBarFocused: Whether the address/search bar is focused.
    static func metadataSummary(
        appName: String?,
        pageTitle: String?,
        webHost: String?,
        isWebApp: Bool,
        addressBarFocused: Bool
    ) -> String {
        let app = (appName?.isEmpty == false) ? appName! : "the active app"
        let title = cleanedPageTitle(pageTitle, appName: appName, host: webHost)

        // Address bar focused → you're typing a URL/search, not into the page; check before the host.
        if addressBarFocused {
            return "User is dictating in the \(app) address bar"
        }

        if let webHost, !webHost.isEmpty {
            // Drop "in <app>" when the host already names the app (e.g. the ChatGPT web app).
            let base = hostMatchesApp(webHost, appName: appName)
                ? "User is dictating in \(app)"
                : "User is dictating on \(webHost) in \(app)"
            if let title { return "\(base) (\"\(title)\")" }
            return base
        }

        // Web app whose URL the browser doesn't expose (e.g. Firefox/Zen) — use the page title.
        if isWebApp, let title {
            return "User is dictating on \"\(title)\" in \(app)"
        }

        return "User is dictating in \(app)"
    }

    // MARK: - Metadata summary helpers (pure)

    /// Lowercased letters/digits only, for loose name-vs-host comparison.
    private static func normalizedToken(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    /// The host's brand label (the second-to-last DNS label: `github.com`→`github`).
    /// Note: not public-suffix aware, so multi-part TLDs are approximate (`bbc.co.uk`→`co`); only used
    /// for the optional cosmetic collapse below, so a miss just keeps the full `on <host>` form.
    private static func hostBrand(_ host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return host }
        return labels[labels.count - 2]
    }

    /// True when the host's brand equals the app name (a web app named after its site, e.g. ChatGPT).
    /// Exact match, so a real browser ("Google Chrome" on google.com) is not collapsed.
    private static func hostMatchesApp(_ host: String, appName: String?) -> Bool {
        guard let appName, !appName.isEmpty else { return false }
        return normalizedToken(hostBrand(host)) == normalizedToken(appName)
    }

    /// Cleans the page title: strips a trailing " — <app>" suffix browsers add, removes embedded quotes,
    /// and returns `nil` if it's empty or just repeats the app name or host.
    private static func cleanedPageTitle(_ pageTitle: String?, appName: String?, host: String?) -> String? {
        guard var title = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }

        // Strip the trailing " — <BrowserName>" / " - <BrowserName>" browsers append.
        if let appName, !appName.isEmpty {
            for separator in [" — ", " – ", " - "] {
                let suffix = separator + appName
                if title.count > suffix.count, title.lowercased().hasSuffix(suffix.lowercased()) {
                    title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        // Remove embedded double quotes so the quoted summary stays balanced.
        title = title.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else { return nil }
        if let appName, normalizedToken(title) == normalizedToken(appName) { return nil }
        if let host, normalizedToken(title) == normalizedToken(host) { return nil }
        return title
    }

    // MARK: - Browser URL & focus (Accessibility)
    //
    // Reads the frontmost app's page host and focus via AX. Detection is structural (finds an AXWebArea,
    // no browser allowlist), so it covers Safari, Chromium browsers (Chrome, Edge, Brave, Arc, Opera,
    // Vivaldi, newer ones), PWAs, and Gecko (Firefox/Zen) where AX is exposed. Requires the Accessibility
    // permission the app already uses.

    /// Max AX nodes visited when searching for the web area — bounds cost on large non-web trees.
    private static let traversalBudget = 250
    /// Max parent hops when checking if the focused element is inside the web content.
    private static let maxParentHops = 12

    /// Reads one dictation's web context: page host (if readable), whether the app renders web content,
    /// and whether the address/search bar is focused. Reads `frontmostApplication` here (the caller can't
    /// pass the element down without editing the byte-identical `collectContext`), but bails when the
    /// frontmost app no longer matches `expectedBundleID`, so it never mixes another app's page into a
    /// summary captured for a different app.
    static func webContext(expectedBundleID: String?) -> (host: String?, isWebApp: Bool, addressBarFocused: Bool) {
        guard AXIsProcessTrusted() else { return (nil, false, false) }
        guard let app = NSWorkspace.shared.frontmostApplication else { return (nil, false, false) }
        // Focus changed since collectContext captured the app → don't read a different app's page.
        if let expectedBundleID, app.bundleIdentifier != expectedBundleID { return (nil, false, false) }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Opt Chromium/Electron apps into exposing their AX tree (harmless for apps that already do).
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        // Safari exposes the page URL on the focused window's AXDocument.
        var urlString = copyElement(appElement, "AXFocusedWindow").flatMap { copyURLString($0, "AXDocument") }

        // Find the web area once; reused for the Chromium/PWA URL and the web-capable flag.
        let webArea = findWebArea(appElement)
        if urlString == nil, let webArea {
            urlString = copyURLString(webArea, "AXURL")
        }

        let host = hostFromURLString(urlString)
        let isWebApp = (webArea != nil) || (host != nil)
        let addressBarFocused = isWebApp && focusedIsChromeTextField(appElement)
        return (host, isWebApp, addressBarFocused)
    }

    /// Clean host from a URL string: http(s) only, lowercased, leading `www.` stripped; else `nil`.
    /// (IDN hosts come back as punycode `xn--…` — left as-is; rare for these users.)
    private static func hostFromURLString(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host?.lowercased(), !host.isEmpty
        else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }

    /// True when the focused element is the address/search bar: a text-input role that is browser chrome
    /// (not inside the web page).
    private static func focusedIsChromeTextField(_ appElement: AXUIElement) -> Bool {
        guard let focused = copyElement(appElement, "AXFocusedUIElement"),
              let role = copyString(focused, "AXRole") else { return false }
        let textInputRoles: Set<String> = ["AXTextField", "AXComboBox", "AXSearchField"]
        guard textInputRoles.contains(role) else { return false }
        return !isInsideWebArea(focused)
    }

    /// Walks up the parent chain (capped) to see if the element sits inside an `AXWebArea`.
    private static func isInsideWebArea(_ element: AXUIElement) -> Bool {
        var current = element
        var hops = 0
        while hops < maxParentHops {
            guard let parent = copyElement(current, "AXParent") else { return false }
            if copyString(parent, "AXRole") == "AXWebArea" { return true }
            current = parent
            hops += 1
        }
        return false
    }

    /// Breadth-first search for the first `AXWebArea`, bounded by `traversalBudget` visited nodes.
    /// BFS reaches the shallow web area before a wide toolbar subtree can exhaust the budget.
    private static func findWebArea(_ root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var head = 0
        var visited = 0
        while head < queue.count, visited < traversalBudget {
            let element = queue[head]
            head += 1
            visited += 1
            if copyString(element, "AXRole") == "AXWebArea" { return element }
            if let children = copyChildren(element) { queue.append(contentsOf: children) }
        }
        return nil
    }

    // MARK: - AX attribute helpers

    /// Copies an element-typed AX attribute (e.g. the focused window).
    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Copies a string-typed AX attribute.
    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Copies a URL- or string-typed AX attribute as a URL string (value may be a CFURL or a String).
    private static func copyURLString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        if CFGetTypeID(value) == CFURLGetTypeID() { return ((value as! CFURL) as URL).absoluteString }
        return value as? String
    }

    /// Copies the element's AX children (`as?` bridges the CFArray and yields nil on any non-array).
    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        return children
    }
}
