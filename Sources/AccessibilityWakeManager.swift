import Cocoa
import ApplicationServices
import OSLog

/// AXObserver callback. Intentionally empty: subscribing alone is enough to keep
/// Chromium's accessibility tree built and updated; we never act on the events.
private func observerCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    // No-op: subscribing is the goal, not handling the events.
}

/// Keeps the frontmost app's accessibility tree awake so text can be read with low latency.
/// Chromium-based apps build their AX tree lazily; this forces it on and holds it open.
@MainActor
public final class AccessibilityWakeManager {
    /// The single shared instance used everywhere in the app.
    public static let shared = AccessibilityWakeManager()

    /// Writes diagnostic messages to the system log for debugging.
    private let logger = Logger(subsystem: "com.zachlatta.freeflow", category: "AccessibilityWakeManager")
    /// The currently installed watcher that keeps the other app's accessibility data awake; nil when nothing is being watched.
    // AXObserver: macOS Accessibility API object that subscribes to UI-change notifications.
    private var activeObserver: AXObserver?
    /// The hook that lets the watcher receive events on the main thread; removed when we stop watching.
    // CFRunLoopSource: macOS object that feeds the observer's notifications into the app's event loop.
    private var observerRunLoopSource: CFRunLoopSource?

    /// Private so the class can only be reached through the shared instance above.
    private init() {}

    // MARK: - Wake

    /// Forces the frontmost app to build and keep its accessibility tree alive.
    public func wakeUpCurrentApp() {
        // Tear down any previous observer before installing a new one.
        sleepCurrentApp()

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }

        let pid = frontmostApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Force-enable the Chromium/Electron accessibility tree. Chromium keeps its AX tree
        // off for performance and only builds it when a client sets this private attribute.
        // Cheap (~0ms even on large Electron apps), so we set it synchronously.
        // Native apps ignore the attribute (the call fails harmlessly).
        let manualAXResult = AXUIElementSetAttributeValue(
            appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue
        )
        logger.info("WakeManager: AXManualAccessibility \(manualAXResult == .success ? "enabled" : "n/a", privacy: .public) for PID \(pid)")

        var observer: AXObserver?
        let err = AXObserverCreate(pid, observerCallback, &observer)

        guard err == .success, let axObserver = observer else {
            logger.error("WakeManager: failed to create AXObserver for PID \(pid)")
            return
        }

        // FocusedUIElementChanged: register on app root (works for all apps).
        AXObserverAddNotification(axObserver, appElement, kAXFocusedUIElementChangedNotification as CFString, nil)

        // SelectedTextChanged: must be registered on the focused element itself, not the app root.
        // In Chromium/Electron, registering on the app root never fires this notification.
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focusedRaw = focusedRef, CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() {
            // Safe cast: the CFGetTypeID check above confirms this really is an AXUIElement.
            let focusedEl = unsafeBitCast(focusedRaw, to: AXUIElement.self)
            AXObserverAddNotification(axObserver, focusedEl, kAXSelectedTextChangedNotification as CFString, nil)
            logger.info("WakeManager: observer on focused element for PID \(pid)")
        } else {
            // Native apps expose focused element at app root level; this is the safe fallback.
            AXObserverAddNotification(axObserver, appElement, kAXSelectedTextChangedNotification as CFString, nil)
            logger.warning("WakeManager: focused element unavailable — observer on app root for PID \(pid)")
        }

        let source = AXObserverGetRunLoopSource(axObserver)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

        self.activeObserver = axObserver
        self.observerRunLoopSource = source
        logger.info("WakeManager: accessibility tree alive for PID \(pid)")
    }
    
    // MARK: - Sleep

    /// Removes the observer and lets the app's accessibility tree go back to sleep.
    public func sleepCurrentApp() {
        if let source = observerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            self.observerRunLoopSource = nil
        }
        
        if self.activeObserver != nil {
            self.activeObserver = nil
            logger.info("Accessibility tree put back to sleep")
        }
    }
}
