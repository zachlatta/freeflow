import SwiftUI

struct TranscriptionProgressPanel: View {
    let audioPath: String
    let onDismiss: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Transcribing in background", systemImage: "waveform.badge.exclamationmark")
                .font(.headline)

            Text("With local processing, this can take as long as the recording — or longer under load. You can keep working; the result will paste when ready.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Audio already saved — safe to cancel if needed:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(audioPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Keep Waiting", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Cancel Transcription", role: .destructive, action: onCancel)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
    }
}
