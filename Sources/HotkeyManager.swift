import Cocoa

final class HotkeyManager {
    private let backend = GlobalShortcutBackend()
    private var configuration = ShortcutConfiguration(
        hold: .defaultHold,
        toggle: .defaultToggle
    )
    private var inputState = ShortcutInputState()

    // Callback triggered on shortcut events; returns true to consume the system key event
    var onShortcutEvent: ((ShortcutEvent) -> Bool)?
    var onEscapeKeyPressed: (() -> Bool)?

    var currentPressedModifiers: ShortcutModifiers {
        inputState.currentModifiers
    }

    var hasPressedShortcutInputs: Bool {
        inputState.hasPressedShortcutInputs(configuration: configuration)
    }

    func start(configuration: ShortcutConfiguration) throws {
        stop()
        self.configuration = configuration
        backend.onInputEvent = { [weak self] event in
            self?.handleInputEvent(event) ?? .passthrough
        }
        backend.onEscapeKeyPressed = { [weak self] in
            self?.onEscapeKeyPressed?() ?? false
        }
        do {
            try backend.start()
        } catch {
            backend.onInputEvent = nil
            backend.onEscapeKeyPressed = nil
            inputState = ShortcutInputState()
            throw error
        }
    }

    func stop() {
        backend.stop()
        backend.onInputEvent = nil
        backend.onEscapeKeyPressed = nil
        inputState = ShortcutInputState()
    }

    deinit {
        stop()
    }

    // Processes raw input events, triggers callbacks, and determines if the event should be consumed
    private func handleInputEvent(_ event: ShortcutInputEvent) -> ShortcutConsumeDecision {
        let result = ShortcutMatcher.reduce(
            state: inputState,
            event: event,
            configuration: configuration
        )
        inputState = result.state
        var shouldConsume = false
        for event in result.emittedEvents {
            if onShortcutEvent?(event) == true {
                shouldConsume = true
            }
        }
        return (result.consumeDecision == .consume || shouldConsume) ? .consume : .passthrough
    }
}
