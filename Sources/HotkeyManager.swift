import Cocoa

final class HotkeyManager {
    private let backend = GlobalShortcutBackend()
    private var configuration = ShortcutConfiguration(
        hold: .defaultHold,
        toggle: .defaultToggle
    )
    private var inputState = ShortcutInputState()

    var onShortcutEvent: ((ShortcutEvent) -> Void)?
    var onEscapeKeyPressed: (() -> Bool)?
    /// Asked on each new Fn press whether the hold binding should consume it
    /// instead of passing it through to macOS (see `ShortcutMatcher.reduce`).
    var shouldClaimFnHoldPress: (() -> Bool)?

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

    private func handleInputEvent(_ event: ShortcutInputEvent) -> ShortcutConsumeDecision {
        let result = ShortcutMatcher.reduce(
            state: inputState,
            event: event,
            configuration: configuration,
            claimFnHoldPress: shouldClaimFnHoldPress?() ?? false
        )
        inputState = result.state
        for event in result.emittedEvents {
            onShortcutEvent?(event)
        }
        return result.consumeDecision
    }
}
