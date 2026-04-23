import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private let storage = SharedStorage.shared
    private let observer = DarwinObserver()
    private var hostingController: UIHostingController<KeyboardView>?
    private var pendingCommandID: String?
    private var insertedResultID: String?
    private var waitingForPrimeSince: Date?

    override func viewDidLoad() {
        super.viewDidLoad()

        model.onToggleRecording = { [weak self] in self?.handleMicTap() }
        model.onAdvanceKeyboard = { [weak self] in self?.advanceToNextInputMode() }
        model.onBackspace = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        model.onBackspaceHold = { [weak self] in
            guard let self else { return }
            for _ in 0..<20 { self.textDocumentProxy.deleteBackward() }
        }
        model.onOpenApp = { [weak self] in self?.openFreeFlowApp() }

        let hosting = UIHostingController(rootView: KeyboardView(model: model))
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
        self.hostingController = hosting

        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        observer.add(name: DarwinNotifications.state) { [weak self] in self?.refresh() }
        observer.add(name: DarwinNotifications.result) { [weak self] in self?.consumeResultIfReady() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        insertedResultID = storage.readResult()?.id
        refresh()
    }

    private func refresh() {
        guard hasFullAccess else {
            model.state = .idle
            model.warning = "Enable Full Access in Settings → General → Keyboard → Keyboards → FreeFlow."
            model.canTapMic = false
            return
        }
        if storage.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.state = .idle
            model.warning = "No API key. Open FreeFlow and paste your Groq key."
            model.canTapMic = false
            return
        }
        model.warning = nil
        model.canTapMic = true

        let state = storage.recorderState
        let primed = storage.isSessionPrimed

        switch state {
        case "recording":
            model.state = .recording
        case "processing":
            model.state = .transcribing
        default:
            if let waiting = waitingForPrimeSince, Date().timeIntervalSince(waiting) < 8, !primed {
                model.state = .opening
            } else if primed {
                waitingForPrimeSince = nil
                model.state = .idlePrimed(expiresAt: storage.sessionPrimedUntil)
            } else {
                waitingForPrimeSince = nil
                model.state = .idleNotPrimed
            }
        }

        consumeResultIfReady()
    }

    private func handleMicTap() {
        guard hasFullAccess,
              !storage.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            refresh()
            return
        }

        if case .recording = model.state {
            pendingCommandID = storage.issueCommand(action: "stop")
            model.state = .transcribing
            scheduleTranscriptionTimeout()
            return
        }
        if case .transcribing = model.state { return }

        if storage.isSessionPrimed {
            pendingCommandID = storage.issueCommand(action: "start")
            model.state = .recording
            return
        }

        tryPrime()
    }

    private func scheduleTranscriptionTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, case .transcribing = self.model.state else { return }
            self.pendingCommandID = nil
            self.refresh()
        }
    }

    private func tryPrime() {
        waitingForPrimeSince = Date()
        model.state = .opening
        DarwinNotifications.post(DarwinNotifications.prime)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            if case .opening = self.model.state, !self.storage.isSessionPrimed {
                self.openFreeFlowApp()
            }
        }
    }

    private func openFreeFlowApp() {
        guard let url = URL(string: "freeflow://prime") else { return }
        extensionContext?.open(url, completionHandler: { [weak self] success in
            guard !success else { return }
            DispatchQueue.main.async { self?.tryOpenViaResponderChain(url: url) }
        })
    }

    @discardableResult
    private func tryOpenViaResponderChain(url: URL) -> Bool {
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return true
            }
            responder = r.next
        }
        return false
    }

    private func consumeResultIfReady() {
        guard let result = storage.readResult() else { return }
        guard result.id != insertedResultID else { return }
        guard let pending = pendingCommandID, pending == result.id else {
            insertedResultID = result.id
            return
        }
        insertedResultID = result.id
        pendingCommandID = nil

        if !result.error.isEmpty {
            model.state = .error(result.error)
            return
        }
        if !result.text.isEmpty {
            textDocumentProxy.insertText(result.text)
            model.state = .success("Inserted")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.refresh()
            }
        } else {
            model.state = .error("Nothing transcribed — try again.")
        }
    }
}
