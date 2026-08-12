import Foundation

enum DictationShortcutAction: Equatable {
    case start(RecordingTriggerMode)
    case stop
    case switchedToToggle
}

final class DictationShortcutSessionController {
    /// Tapping the hold shortcut twice in quick succession latches into toggle
    /// mode, so a long dictation does not require holding the key down.
    static let defaultDoubleTapWindow: TimeInterval = 0.4

    var doubleTapLatchEnabled: Bool
    var doubleTapWindow: TimeInterval

    /// Injectable clock so the double-tap window is testable without sleeping.
    private let now: () -> Date

    private(set) var activeMode: RecordingTriggerMode?
    private(set) var toggleStopArmed = false

    /// When the hold shortcut was last released. Deliberately *not* cleared by
    /// `reset()`: the gap that makes a double tap spans two sessions, and
    /// `reset()` runs between them once the first tap's recording is committed.
    private var lastHoldReleaseAt: Date?

    /// True when toggle mode was entered by double-tapping the hold shortcut.
    /// Such a session is also stopped by the hold shortcut, since that is the
    /// only key the speaker touched.
    private(set) var toggleEnteredFromHold = false

    init(
        doubleTapLatchEnabled: Bool = true,
        doubleTapWindow: TimeInterval = DictationShortcutSessionController.defaultDoubleTapWindow,
        now: @escaping () -> Date = Date.init
    ) {
        self.doubleTapLatchEnabled = doubleTapLatchEnabled
        self.doubleTapWindow = doubleTapWindow
        self.now = now
    }

    func handle(event: ShortcutEvent, isTranscribing: Bool) -> DictationShortcutAction? {
        // Paste Again is handled before this controller runs; if it ever
        // reaches here, treat as a no-op so dictation state is unaffected.
        if event == .copyAgainTriggered { return nil }

        if activeMode == nil {
            // A double tap is allowed to latch even while the first tap's
            // (near-empty) clip is still transcribing. Blocking it there would
            // swallow the second tap and leave the speaker with nothing.
            if event == .holdActivated, isDoubleTap() {
                activeMode = .toggle
                toggleEnteredFromHold = true
                toggleStopArmed = false
                lastHoldReleaseAt = nil
                return .start(.toggle)
            }

            guard !isTranscribing else { return nil }
            switch event {
            case .toggleActivated:
                activeMode = .toggle
                toggleEnteredFromHold = false
                toggleStopArmed = false
                return .start(.toggle)
            case .holdActivated:
                activeMode = .hold
                toggleStopArmed = false
                return .start(.hold)
            case .holdDeactivated, .toggleDeactivated:
                return nil
            case .copyAgainTriggered:
                return nil
            }
        }

        guard let mode = activeMode else { return nil }

        switch mode {
        case .hold:
            switch event {
            case .toggleActivated:
                activeMode = .toggle
                toggleEnteredFromHold = false
                toggleStopArmed = false
                return .switchedToToggle
            case .holdDeactivated:
                reset()
                lastHoldReleaseAt = now()
                return .stop
            case .holdActivated, .toggleDeactivated:
                return nil
            case .copyAgainTriggered:
                return nil
            }

        case .toggle:
            switch event {
            case .toggleDeactivated:
                toggleStopArmed = true
                return nil
            case .toggleActivated:
                guard toggleStopArmed else { return nil }
                reset()
                return .stop
            case .holdDeactivated:
                // Releasing the second tap must not end the session; it arms
                // the next press to end it.
                guard toggleEnteredFromHold else { return nil }
                toggleStopArmed = true
                return nil
            case .holdActivated:
                guard toggleEnteredFromHold, toggleStopArmed else { return nil }
                reset()
                return .stop
            case .copyAgainTriggered:
                return nil
            }
        }
    }

    func beginManual(mode: RecordingTriggerMode) {
        activeMode = mode
        toggleEnteredFromHold = false
        toggleStopArmed = false
    }

    func forceToggleMode() {
        activeMode = .toggle
        toggleEnteredFromHold = false
        toggleStopArmed = false
    }

    func reset() {
        activeMode = nil
        toggleEnteredFromHold = false
        toggleStopArmed = false
    }

    private func isDoubleTap() -> Bool {
        guard doubleTapLatchEnabled, let last = lastHoldReleaseAt else { return false }
        return now().timeIntervalSince(last) <= doubleTapWindow
    }
}
