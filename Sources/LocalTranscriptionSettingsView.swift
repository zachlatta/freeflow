import SwiftUI

struct LocalTranscriptionSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelManager: LocalParakeetModelManager
    @State private var showsRemovalConfirmation = false
    let compact: Bool

    init(modelManager: LocalParakeetModelManager, compact: Bool = false) {
        self.modelManager = modelManager
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Use on-device transcription", isOn: localModeBinding)
                .disabled(
                    modelManager.state.isBusy
                        || (isUnavailable && !appState.localTranscriptionEnabled)
                        || appState.isRecording || appState.isTranscribing
                )

            if !compact {
                Text("Parakeet TDT 0.6B v3 runs on Apple silicon. While enabled, dictated audio and text stay on this Mac; screenshots, app context, translation, realtime streaming, Edit Mode, and language-model cleanup are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            modelStatus
                .disabled(appState.isRecording || appState.isTranscribing)
        }
        .onAppear { modelManager.refresh() }
        .confirmationDialog(
            "Remove the on-device model?",
            isPresented: $showsRemovalConfirmation
        ) {
            Button("Remove Model", role: .destructive) {
                appState.localTranscriptionEnabled = false
                modelManager.removeModel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees the model cache. You can download it again at any time.")
        }
    }

    private var localModeBinding: Binding<Bool> {
        Binding(
            get: { appState.localTranscriptionEnabled || modelManager.state.isBusy },
            set: { enabled in
                if enabled {
                    enableLocalMode()
                } else {
                    appState.localTranscriptionEnabled = false
                }
            }
        )
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch modelManager.state {
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .notInstalled:
            HStack {
                Text("Enabling this downloads and prepares a verified 459 MB model.")
                    .foregroundStyle(.secondary)
                Spacer()
                if appState.localTranscriptionEnabled {
                    Button("Download Model") { enableLocalMode() }
                }
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 5) {
                ProgressView(value: progress)
                Text("Downloading model… \(Int(progress * 100))%")
                    .foregroundStyle(.secondary)
            }
        case .verifying:
            progressLabel("Verifying model integrity…")
        case .preparing:
            progressLabel("Preparing Core ML for first use…")
        case .ready(let byteCount):
            HStack {
                Label(
                    "Model ready · \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)) on disk",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                Spacer()
                Button("Remove Model") { showsRemovalConfirmation = true }
                    .disabled(
                        modelManager.state.isBusy || appState.isRecording || appState.isTranscribing
                    )
            }
        case .failed(let message):
            HStack(alignment: .firstTextBaseline) {
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Spacer()
                Button("Try Again") { enableLocalMode() }
            }
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = modelManager.state { return true }
        return false
    }

    private func progressLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func enableLocalMode() {
        Task { @MainActor in
            if await modelManager.install() {
                appState.localTranscriptionEnabled = true
            }
        }
    }
}
