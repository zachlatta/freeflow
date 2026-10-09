import Foundation

enum DictationShortcutAction: Equatable {
    case start(RecordingTriggerMode)
    case stop
    case switchedToToggle
    /// Swallow the system key event without changing dictation state (avoids leaking characters).
    case consumeOnly
}

final class DictationShortcutSessionController {
    private(set) var activeMode: RecordingTriggerMode?
    private(set) var toggleStopArmed = false
    /// Prevents restarting dictation immediately while the stop shortcut's keys are still being released.
    private var ignoreToggleUntilComponentDeactivation = false

    // Handles the incoming shortcut event and computes the next dictation action
    func handle(event: ShortcutEvent, isTranscribing: Bool) -> DictationShortcutAction? {
        // Paste Again is handled externally; treat as no-op here.
        if event == .copyAgainTriggered { return nil }

        // Reset the ignore flag when the user releases all keys
        if event == .toggleComponentDeactivated {
            ignoreToggleUntilComponentDeactivation = false
        }

        if activeMode == nil {
            // Swallow trailing components of a stop sequence to prevent leaking characters (e.g. spaces)
            if ignoreToggleUntilComponentDeactivation {
                switch event {
                case .toggleActivated, .toggleComponentActivated, .toggleComponentInputReceived:
                    return .consumeOnly
                default:
                    break
                }
            }

            guard !isTranscribing else { return nil }
            switch event {
            case .toggleActivated:
                // Only start toggle if not ignoring due to a recent stop action
                guard !ignoreToggleUntilComponentDeactivation else { return nil }
                activeMode = .toggle
                toggleStopArmed = false
                return .start(.toggle)
            case .holdActivated:
                activeMode = .hold
                toggleStopArmed = false
                return .start(.hold)
            // Ignore deactivations and stateless toggle inputs when idle
            case .holdDeactivated, .toggleDeactivated, .toggleComponentActivated, .toggleComponentDeactivated, .toggleComponentInputReceived:
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
                toggleStopArmed = false
                return .switchedToToggle
            case .holdDeactivated:
                reset()
                return .stop
            // Ignore other activations and stateless toggle inputs in hold mode
            case .holdActivated, .toggleDeactivated, .toggleComponentActivated, .toggleComponentDeactivated, .toggleComponentInputReceived:
                return nil
            case .copyAgainTriggered:
                return nil
            }

        case .toggle:
            switch event {
            case .toggleDeactivated:
                toggleStopArmed = true
                return nil
            // Stop recording on toggle shortcut activations or stateless component inputs
            case .toggleActivated, .toggleComponentActivated, .toggleComponentInputReceived:
                // Trigger stop if toggle is armed and we are not currently ignoring events
                guard toggleStopArmed else { return nil }
                guard !ignoreToggleUntilComponentDeactivation else { return nil }
                reset()
                ignoreToggleUntilComponentDeactivation = true
                return .stop
            case .holdActivated, .holdDeactivated, .toggleComponentDeactivated:
                return nil
            case .copyAgainTriggered:
                return nil
            }
        }
    }

    // Begins a manual dictation session with the specified mode
    func beginManual(mode: RecordingTriggerMode) {
        activeMode = mode
        toggleStopArmed = false
        ignoreToggleUntilComponentDeactivation = false
    }

    // Forces the controller state into toggle mode
    func forceToggleMode() {
        activeMode = .toggle
        toggleStopArmed = false
        ignoreToggleUntilComponentDeactivation = false
    }

    // Resets the controller state to idle
    func reset() {
        activeMode = nil
        toggleStopArmed = false
    }
}
