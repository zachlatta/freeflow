import Foundation
import ApplicationServices
import AppKit
import OSLog
import Darwin   // dlsym, for resolving private AXTextMarker C functions at runtime

private let axLog = Logger(subsystem: "com.zachlatta.freeflow", category: "AccessibilityText")

// MARK: - SurroundingTextSnapshot

/// Text context captured around the cursor from the focused text field.
/// All fields are optional; nil means the app does not expose accessible text.
struct SurroundingTextSnapshot: Sendable {
    /// Up to N characters before the cursor (or selection start).
    let precedingText: String?
    /// Up to N characters after the selection end (never includes selected text).
    let followingText: String?
    /// Semantic position of the cursor within the field.
    let cursorPosition: CursorPosition
    /// Which extraction technique successfully read the surrounding text.
    let extractionMethod: ExtractionMethod
    /// What kind of app the text came from. Diagnostics/UX only — never drives logic.
    var appKind: AppKind = .unknown

    /// Semantic position of the cursor within the focused field.
    enum CursorPosition: String {
        case start    // index 0
        case middle   // somewhere in the body
        case end      // at or past the last character
        case empty    // field has no text
        case unknown  // AX API did not expose position info
    }

    /// Which Accessibility technique successfully read the surrounding text.
    enum ExtractionMethod: String {
        case axAPI               // Native kAXValueAttribute worked
        case axWebTextMarker     // WebKit/Chromium TextMarker parameterized attributes
        case axWebAreaBFS        // BFS located the focused element inside an AXWebArea
        case keyboardSimulation  // Cmd+Shift+Up/Down clipboard-selection fallback used
        case unknown             // No technique could get context
    }

    /// The kind of application hosting the focused text field.
    /// Used only for human-readable diagnostics — it never changes how text is read.
    enum AppKind: String {
        case native   // A standard Mac app (its text fields speak the native accessibility API)
        case webView  // An Electron / Chromium / Safari-style app (text lives inside a web page)
        case unknown  // We could not tell (there was no focused field to inspect)
    }

    /// True when at least one side of the cursor is readable.
    var hasContext: Bool { precedingText != nil || followingText != nil }

    /// Returns a copy of this snapshot tagged with the given app kind.
    func withAppKind(_ kind: AppKind) -> SurroundingTextSnapshot {
        var copy = self
        copy.appKind = kind
        return copy
    }
}

// MARK: - AccessibilityTextReader

/// Reads text surrounding the cursor via the macOS Accessibility API.
///
/// Covers:
/// - Native AppKit controls (NSTextView, NSTextField, etc.)
/// - Electron / Chromium web views (e.g. editor and chat apps)
/// - Browser text fields (Safari, Chrome, Firefox)
/// - Qt and Java/Swing apps via their respective AX bridges
/// - Terminal emulators — limited, field-level only
///
/// Falls back gracefully: returns nil values for unsupported apps.
enum AccessibilityTextReader {

    /// Per-message AX IPC timeout (seconds). Bounds each cross-process Accessibility request so a
    /// CPU-starved target app degrades to a fallback instead of blocking for the ~6s system default.
    private static let axMessagingTimeoutSeconds: Float = 2.0

    // MARK: Public API

    /// Synchronous read — works for native AppKit controls that expose kAXValueAttribute.
    /// For Electron/web views (where AX may not be awake), this returns nil for surrounding text;
    /// the async collectContext() path handles those via BFS and keyboard fallback.
    static func readSurroundingText(
        from appElement: AXUIElement,
        maxBefore: Int = 300,
        maxAfter: Int = 400
    ) -> SurroundingTextSnapshot {
        // Cap per-message AX IPC so a CPU-starved target app can't block this read for the
        // ~6s system default; a slow app then degrades to a fallback instead of stalling.
        _ = AXUIElementSetMessagingTimeout(appElement, axMessagingTimeoutSeconds)
        guard let focused = focusedElement(in: appElement) else {
            axLog.info("readSurroundingText(sync): no focused element found")
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: .unknown)
        }

        // Probe app kind once; we have a focused element to inspect from here on.
        let kind = detectAppKind(of: focused)

        // Genuine web form controls (<textarea>/<input>) expose an honest, self-scoped
        // kAXValue + caret — read them natively FIRST so a TextMarker read can't capture
        // surrounding page text as context (see nativeReadForWebFormControl).
        if kind == .webView,
           let nativeSnap = nativeReadForWebFormControl(focused, maxBefore: maxBefore, maxAfter: maxAfter) {
            axLog.info("readSurroundingText(sync): done via native form-control read — prec=\(nativeSnap.precedingText?.count ?? 0)ch foll=\(nativeSnap.followingText?.count ?? 0)ch")
            return nativeSnap.withAppKind(.webView)
        }

        // Web/Electron: prefer TextMarkers — immune to the fraudulent (0,0) cursor that
        // kAXSelectedTextRange returns in Chromium. Falls through to the native path on nil.
        if kind == .webView,
           let markerSnap = extractViaTextMarkers(focused, maxBefore: maxBefore, maxAfter: maxAfter),
           markerSnap.hasContext {
            axLog.info("readSurroundingText(sync): done via TextMarkers — prec=\(markerSnap.precedingText?.count ?? 0)ch foll=\(markerSnap.followingText?.count ?? 0)ch")
            return markerSnap.withAppKind(.webView)
        }

        // Read full text — may fail in Electron where the AX tree is not yet awake.
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success,
              let fullText = valueRef as? String else {
            axLog.info("readSurroundingText(sync): kAXValueAttribute unavailable — async read required")
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: .unknown, appKind: kind)
        }

        guard !fullText.isEmpty else {
            return .init(precedingText: "", followingText: "", cursorPosition: .empty, extractionMethod: .axAPI, appKind: kind)
        }

        let nsText = fullText as NSString
        let totalLength = nsText.length

        // Read cursor range — synchronous, no keyboard simulation possible here.
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef,
              CFGetTypeID(rangeVal) == AXValueGetTypeID() else {
            axLog.info("readSurroundingText(sync): no range info — returning tail as preceding")
            let tail = nsText.substring(from: max(0, totalLength - maxBefore))
            return .init(precedingText: tail, followingText: "", cursorPosition: .unknown, extractionMethod: .axAPI, appKind: kind)
        }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(unsafeBitCast(rangeVal, to: AXValue.self), .cfRange, &cfRange) else {
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: .unknown, appKind: kind)
        }

        let selStart = min(max(cfRange.location, 0), totalLength)
        let selEnd   = min(selStart + max(cfRange.length, 0), totalLength)

        let beforeStart    = max(0, selStart - maxBefore)
        let precedingSlice = nsText.substring(with: NSRange(location: beforeStart, length: selStart - beforeStart))
        let afterLength    = min(maxAfter, totalLength - selEnd)
        let followingSlice = afterLength > 0
            ? nsText.substring(with: NSRange(location: selEnd, length: afterLength))
            : ""

        let position: SurroundingTextSnapshot.CursorPosition
        if selStart == 0               { position = .start }
        else if selStart >= totalLength { position = .end }
        else                           { position = .middle }

        axLog.info("readSurroundingText(sync): prec=\(selStart - beforeStart)ch foll=\(afterLength)ch pos=\(position.rawValue, privacy: .public) kind=\(kind.rawValue, privacy: .public)")
        return .init(precedingText: precedingSlice, followingText: followingSlice, cursorPosition: position, extractionMethod: .axAPI, appKind: kind)
    }

    /// Async read that auto-syncs the AX tree for Electron/web views before reading.
    /// Always prefer this variant inside async contexts (e.g., collectContext).
    static func readSurroundingTextWithSync(
        from appElement: AXUIElement,
        maxBefore: Int = 300,
        maxAfter: Int = 400,
        allowKeyboardSelection: Bool = false
    ) async -> SurroundingTextSnapshot {
        let readStart = ContinuousClock.now
        // Cap per-message AX IPC (see readSurroundingText) so a busy target app can't block ~6s/call.
        _ = AXUIElementSetMessagingTimeout(appElement, axMessagingTimeoutSeconds)

        // ── Attempt 1: Standard focused element ──
        var focused = focusedElement(in: appElement)
        var didBFS = false

        // ── Attempt 2: BFS AXWebArea fallback ──
        // Standard AX focused-element query often returns nil for Electron/Chromium apps
        // because the text element lives inside a web content subtree, not at the app root.
        if focused == nil {
            axLog.info("readSurroundingTextWithSync: standard focused element nil — starting BFS")
            focused = searchForWebAreaFocusedElement(in: appElement)
            didBFS = true
            if focused == nil {
                axLog.warning("readSurroundingTextWithSync: BFS found no AXWebArea — returning empty snapshot")
                return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: .unknown)
            }
        }

        guard let focused else {
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: .unknown)
        }

        // Web/Electron detection is invariant for `focused` within one read — compute the AX
        // attribute-names round-trip once and reuse it (gates below + the app-kind tag).
        let focusedIsWeb = isWebOrElectronElement(focused)

        // Genuine web form controls (<textarea>/<input>) expose an honest, self-scoped
        // kAXValue + caret — read them natively FIRST so a TextMarker read can't capture
        // surrounding page text as context (see nativeReadForWebFormControl).
        if focusedIsWeb,
           let nativeSnap = nativeReadForWebFormControl(focused, maxBefore: maxBefore, maxAfter: maxAfter) {
            let elapsed = ContinuousClock.now - readStart
            axLog.info("readSurroundingTextWithSync: done via native form-control read in \(ms(elapsed))ms — prec=\(nativeSnap.precedingText?.count ?? 0)ch foll=\(nativeSnap.followingText?.count ?? 0)ch")
            return nativeSnap.withAppKind(.webView)
        }

        // Prefer TextMarkers for web/Electron elements. This reads the real cursor context
        // and sidesteps both the fraudulent (0,0) cursor and the keyboard fallback entirely.
        if focusedIsWeb,
           let markerSnap = extractViaTextMarkers(focused, maxBefore: maxBefore, maxAfter: maxAfter),
           markerSnap.hasContext {
            let elapsed = ContinuousClock.now - readStart
            axLog.info("readSurroundingTextWithSync: done via TextMarkers in \(ms(elapsed))ms — prec=\(markerSnap.precedingText?.count ?? 0)ch foll=\(markerSnap.followingText?.count ?? 0)ch")
            return markerSnap.withAppKind(.webView)
        }

        // Pass appElement: nil if we already did BFS, to avoid repeating BFS inside extract().
        let initial = await extract(
            from: focused,
            appElement: didBFS ? nil : appElement,
            maxBefore: maxBefore,
            maxAfter: maxAfter,
            allowKeyboardSelection: allowKeyboardSelection
        )

        // Tag the snapshot with the app kind (native vs web view) for diagnostics.
        // Web-area extraction methods are themselves proof of a web view; otherwise probe the element.
        let detectedKind: SurroundingTextSnapshot.AppKind = {
            switch initial.extractionMethod {
            case .axWebAreaBFS: return .webView
            default:            return focusedIsWeb ? .webView : .native
            }
        }()

        // kAXValue was absent but the BFS/keyboard fallback returned context — report it directly.
        var valueRef: CFTypeRef?
        let hasAXValue = AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success
        if !hasAXValue && initial.hasContext {
            let elapsed = ContinuousClock.now - readStart
            axLog.info("readSurroundingTextWithSync: done via fallback in \(ms(elapsed))ms — prec=\(initial.precedingText?.count ?? 0)ch method=\(initial.extractionMethod.rawValue, privacy: .public) kind=\(detectedKind.rawValue, privacy: .public)")
            return initial.withAppKind(detectedKind)
        }

        let elapsed = ContinuousClock.now - readStart
        axLog.info("readSurroundingTextWithSync: done in \(ms(elapsed))ms — prec=\(initial.precedingText?.count ?? 0)ch foll=\(initial.followingText?.count ?? 0)ch pos=\(initial.cursorPosition.rawValue, privacy: .public) method=\(initial.extractionMethod.rawValue, privacy: .public) kind=\(detectedKind.rawValue, privacy: .public)")
        return initial.withAppKind(detectedKind)
    }

    /// Returns true when the focused element belongs to a web/Electron/browser view.
    /// Detection is based on non-standard AX attribute name prefixes used by Chromium and WebKit.
    static func isWebOrElectronElement(_ element: AXUIElement) -> Bool {
        var namesRef: CFArray?
        guard AXUIElementCopyAttributeNames(element, &namesRef) == .success,
              let names = namesRef as? [String] else { return false }
        // Chromium-based apps expose "AXDOM*" or "AXWeb*" attributes.
        // WebKit (Safari) exposes "AXWeb*" attributes.
        return names.contains(where: { $0.hasPrefix("AXDOM") || $0.hasPrefix("AXWeb") })
    }

    /// Classifies a focused element as a native control or a web view, for diagnostics.
    private static func detectAppKind(of element: AXUIElement) -> SurroundingTextSnapshot.AppKind {
        isWebOrElectronElement(element) ? .webView : .native
    }

    // MARK: Private — TextMarker reads (web / Electron)

    /// Reads the text just before and after the cursor inside a web page or web-based app
    /// (browsers, Electron). Uses WebKit/Chromium "TextMarker" attributes, which address
    /// positions by opaque markers instead of integer offsets, so they stay correct even when
    /// the app wrongly reports the cursor at the very start (Chromium's fraudulent (0,0) cursor)
    /// — the main reason these reads used to fall through to the keyboard fallback.
    ///
    /// Returns nil if the element does not expose the TextMarker API, so the caller can
    /// continue down the offset/BFS/keyboard ladder. Every step is guarded; a single
    /// missing attribute aborts cleanly with nil.
    private static func extractViaTextMarkers(
        _ element: AXUIElement,
        maxBefore: Int,
        maxAfter: Int
    ) -> SurroundingTextSnapshot? {
        // Try the focused element first. WebKit/Chromium often hosts the TextMarker
        // attributes on the AXWebArea ancestor instead, so try that next.
        if let snap = markerRead(on: element, maxBefore: maxBefore, maxAfter: maxAfter) {
            return snap
        }
        if let webArea = webAreaAncestor(of: element),
           let snap = markerRead(on: webArea, maxBefore: maxBefore, maxAfter: maxAfter) {
            return snap
        }
        axLog.info("textMarkers: no strategy produced context")
        return nil
    }

    /// Reads preceding/following text from `element` via TextMarkers.
    ///
    /// Algorithm:
    ///   1. Read the caret/selection as a marker range (AXSelectedTextMarkerRange).
    ///   2. Split it into start/end caret markers (AXTextMarkerRangeCopy{Start,End}Marker C SPI).
    ///   3. Get the field's bounds markers (AXTextMarkerRangeForUIElement → split), so the
    ///      context stays scoped to the field rather than the whole web page.
    ///   4. Build "field start → caret" and "caret → field end" ranges and resolve each to
    ///      text (AXStringForTextMarkerRange). This is immune to the fraudulent (0,0) cursor
    ///      and to kAXValue returning truncated/partial text.
    private static func markerRead(
        on element: AXUIElement,
        maxBefore: Int,
        maxAfter: Int
    ) -> SurroundingTextSnapshot? {
        guard let selRange = copyAttr(element, "AXSelectedTextMarkerRange") else {
            axLog.debug("textMarkers: AXSelectedTextMarkerRange absent")
            return nil
        }

        // Split the caret/selection range into its boundary markers.
        guard let caretStart = startMarker(of: selRange, element: element),
              let caretEnd   = endMarker(of: selRange, element: element) else {
            axLog.debug("textMarkers: cannot split selection range — trying index path")
            return markerReadViaIndex(element, selRange: selRange, maxBefore: maxBefore, maxAfter: maxAfter)
        }

        // Field bounds: prefer the element's own marker range so preceding/following stay scoped
        // to THIS field. If that is unavailable, document-wide markers would reach back into
        // unrelated page content sitting just before the caret (e.g. a live-region "response
        // ready" status in a chat app), wrongly capturing it as the preceding text. So before
        // falling back to document-wide, clamp the read to the caret's CURRENT LINE — the caret
        // is in the real field, so its line is the field's content, not a sibling page element.
        let bounds: (start: CFTypeRef, end: CFTypeRef)? = {
            if let fieldRange = copyParam(element, "AXTextMarkerRangeForUIElement", element),
               let fs = startMarker(of: fieldRange, element: element),
               let fe = endMarker(of: fieldRange, element: element) {
                return (fs, fe)
            }
            if let lineRange = copyParam(element, "AXLineTextMarkerRangeForTextMarker", caretStart),
               let ls = startMarker(of: lineRange, element: element),
               let le = endMarker(of: lineRange, element: element) {
                axLog.info("textMarkers: field range unavailable — scoping to the caret's current line")
                return (ls, le)
            }
            if let ds = copyAttr(element, "AXStartTextMarker"),
               let de = copyAttr(element, "AXEndTextMarker") {
                axLog.info("textMarkers: field+line ranges unavailable — document-wide bounds (may include page text)")
                return (ds, de)
            }
            return nil
        }()
        guard let bounds else {
            axLog.debug("textMarkers: no field/document bounds — trying index path")
            return markerReadViaIndex(element, selRange: selRange, maxBefore: maxBefore, maxAfter: maxAfter)
        }

        // Order the selection's two boundary markers by document position before slicing.
        // For a selection (especially a full-field "select all"), the start/end markers can
        // arrive REVERSED (anchor→focus order, not document order) — which would put the entire
        // selected text into BOTH preceding and following, and make the formatter add spaces on
        // both sides of a replacement. Distance from the field start disambiguates them: the
        // marker with the shorter "field start → marker" string is the real selection start, so
        // preceding ends strictly before the selection and following starts strictly after it.
        // (For a plain caret the two markers are equal, so this is a no-op.)
        let toCaretStart = markerRangeString(element, from: bounds.start, to: caretStart)
        let toCaretEnd   = markerRangeString(element, from: bounds.start, to: caretEnd)
        let startIsEarlier = (toCaretStart?.count ?? 0) <= (toCaretEnd?.count ?? 0)
        let selEndMarker = startIsEarlier ? caretEnd : caretStart
        let precFull = startIsEarlier ? toCaretStart : toCaretEnd
        let follFull = markerRangeString(element, from: selEndMarker, to: bounds.end)
        guard precFull != nil || follFull != nil else {
            axLog.debug("textMarkers: marker ranges produced no string — trying index path")
            return markerReadViaIndex(element, selRange: selRange, maxBefore: maxBefore, maxAfter: maxAfter)
        }

        // Empty field that leaks its placeholder as phantom marker text. The integer
        // AXSelectedTextRange caret is pinned at the field start (0,0) while the markers still
        // report surrounding text — as preceding (the original case) OR as following (an empty
        // field whose placeholder sits "after" the caret, e.g. a chat input prompt). Any one of
        // these independent tells confirms the marker text is a placeholder, not real content:
        //   (a) markers report PRECEDING text — impossible if the caret is truly at offset 0;
        //   (b) the field's real value (AXValue) is present but empty;
        //   (c) the marker text matches the field's declared placeholder (AXPlaceholderValue).
        if let selR = rangeAttr(element, "AXSelectedTextRange"), selR.loc == 0, selR.len == 0,
           (precFull?.isEmpty == false || follFull?.isEmpty == false) {
            // (b) Real value present but empty. Only trust AXValue when it actually exists;
            // a nil (unavailable) value is no evidence either way for a web field.
            let axValue = copyAttr(element, kAXValueAttribute as String) as? String
            let valuePresentAndEmpty = (axValue != nil) && axValue!.isEmpty
            // (c) Declared placeholder equals the marker text (compared without surrounding space).
            let placeholder = (copyAttr(element, "AXPlaceholderValue") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let markerText = ((precFull ?? "") + (follFull ?? ""))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesPlaceholder = placeholder.map { !$0.isEmpty && markerText == $0 } ?? false
            // (a) Preceding text at offset 0 is a contradiction.
            let precedingContradiction = (precFull?.isEmpty == false)

            if precedingContradiction || valuePresentAndEmpty || matchesPlaceholder {
                axLog.info("textMarkers: caret (0,0) placeholder field — prec=\(precFull?.count ?? 0)ch foll=\(follFull?.count ?? 0)ch valueEmpty=\(valuePresentAndEmpty, privacy: .public) matchPlaceholder=\(matchesPlaceholder, privacy: .public) — treating as empty")
                return .init(precedingText: "", followingText: "", cursorPosition: .empty, extractionMethod: .axWebTextMarker)
            }
            // Caret at the start with marker text but no placeholder tell fired: this is either a
            // real cursor-at-start with text after, or a placeholder we can't yet identify. Log
            // the available signals so the case can be diagnosed without leaking text content.
            axLog.info("textMarkers: caret (0,0) with marker text, no placeholder tell — prec=\(precFull?.count ?? 0)ch foll=\(follFull?.count ?? 0)ch axValuePresent=\(axValue != nil, privacy: .public) placeholderPresent=\(placeholder != nil, privacy: .public)")
        }

        // idx and total are field-scoped and mutually consistent (both from these reads).
        let idx        = precFull?.count
        let totalChars = (precFull?.count ?? 0) + (follFull?.count ?? 0)

        // Web/Electron paragraph breaks are often STRUCTURAL (DOM element boundaries), so the
        // marker string omits a "\n" for them — the caret can sit at the start of a new line
        // while the preceding text just ends with "…isso.". Detect that by reading the current
        // line up to the caret: if there is text overall but the line before the caret is empty,
        // the caret is at a line/paragraph start, so reconstruct the missing "\n" — the formatter
        // then capitalizes and adds NO leading space. No false positives (only fires when the
        // line before the caret is genuinely empty); guarded (if the line SPI is absent, nothing
        // changes), and self-diagnosing (logs the available line params when unusable).
        var precForFormatter = precFull
        if let p = precFull, !p.isEmpty, !p.hasSuffix("\n") {
            if let lineRange = copyParam(element, "AXLineTextMarkerRangeForTextMarker", caretStart),
               let lineStart = startMarker(of: lineRange, element: element),
               let lineHead  = markerRangeString(element, from: lineStart, to: caretStart) {
                if lineHead.isEmpty {
                    precForFormatter = p + "\n"
                    axLog.info("textMarkers: caret at line start — reconstructed structural paragraph break")
                }
            } else {
                let lineParams = (paramAttrNames(element) ?? []).filter {
                    let l = $0.lowercased(); return l.contains("line") || l.contains("paragraph")
                }
                axLog.info("textMarkers: line-start SPI unavailable — line/para params: \(lineParams.joined(separator: ","), privacy: .public)")
            }
        }

        let precedingText = precForFormatter.map { String($0.suffix(maxBefore)) }
        let followingText = follFull.map { String($0.prefix(maxAfter)) }

        let position: SurroundingTextSnapshot.CursorPosition
        if let idx {
            if idx <= 0               { position = .start }
            else if follFull == nil   { position = .middle }   // following unread → total unknown, don't claim .end
            else if idx >= totalChars { position = .end }
            else                      { position = .middle }
        } else {
            position = .unknown
        }

        axLog.info("textMarkers[markers]: prec=\(precedingText?.count ?? -1)ch foll=\(followingText?.count ?? -1)ch idx=\(idx ?? -1) total=\(totalChars) pos=\(position.rawValue, privacy: .public)")
        return .init(precedingText: precedingText, followingText: followingText, cursorPosition: position, extractionMethod: .axWebTextMarker)
    }

    // MARK: TextMarker C SPI (resolved at runtime via dlsym; nil if unavailable)

    /// Returns the start marker of a marker range. Prefers the AXTextMarkerRangeCopyStartMarker
    /// C function (WebKit/Chromium SPI), then the parameterized-attribute form.
    private static func startMarker(of range: CFTypeRef, element: AXUIElement) -> CFTypeRef? {
        callMarkerRangeFn("AXTextMarkerRangeCopyStartMarker", range)
            ?? copyParam(element, "AXStartTextMarkerForTextMarkerRange", range)
    }

    /// Returns the end marker of a marker range. Prefers the AXTextMarkerRangeCopyEndMarker
    /// C function (WebKit/Chromium SPI), then the parameterized-attribute form.
    private static func endMarker(of range: CFTypeRef, element: AXUIElement) -> CFTypeRef? {
        callMarkerRangeFn("AXTextMarkerRangeCopyEndMarker", range)
            ?? copyParam(element, "AXEndTextMarkerForTextMarkerRange", range)
    }

    /// Builds a marker range from two markers and resolves it to a string. Prefers the
    /// AXTextMarkerRangeCreate C function, then the unordered-markers attribute; reads text
    /// via AXStringForTextMarkerRange, falling back to the attributed-string variant.
    private static func markerRangeString(_ element: AXUIElement, from a: CFTypeRef, to b: CFTypeRef) -> String? {
        let range = createMarkerRange(from: a, to: b)
            ?? copyParam(element, "AXTextMarkerRangeForUnorderedTextMarkers", [a, b] as CFArray)
        guard let range else { return nil }
        if let s = copyParam(element, "AXStringForTextMarkerRange", range) as? String { return s }
        if let attr = copyParam(element, "AXAttributedStringForTextMarkerRange", range) as? NSAttributedString {
            return attr.string
        }
        return nil
    }

    /// Calls a C SPI of the form `AXTextMarkerRef fn(AXTextMarkerRangeRef)` resolved via dlsym.
    /// The result is +1 (Copy), so we consume the retain with takeRetainedValue().
    private typealias MarkerRangeFn = @convention(c) (AnyObject) -> Unmanaged<AnyObject>?

    /// Resolves a TextMarker range function by name (a dlsym symbol-table search across loaded
    /// images). Pure; callers cache the result in the static lets below.
    private static func resolveMarkerRangeFn(_ name: String) -> MarkerRangeFn? {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }  // -2 = RTLD_DEFAULT
        return unsafeBitCast(sym, to: MarkerRangeFn.self)
    }

    // The two TextMarker boundary functions, resolved once each. These SPI symbols are stable for
    // the process lifetime, so `static let` (immutable, run-once, thread-safe initialization) avoids
    // both repeated dlsym lookups and any global mutable state — safe from any thread/executor.
    /// The "give me the start of this range" system function, looked up once and reused.
    /// nil if this macOS version does not expose it.
    private static let copyStartMarkerFn = resolveMarkerRangeFn("AXTextMarkerRangeCopyStartMarker")
    /// The "give me the end of this range" system function, looked up once and reused.
    /// nil if this macOS version does not expose it.
    private static let copyEndMarkerFn   = resolveMarkerRangeFn("AXTextMarkerRangeCopyEndMarker")

    /// Calls one of the cached marker-boundary system functions by name and returns its result
    /// (the start or end marker), or nil if that function is unavailable on this system.
    private static func callMarkerRangeFn(_ name: String, _ range: CFTypeRef) -> CFTypeRef? {
        let fn: MarkerRangeFn?
        switch name {
        case "AXTextMarkerRangeCopyStartMarker": fn = copyStartMarkerFn
        case "AXTextMarkerRangeCopyEndMarker":   fn = copyEndMarkerFn
        default:                                  fn = resolveMarkerRangeFn(name)  // unexpected name: resolve uncached
        }
        guard let fn else { return nil }
        return fn(range)?.takeRetainedValue()
    }

    /// Shape of the hidden system function that builds a marker range from a start and an end marker.
    /// Used to call it after looking it up by name at runtime.
    private typealias MarkerRangeCreateFn = @convention(c) (CFAllocator?, AnyObject, AnyObject) -> Unmanaged<AnyObject>?

    /// Resolved once: AXTextMarkerRangeCreate is a stable SPI symbol for the process lifetime.
    private static let createMarkerRangeFn: MarkerRangeCreateFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AXTextMarkerRangeCreate") else { return nil }  // -2 = RTLD_DEFAULT
        return unsafeBitCast(sym, to: MarkerRangeCreateFn.self)
    }()

    /// Calls AXTextMarkerRangeCreate(allocator, start, end) via the once-resolved pointer. Result is +1 (Create).
    private static func createMarkerRange(from a: CFTypeRef, to b: CFTypeRef) -> CFTypeRef? {
        guard let fn = createMarkerRangeFn else { return nil }
        return fn(nil, a, b)?.takeRetainedValue()
    }

    /// The parameterized AX attribute names the element exposes (diagnostics only). Used to probe
    /// which line/paragraph TextMarker attributes a given web/Electron element actually supports.
    private static func paramAttrNames(_ element: AXUIElement) -> [String]? {
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success else { return nil }
        return names as? [String]
    }

    /// Fallback: caret integer index via AXIndexForTextMarker, then AXStringForRange char-range
    /// slicing. For apps exposing the index API instead of the range-decomposition path.
    private static func markerReadViaIndex(
        _ element: AXUIElement,
        selRange: CFTypeRef,
        maxBefore: Int,
        maxAfter: Int
    ) -> SurroundingTextSnapshot? {
        guard let idx = (copyParam(element, "AXIndexForTextMarker", selRange) as? NSNumber)?.intValue, idx >= 0 else {
            return nil
        }
        let total   = (copyAttr(element, "AXNumberOfCharacters") as? NSNumber)?.intValue
        let precLoc = max(0, idx - maxBefore)
        let precLen = idx - precLoc
        let follLen = total.map { max(0, min(maxAfter, $0 - idx)) } ?? maxAfter
        // A zero-length side is a genuine "nothing here" — not a successful read.
        let prec = precLen > 0 ? stringForCharRange(element, location: precLoc, length: precLen) : ""
        let foll = follLen > 0 ? stringForCharRange(element, location: idx, length: follLen) : ""
        guard (precLen > 0 && prec != nil) || (follLen > 0 && foll != nil) else { return nil }
        let position: SurroundingTextSnapshot.CursorPosition =
            idx <= 0 ? .start : ((total.map { idx >= $0 } ?? false) ? .end : .middle)
        axLog.info("textMarkers[index]: prec=\(prec?.count ?? -1)ch foll=\(foll?.count ?? -1)ch idx=\(idx) pos=\(position.rawValue, privacy: .public)")
        return .init(precedingText: prec, followingText: foll, cursorPosition: position, extractionMethod: .axWebTextMarker)
    }

    /// Reads the substring for an integer character range via the AXStringForRange
    /// parameterized attribute (its parameter is an AXValue-wrapped CFRange).
    private static func stringForCharRange(_ element: AXUIElement, location: Int, length: Int) -> String? {
        guard length > 0 else { return "" }
        guard location >= 0 else { return nil }   // refuse negative locations defensively
        var cfRange = CFRange(location: location, length: length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return nil }
        return copyParam(element, "AXStringForRange", axRange) as? String
    }

    /// Walks up the AX parent chain to find the enclosing AXWebArea (hops capped).
    private static func webAreaAncestor(of element: AXUIElement, maxHops: Int = 12) -> AXUIElement? {
        var current = element
        for _ in 0..<maxHops {
            if let role = copyAttr(current, kAXRoleAttribute as String) as? String, role == "AXWebArea" {
                return current
            }
            guard let parent = copyAttr(current, kAXParentAttribute as String),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            current = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return nil
    }

    /// Elapsed milliseconds for a Duration, for timing logs.
    private static func ms(_ d: Duration) -> Int {
        Int(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
    }

    /// Reads a plain AX attribute, returning the raw CF value or nil on failure.
    private static func copyAttr(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    /// Reads a parameterized AX attribute (e.g. TextMarker queries), returning the raw CF value or nil.
    private static func copyParam(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &result) == .success ? result : nil
    }

    /// Reads an AX attribute whose value is a CFRange (AXValue), e.g. AXSelectedTextRange
    /// or AXVisibleCharacterRange. Returns (location, length) or nil.
    private static func rangeAttr(_ element: AXUIElement, _ attribute: String) -> (loc: Int, len: Int)? {
        guard let raw = copyAttr(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var r = CFRange(location: 0, length: 0)
        guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &r) else { return nil }
        return (r.location, r.length)
    }

    // MARK: Private — Clipboard fallback

    /// Uses Cmd+Shift+Up/Down to select text before/after the cursor, then reads the clipboard.
    /// Safely guarded: will NOT trigger if the user has an active text selection.
    /// Note: Cmd+Shift+Up selects to viewport top in some editors (not document start).
    private static func extractContextViaKeyboardSelection(_ element: AXUIElement) async -> SurroundingTextSnapshot {
        if hasActiveSelection(element) {
            axLog.info("keyboardFallback: skipped — user has active selection, would destroy it")
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: .unknown)
        }

        axLog.info("keyboardFallback: starting Cmd+Shift+Up/Down clipboard capture")

        let pasteboard = NSPasteboard.general
        // Save current clipboard so we can restore it after capture.
        let originalItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { newItem.setData(data, forType: type) }
            }
            return newItem
        }

        let source = CGEventSource(stateID: .hidSystemState)

        // ── Part 1: Preceding text (Cmd+Shift+↑ selects to top, then Cmd+C) ──
        sendKey(source, 126, command: true, shift: true, keyDown: true)
        sendKey(source, 126, command: true, shift: true, keyDown: false)
        try? await Task.sleep(nanoseconds: 30_000_000)

        pasteboard.clearContents()
        let precChangeCount = pasteboard.changeCount
        sendKey(source, 8, command: true, keyDown: true)   // Cmd+C
        sendKey(source, 8, command: true, keyDown: false)

        // Poll up to 300ms for clipboard to update (increased from 100ms for loaded systems).
        var precElapsed = 0
        while pasteboard.changeCount == precChangeCount && precElapsed < 300 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            precElapsed += 50
        }
        if pasteboard.changeCount == precChangeCount {
            axLog.warning("keyboardFallback: clipboard timeout for preceding text after \(precElapsed)ms")
        } else {
            axLog.debug("keyboardFallback: preceding clipboard changed after \(precElapsed)ms")
        }
        let precedingText = pasteboard.string(forType: .string)

        // Collapse selection back to original cursor position.
        sendKey(source, 124, keyDown: true)   // → collapses right
        sendKey(source, 124, keyDown: false)
        try? await Task.sleep(nanoseconds: 30_000_000)

        // ── Part 2: Following text (Cmd+Shift+↓ selects to bottom, then Cmd+C) ──
        sendKey(source, 125, command: true, shift: true, keyDown: true)
        sendKey(source, 125, command: true, shift: true, keyDown: false)
        try? await Task.sleep(nanoseconds: 30_000_000)

        pasteboard.clearContents()
        let follChangeCount = pasteboard.changeCount
        sendKey(source, 8, command: true, keyDown: true)   // Cmd+C
        sendKey(source, 8, command: true, keyDown: false)

        var follElapsed = 0
        while pasteboard.changeCount == follChangeCount && follElapsed < 300 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            follElapsed += 50
        }
        if pasteboard.changeCount == follChangeCount {
            axLog.warning("keyboardFallback: clipboard timeout for following text after \(follElapsed)ms")
        } else {
            axLog.debug("keyboardFallback: following clipboard changed after \(follElapsed)ms")
        }
        let followingText = pasteboard.string(forType: .string)

        // Collapse selection to restore original cursor position.
        sendKey(source, 123, keyDown: true)   // ← collapses left
        sendKey(source, 123, keyDown: false)
        try? await Task.sleep(nanoseconds: 30_000_000)

        // Restore the user's clipboard. If it was empty before, clear ours so the
        // captured selection text is never left stranded on the clipboard.
        pasteboard.clearContents()
        if let items = originalItems, !items.isEmpty {
            pasteboard.writeObjects(items)
        }

        axLog.info("keyboardFallback: done — prec=\(precedingText?.count ?? 0)ch foll=\(followingText?.count ?? 0)ch")
        return .init(
            precedingText: precedingText,
            followingText: followingText,
            cursorPosition: (precedingText?.isEmpty ?? true) ? .unknown : .middle,
            extractionMethod: .keyboardSimulation
        )
    }

    // MARK: Private — native read for genuine web form controls

    /// Reads surrounding text from a GENUINE web form control (`<textarea>` / `<input>`)
    /// using the native offset path — the SAME `kAXValue` + `kAXSelectedTextRange` contract
    /// a native macOS text field exposes.
    ///
    /// Why this exists: a real form control is an accessibility LEAF whose text is its own
    /// `kAXValue`, NOT part of the surrounding page's TextMarker document. Reading it via
    /// TextMarkers therefore captures unrelated page content sitting next to the control
    /// (e.g. a live-region "response ready" status just before the input) as the preceding
    /// text. The native value is self-scoped, so it can never leak neighbouring page text.
    ///
    /// Intentionally site-agnostic: it keys on the accessibility CONTRACT of the focused
    /// element (a plain leaf text control with an honest caret), not on any per-website markup.
    ///
    /// Returns nil — so the caller falls through to the TextMarker path — when the element is
    /// NOT a plain leaf text control, exposes no value, or reports the fraudulent (0,0) cursor
    /// Chromium contenteditable fields use (those genuinely need TextMarkers).
    /// - Parameters:
    ///   - element: The focused AX element to read from.
    ///   - maxBefore: Max characters captured before the cursor.
    ///   - maxAfter: Max characters captured after the cursor.
    private static func nativeReadForWebFormControl(
        _ element: AXUIElement,
        maxBefore: Int,
        maxAfter: Int
    ) -> SurroundingTextSnapshot? {
        // Resolve the real text control. Browsers sometimes hand us a wrapper (web area or
        // group) as the focused element; descend to ITS focused leaf once so we read the field
        // itself, not an ancestor that hosts the page TextMarker document.
        var target = element
        var roleOpt = copyAttr(target, kAXRoleAttribute as String) as? String
        if roleOpt != "AXTextField", roleOpt != "AXTextArea", let leaf = focusedElement(in: target) {
            target = leaf
            roleOpt = copyAttr(target, kAXRoleAttribute as String) as? String
        }

        // Only genuine plain-text controls. Rich contenteditable editors report other roles
        // (AXWebArea / AXGroup) and must keep using TextMarkers (which preserve their structural
        // paragraph breaks). Log the role so a non-match is diagnosable from one reproduction.
        guard let role = roleOpt, role == "AXTextField" || role == "AXTextArea" else {
            axLog.info("nativeWebFormControl: not a plain text control (role=\(roleOpt ?? "nil", privacy: .public)) — deferring to TextMarkers")
            return nil
        }

        // The control's own text — self-scoped, never the page document.
        guard let value = copyAttr(target, kAXValueAttribute as String) as? String else {
            axLog.info("nativeWebFormControl: role=\(role, privacy: .public) but kAXValue absent — deferring to TextMarkers")
            return nil
        }

        // Empty control → empty context (the common "fresh field" case, e.g. a new chat query).
        guard !value.isEmpty else {
            axLog.info("nativeWebFormControl: role=\(role, privacy: .public) empty field — empty context")
            return .init(precedingText: "", followingText: "", cursorPosition: .empty, extractionMethod: .axAPI)
        }

        let nsText = value as NSString
        let totalLength = nsText.length

        // Honest caret required. A (0,0) range on a NON-empty field is the Chromium fraud —
        // bail to TextMarkers; an unreadable or out-of-bounds range also bails. Each bail logs.
        guard let range = rangeAttr(target, kAXSelectedTextRangeAttribute as String) else {
            axLog.info("nativeWebFormControl: role=\(role, privacy: .public) value=\(totalLength)ch but no caret range — deferring to TextMarkers")
            return nil
        }
        guard !(range.loc == 0 && range.len == 0) else {
            axLog.info("nativeWebFormControl: role=\(role, privacy: .public) value=\(totalLength)ch fraudulent (0,0) caret — deferring to TextMarkers")
            return nil
        }
        guard range.loc >= 0, range.loc <= totalLength else {
            axLog.info("nativeWebFormControl: role=\(role, privacy: .public) caret \(range.loc) out of bounds (len=\(totalLength)) — deferring to TextMarkers")
            return nil
        }

        // Slice preceding/following around the honest caret (real "\n"s in the value are kept).
        let selStart = min(range.loc, totalLength)
        let selEnd   = min(selStart + max(range.len, 0), totalLength)

        let beforeStart    = max(0, selStart - maxBefore)
        let precedingSlice = nsText.substring(with: NSRange(location: beforeStart, length: selStart - beforeStart))
        let afterLength    = min(maxAfter, totalLength - selEnd)
        let followingSlice = afterLength > 0
            ? nsText.substring(with: NSRange(location: selEnd, length: afterLength))
            : ""

        let position: SurroundingTextSnapshot.CursorPosition
        if selStart == 0                { position = .start }
        else if selStart >= totalLength { position = .end }
        else                            { position = .middle }

        axLog.info("nativeWebFormControl: role=\(role, privacy: .public) prec=\(selStart - beforeStart)ch foll=\(afterLength)ch pos=\(position.rawValue, privacy: .public)")
        return .init(precedingText: precedingSlice, followingText: followingSlice, cursorPosition: position, extractionMethod: .axAPI)
    }

    // MARK: Private — core extraction

    /// Reads surrounding text from a focused element via the offset-based AX ladder.
    /// Stages, in order: read `kAXValue` + `kAXSelectedTextRange`; on failure, a BFS rescue down the
    /// app tree for an `AXWebArea` child; fraudulent-(0,0)-cursor detection on non-empty fields; and —
    /// only when `allowKeyboardSelection` is true AND the element is web/Electron — the clipboard
    /// keyboard-selection fallback. Returns an `.unknown` snapshot when every stage fails.
    /// - Parameters:
    ///   - element: The focused AX element to read from.
    ///   - appElement: App root for the BFS rescue; pass nil to skip BFS.
    ///   - maxBefore: Max characters captured before the cursor.
    ///   - maxAfter: Max characters captured after the cursor.
    ///   - allowKeyboardSelection: Gate for the destructive clipboard keyboard fallback.
    private static func extract(
        from element: AXUIElement,
        appElement: AXUIElement? = nil,
        maxBefore: Int = 300,
        maxAfter: Int = 400,
        allowKeyboardSelection: Bool = false
    ) async -> SurroundingTextSnapshot {
        // ── Step 1: Read full text of the field ──
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let fullText = valueRef as? String else {
            axLog.info("extract: kAXValueAttribute failed — trying BFS/keyboard fallbacks")
            // BFS retry in case we received the wrong focused element from the app root.
            if let appElement, let bfsFocused = searchForWebAreaFocusedElement(in: appElement) {
                var bfsValueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(bfsFocused, kAXValueAttribute as CFString, &bfsValueRef) == .success,
                   let bfsText = bfsValueRef as? String, !bfsText.isEmpty {
                    axLog.info("extract: BFS rescue — got \(bfsText.count) chars from AXWebArea child")
                    return extractTextFromElement(bfsFocused, fullText: bfsText, maxBefore: maxBefore, maxAfter: maxAfter, method: .axWebAreaBFS)
                }
            }
            if allowKeyboardSelection, isWebOrElectronElement(element) {
                axLog.info("extract: trying keyboard selection fallback")
                let snapshot = await extractContextViaKeyboardSelection(element)
                if snapshot.hasContext {
                    axLog.info("extract: keyboard fallback succeeded — prec=\(snapshot.precedingText?.count ?? 0)ch")
                    return snapshot
                }
                axLog.warning("extract: keyboard fallback returned no context")
            }
            axLog.error("extract: all methods failed — returning empty snapshot")
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: .unknown)
        }

        guard !fullText.isEmpty else {
            axLog.debug("extract: field is empty")
            return .init(precedingText: "", followingText: "", cursorPosition: .empty, extractionMethod: .axAPI)
        }

        let nsText     = fullText as NSString
        let totalLength = nsText.length
        axLog.debug("extract: kAXValueAttribute OK — field has \(totalLength) chars")

        // ── Step 2: Read cursor/selection range ──
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef,
              CFGetTypeID(rangeVal) == AXValueGetTypeID() else {
            axLog.info("extract: kAXSelectedTextRangeAttribute failed — position unknown, returning tail as preceding")
            if allowKeyboardSelection, isWebOrElectronElement(element) {
                let snapshot = await extractContextViaKeyboardSelection(element)
                if snapshot.hasContext {
                    axLog.info("extract: keyboard fallback resolved missing range — prec=\(snapshot.precedingText?.count ?? 0)ch")
                    return snapshot
                }
            }
            // Return document tail so the LLM has some context; mark as .unknown for JIT re-read.
            let tail = nsText.substring(from: max(0, totalLength - maxBefore))
            return .init(precedingText: tail, followingText: "", cursorPosition: .unknown, extractionMethod: .axAPI)
        }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(unsafeBitCast(rangeVal, to: AXValue.self), .cfRange, &cfRange) else {
            axLog.error("extract: AXValueGetValue failed on range value")
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: .unknown)
        }

        axLog.debug("extract: range=(\(cfRange.location), \(cfRange.length))")

        // ── Step 3: Fraudulent cursor detection ──
        // Chromium and some SwiftUI fields report (0, 0) even when the cursor is mid-document.
        // When detected with a non-empty field, try BFS/keyboard before trusting the position.
        // If ALL fallbacks fail, return nil so the formatter preserves LLM casing (not uppercase).
        if cfRange.location == 0, cfRange.length == 0, !fullText.isEmpty {
            axLog.warning("extract: fraudulent cursor (0,0) with \(totalLength)-char field — trying fallbacks")
            if let appElement, let bfsFocused = searchForWebAreaFocusedElement(in: appElement) {
                var bfsValueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(bfsFocused, kAXValueAttribute as CFString, &bfsValueRef) == .success,
                   let bfsText = bfsValueRef as? String, !bfsText.isEmpty {
                    axLog.info("extract: fraudulent cursor resolved via BFS")
                    return extractTextFromElement(bfsFocused, fullText: bfsText, maxBefore: maxBefore, maxAfter: maxAfter, method: .axWebAreaBFS)
                }
            }
            if allowKeyboardSelection, isWebOrElectronElement(element) {
                let snapshot = await extractContextViaKeyboardSelection(element)
                if snapshot.hasContext {
                    axLog.info("extract: fraudulent cursor resolved via keyboard")
                    return snapshot
                }
            }
            // Returning nil signals "unknown context" — formatter will NOT force uppercase.
            axLog.error("extract: fraudulent cursor (0,0) — all fallbacks failed, returning nil context")
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: .unknown)
        }

        // ── Step 4: Slice surrounding text ──
        let selStart = min(max(cfRange.location, 0), totalLength)
        let selEnd   = min(selStart + max(cfRange.length, 0), totalLength)

        let beforeStart    = max(0, selStart - maxBefore)
        let precedingSlice = nsText.substring(with: NSRange(location: beforeStart, length: selStart - beforeStart))

        let afterLength    = min(maxAfter, totalLength - selEnd)
        let followingSlice = afterLength > 0
            ? nsText.substring(with: NSRange(location: selEnd, length: afterLength))
            : ""

        let position: SurroundingTextSnapshot.CursorPosition
        if selStart == 0               { position = .start }
        else if selStart >= totalLength { position = .end }
        else                           { position = .middle }

        axLog.info("extract: success — prec=\(selStart - beforeStart)ch foll=\(afterLength)ch pos=\(position.rawValue, privacy: .public) method=axAPI")
        return .init(precedingText: precedingSlice, followingText: followingSlice, cursorPosition: position, extractionMethod: .axAPI)
    }

    /// Slices text around the cursor given a full text string and an AXUIElement with range info.
    private static func extractTextFromElement(
        _ element: AXUIElement,
        fullText: String,
        maxBefore: Int,
        maxAfter: Int,
        method: SurroundingTextSnapshot.ExtractionMethod
    ) -> SurroundingTextSnapshot {
        let nsText = fullText as NSString
        let totalLength = nsText.length

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef,
              CFGetTypeID(rangeVal) == AXValueGetTypeID() else {
            let tail = nsText.substring(from: max(0, totalLength - maxBefore))
            return .init(precedingText: tail, followingText: "", cursorPosition: .unknown, extractionMethod: method)
        }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(unsafeBitCast(rangeVal, to: AXValue.self), .cfRange, &cfRange) else {
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: method)
        }

        // Chromium/Electron AXWebArea children often report (0,0) while holding real text. Treat it as
        // "unknown" (mirrors the guard in extract()) so slicing doesn't produce corrupt context and the
        // JIT re-read + start-snapshot fallback can recover.
        if cfRange.location == 0, cfRange.length == 0, totalLength > 0 {
            return .init(precedingText: nil, followingText: nil, cursorPosition: .unknown, extractionMethod: method)
        }

        let selStart = min(max(cfRange.location, 0), totalLength)
        let selEnd = min(selStart + max(cfRange.length, 0), totalLength)

        let beforeStart = max(0, selStart - maxBefore)
        let precedingSlice = nsText.substring(with: NSRange(location: beforeStart, length: selStart - beforeStart))
        let afterLength = min(maxAfter, totalLength - selEnd)
        let followingSlice = afterLength > 0
            ? nsText.substring(with: NSRange(location: selEnd, length: afterLength))
            : ""

        let position: SurroundingTextSnapshot.CursorPosition
        if selStart == 0 { position = .start }
        else if selStart >= totalLength { position = .end }
        else { position = .middle }

        return .init(precedingText: precedingSlice as String, followingText: followingSlice as String, cursorPosition: position, extractionMethod: method)
    }

    // MARK: Private — AX helpers

    /// Searches the accessibility tree via BFS for an AXWebArea, then returns the focused
    /// element inside it. Used when kAXFocusedUIElementAttribute fails for Electron/Chromium.
    ///
    /// Limits: 30 levels depth, 8000 elements max, 250ms hard timeout (ContinuousClock).
    /// Returns nil if no AXWebArea with a focused child is found within those limits.
    private static func searchForWebAreaFocusedElement(
        in appElement: AXUIElement
    ) -> AXUIElement? {
        // Use the focused window as BFS root to avoid traversing the entire app tree.
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success,
              let raw = windowRef,
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else {
            axLog.warning("BFS: no focused window — cannot search AX tree")
            return nil
        }

        let window = unsafeBitCast(raw, to: AXUIElement.self)

        // ContinuousClock is monotonic and unaffected by system load — more reliable than DispatchTime.
        let bfsStart  = ContinuousClock.now
        let maxDepth    = 30
        let maxElements = 8000
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        // Head index gives O(1) dequeue (Array.removeFirst is O(n)); identical FIFO/BFS order.
        var head = 0
        var visitedCount = 0

        axLog.debug("BFS: starting AXWebArea search (limit: \(maxElements) elements / 250ms)")

        while head < queue.count {
            guard ContinuousClock.now - bfsStart < .milliseconds(250) else {
                axLog.warning("BFS: 250ms timeout reached after \(visitedCount) elements — no AXWebArea found")
                return nil
            }
            guard visitedCount < maxElements else {
                axLog.warning("BFS: element limit (\(maxElements)) reached — no AXWebArea found")
                return nil
            }

            let (current, depth) = queue[head]; head += 1
            guard depth <= maxDepth else { continue }
            visitedCount += 1

            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current, kAXRoleAttribute as CFString, &roleRef
            ) == .success, let role = roleRef as? String else { continue }

            if role == "AXWebArea" {
                // Electron apps often use file:// or omit the URL entirely,
                // so we do NOT filter by HTTP/HTTPS — just ask who's focused inside.
                var focusedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    current, kAXFocusedUIElementAttribute as CFString, &focusedRef
                ) == .success,
                   let focusedRaw = focusedRef,
                   CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() {
                    let elapsed = ContinuousClock.now - bfsStart
                    axLog.info("BFS: AXWebArea found after \(visitedCount) elements in \(ms(elapsed))ms")
                    return unsafeBitCast(focusedRaw, to: AXUIElement.self)
                }
                axLog.warning("BFS: AXWebArea found but kAXFocusedUIElementAttribute returned nil")
            }

            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current, kAXChildrenAttribute as CFString, &childrenRef
            ) == .success,
                  let children = childrenRef as? [AXUIElement]
            else { continue }

            for child in children {
                queue.append((child, depth + 1))
            }
        }

        axLog.info("BFS: exhausted tree (\(visitedCount) elements) — no AXWebArea found")
        return nil
    }

    /// Returns the focused UI element of `appElement` via kAXFocusedUIElementAttribute, or nil if none / wrong type.
    private static func focusedElement(in appElement: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &ref
        ) == .success,
              let raw = ref,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    /// True when `element` currently holds a non-empty text selection (kAXSelectedTextRange length > 0).
    private static func hasActiveSelection(_ element: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &ref
        ) == .success,
              let val = ref,
              CFGetTypeID(val) == AXValueGetTypeID() else { return false }
        var range = CFRange(location: 0, length: 0)
        // Decode the CFRange; a failed decode is treated as "no selection" (fail-safe for the
        // destructive Backspace gate that depends on this).
        guard AXValueGetValue(unsafeBitCast(val, to: AXValue.self), .cfRange, &range) else { return false }
        return range.length > 0
    }

    /// True when the focused element of `appElement` currently has a non-empty text selection.
    /// Used to confirm a LIVE selection before destructive key simulation (the JIT Backspace),
    /// so a stale recording-time selection can't cause a real character to be deleted.
    static func hasLiveSelection(in appElement: AXUIElement) -> Bool {
        guard let focused = focusedElement(in: appElement) else { return false }
        return hasActiveSelection(focused)
    }

    /// Synthesizes and posts a single virtual-key event (down or up) with optional Cmd/Shift/Option
    /// modifiers. The primitive behind the keyboard-simulation fallback (selection capture in
    /// web/Electron fields). `keyCode` is a virtual key code (e.g. 8 = C, 126 = ↑, 124 = →).
    private static func sendKey(_ source: CGEventSource?, _ keyCode: CGKeyCode, command: Bool = false, shift: Bool = false, option: Bool = false, keyDown: Bool) {
        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) {
            var flags: CGEventFlags = []
            if command { flags.insert(.maskCommand) }
            if shift { flags.insert(.maskShift) }
            if option { flags.insert(.maskAlternate) }
            event.flags = flags
            // Post to the session event tap so the synthesized key reaches the frontmost app.
            event.post(tap: .cgSessionEventTap)
        }
    }
}
