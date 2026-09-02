import SwiftUI

/// Shown when a transcript could not be delivered to the element it was
/// dictated into and is waiting on the clipboard instead. Deliberately the
/// same shape as `TranscriptionProgressPanel`: a floating, non-activating
/// panel that appears on whichever Space the user is on, without taking focus.
struct ClipboardWaitingPanel: View {
    let targetDescription: String
    let reason: String?
    let transcriptPreview: String
    let onDismiss: () -> Void

    private var explanation: String {
        "The text could not be placed in \(targetDescription), so it is waiting on your clipboard. Put the cursor where you want it and press Cmd-V. Nothing was typed anywhere else."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Transcript on the clipboard", systemImage: "doc.on.clipboard")
                .font(.headline)

            Text(explanation)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Waiting text:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(transcriptPreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                if let reason {
                    Text("Why: \(reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Button("Got It", action: onDismiss)
                        .keyboardShortcut(.defaultAction)
                    Text("the text stays on the clipboard either way")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
    }
}
