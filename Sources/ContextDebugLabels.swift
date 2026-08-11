import Foundation

/// Plain-English labels for the "Smart Paste" debug panel.
///
/// This is the single place that turns raw internal values (app kind, extraction
/// method, whether text was found) into friendly text. The live debug panel and
/// the saved-history view both read from here, so their wording stays in sync.
/// Every string is written for a normal reader — no internal jargon.
enum ContextDebugLabels {

    // MARK: - App / read labels

    /// What kind of app the cursor was in.
    /// `appKind` is the stored raw value: "native", "webView", or "unknown".
    static func appType(_ appKind: String?) -> String {
        switch appKind {
        case "native":  return "Standard Mac app"
        case "webView": return "Web-based app (Electron, browser, etc.)"
        default:        return "Couldn't identify the app type"
        }
    }

    /// How the text around the cursor was obtained.
    /// `method` is the stored raw extraction method.
    static func howTextWasRead(_ method: String?) -> String {
        switch method {
        case "axAPI":           return "Read directly from the text field"
        case "axWebTextMarker": return "Read precisely from the web view"
        case "axWebAreaBFS":    return "Read from inside the web view"
        case "unknown", nil:    return "Couldn't read the surrounding text"
        // Any other stored raw value (e.g. from an older build's history) renders as-is.
        default:                return method ?? "Unknown"
        }
    }

    /// Whether any usable text was found around the cursor.
    /// - Parameters:
    ///   - hasText: at least one side of the cursor had real (non-empty) text.
    ///   - readFailed: the accessibility read returned nothing at all (a "blind" app).
    static func surroundingText(hasText: Bool, readFailed: Bool) -> String {
        if hasText { return "Found" }
        return readFailed ? "Not available (couldn't read this app)" : "Empty field"
    }

    // MARK: - Formatter rule summary

    /// Turns the formatter's internal rule string (e.g. "no-punct | cap:↓ | sp:L")
    /// into a plain-English summary of what Smart Paste did.
    /// The raw rule string stays in the logs for debugging.
    static func ruleSummary(_ rule: String?) -> String {
        guard let rule, !rule.isEmpty,
              !["N/A", "nil", "empty-input"].contains(rule) else {
            return "No changes"
        }
        var parts: [String] = []
        for token in rule.split(separator: "|").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch token {
            case "cap:↑": parts.append("capitalized the first letter")
            case "cap:↓": parts.append("made the first letter lowercase")
            case "sp:L":  parts.append("added a space before")
            case "sp:T":  parts.append("added a space after")
            case "sp:LT": parts.append("added spaces on both sides")
            case "+repl": parts.append("replaced the selected text")
            case "+vocab": parts.append("restored a custom-word spelling")
            case "no-punct", "cap:–", "cap:blind", "sp:0":
                break  // no user-visible change
            default:
                if token.hasPrefix("punct:") { parts.append("removed an extra punctuation mark") }
            }
        }
        guard !parts.isEmpty else { return "No changes" }
        let sentence = parts.joined(separator: ", ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}
