import Foundation

enum DictationShortcutAction: Equatable {
    case start(RecordingTriggerMode)
    case stop
    case switchedToToggle
    /// A short hold-shortcut press ended. Keep the session alive for this long
    /// in case a second press latches it, then call `handleDoubleTapTimeout`.
    case awaitDoubleTap(TimeInterval)
}

final class DictationShortcutSessionController {
    static let doubleTapMaxPressDuration: TimeInterval = 0.3
    static let doubleTapWindow: TimeInterval = 0.3

    private(set) var activeMode: RecordingTriggerMode?
    private(set) var toggleStopArmed = false
    private var holdStartedAt: TimeInterval?
    private var awaitingDoubleTap = false
    private var latchedByDoubleTap = false
    private var holdStopArmed = false

    func handle(
        event: ShortcutEvent,
        isTranscribing: Bool,
        doubleTapToToggleEnabled: Bool = false,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> DictationShortcutAction? {
        // Paste Again is handled before this controller runs; if it ever
        // reaches here, treat as a no-op so dictation state is unaffected.
        if event == .copyAgainTriggered { return nil }

        if activeMode == nil {
            guard !isTranscribing else { return nil }
            switch event {
            case .toggleActivated:
                activeMode = .toggle
                toggleStopArmed = false
                return .start(.toggle)
            case .holdActivated:
                activeMode = .hold
                toggleStopArmed = false
                holdStartedAt = now
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
                forceToggleMode()
                return .switchedToToggle
            case .holdDeactivated:
                if doubleTapToToggleEnabled,
                   let holdStartedAt,
                   now - holdStartedAt <= Self.doubleTapMaxPressDuration {
                    awaitingDoubleTap = true
                    return .awaitDoubleTap(Self.doubleTapWindow)
                }
                reset()
                return .stop
            case .holdActivated:
                guard awaitingDoubleTap else { return nil }
                forceToggleMode()
                latchedByDoubleTap = true
                // The toggle shortcut was never pressed in this session, so
                // its first press must stop rather than wait to be armed.
                toggleStopArmed = true
                return .switchedToToggle
            case .toggleDeactivated:
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
                holdStopArmed = latchedByDoubleTap
                return nil
            case .holdActivated:
                guard holdStopArmed else { return nil }
                reset()
                return .stop
            case .copyAgainTriggered:
                return nil
            }
        }
    }

    func handleDoubleTapTimeout() -> DictationShortcutAction? {
        guard awaitingDoubleTap else { return nil }
        reset()
        return .stop
    }

    func beginManual(mode: RecordingTriggerMode) {
        reset()
        activeMode = mode
    }

    func forceToggleMode() {
        reset()
        activeMode = .toggle
    }

    func reset() {
        activeMode = nil
        toggleStopArmed = false
        holdStartedAt = nil
        awaitingDoubleTap = false
        latchedByDoubleTap = false
        holdStopArmed = false
    }
}
