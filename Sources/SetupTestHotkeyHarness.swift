import Foundation

@MainActor
final class SetupTestHotkeyHarness: ObservableObject {
    private let hotkeyManager = HotkeyManager()
    private let sessionController = DictationShortcutSessionController()

    var isTranscribing = false
    var onAction: ((DictationShortcutAction) -> Void)?

    func start(configuration: ShortcutConfiguration) {
        hotkeyManager.onShortcutEvent = { [weak self] event in
            guard let self else { return }
            let action = self.sessionController.handle(event: event, isTranscribing: self.isTranscribing)
            guard let action else { return }
            DispatchQueue.main.async {
                self.onAction?(action)
            }
        }
        hotkeyManager.start(configuration: configuration)
    }

    func stop() {
        hotkeyManager.stop()
        onAction = nil
        sessionController.reset()
        isTranscribing = false
    }

    func resetSession() {
        sessionController.reset()
    }
}
