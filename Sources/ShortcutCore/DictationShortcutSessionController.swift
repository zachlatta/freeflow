import Foundation

enum DictationShortcutAction: Equatable {
    case start(RecordingTriggerMode)
    case stop
    case switchedToToggle
}

final class DictationShortcutSessionController {
    private(set) var activeMode: RecordingTriggerMode?
    private(set) var toggleStopArmed = false

    func handle(event: ShortcutEvent, isTranscribing: Bool) -> DictationShortcutAction? {
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
                return .start(.hold)
            case .holdDeactivated, .toggleDeactivated:
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
            case .holdActivated, .toggleDeactivated:
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
            case .holdActivated, .holdDeactivated:
                return nil
            }
        }
    }

    func beginManual(mode: RecordingTriggerMode) {
        activeMode = mode
        toggleStopArmed = false
    }

    func forceToggleMode() {
        activeMode = .toggle
        toggleStopArmed = false
    }

    func reset() {
        activeMode = nil
        toggleStopArmed = false
    }
}
