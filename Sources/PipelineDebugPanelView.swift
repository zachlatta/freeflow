import SwiftUI

struct PipelineDebugPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()

            PipelineDebugContentView(
                statusMessage: appState.debugStatusMessage,
                postProcessingStatus: appState.lastPostProcessingStatus,
                contextSummary: appState.lastContextSummary,
                contextScreenshotStatus: appState.lastContextScreenshotStatus,
                contextScreenshotDataURL: appState.lastContextScreenshotDataURL,
                rawTranscript: appState.lastRawTranscript,
                postProcessedTranscript: appState.lastPostProcessedTranscript,
                postProcessingPrompt: appState.lastPostProcessingPrompt
            )

            if appState.lastContextSummary.isEmpty && appState.lastRawTranscript.isEmpty {
                Text("Run a dictation pass to populate debug output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 620, height: 640, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pipeline Debug")
                        .font(.title3)
                    Text("Live data for the transcription + post-processing pipeline.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Export Test Case…") {
                    exportTestCase()
                }
                .font(.body)
                .disabled(appState.pipelineHistory.first == nil)
            }
        }
    }

    private func exportTestCase() {
        guard let item = appState.pipelineHistory.first else { return }
        TestCaseExporter.exportWithSavePanel(
            item: item,
            audioDirURL: AppState.audioStorageDirectory()
        )
    }
}
