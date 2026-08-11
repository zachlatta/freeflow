import SwiftUI
import AppKit

func imageFromDataURL(_ dataURL: String) -> NSImage? {
    guard let commaIndex = dataURL.lastIndex(of: ",") else { return nil }
    let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
    guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
    return NSImage(data: data)
}

struct PipelineDebugContentView: View {
    let statusMessage: String
    let postProcessingStatus: String
    let contextSummary: String
    let contextScreenshotStatus: String
    let contextScreenshotDataURL: String?
    /// Text just before the cursor, shown in the Smart Paste panel.
    let contextPrecedingText: String
    /// Text just after the cursor, shown in the Smart Paste panel.
    let contextFollowingText: String
    /// Text the user had selected when dictating, shown in its own debug row.
    let contextSelectedText: String
    let rawTranscript: String
    let postProcessedTranscript: String
    /// The transcript after smart-paste formatting (spacing/casing) is applied.
    let formattedTranscript: String
    let postProcessingPrompt: String
    /// Where the cursor sat in the field (e.g. start/middle/end/unknown).
    let cursorPosition: String?
    /// Which smart-paste formatting rule was applied, shown in the Smart Paste panel.
    let contextFormatRule: String?
    /// True when no surrounding text could be read (the app was "blind"); flags a failed read in the panel.
    let isBlindApp: Bool
    /// Which read method produced the surrounding text (e.g. axAPI, axWebTextMarker).
    let extractionMethod: String?
    /// App kind of the target field: "native", "webView", or "unknown".
    let appKind: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !statusMessage.isEmpty {
                debugRow(title: "Status", value: statusMessage)
            }

            if !postProcessingStatus.isEmpty {
                debugRow(title: "Post-Processing", value: postProcessingStatus)
            }

            if !postProcessingPrompt.isEmpty {
                debugRow(title: "Post-Processing Prompt", value: postProcessingPrompt, copyText: postProcessingPrompt)
            }

            if !contextSummary.isEmpty {
                debugRow(title: "Context", value: contextSummary)
            }

            if !contextScreenshotStatus.isEmpty || contextScreenshotDataURL != nil {
                screenshotSection(
                    status: contextScreenshotStatus,
                    dataURL: contextScreenshotDataURL
                )
            }

            if !contextSelectedText.isEmpty {
                debugRow(title: "Selected Text", value: contextSelectedText, copyText: contextSelectedText)
            }

            if !rawTranscript.isEmpty || !contextPrecedingText.isEmpty || !contextFollowingText.isEmpty {
                smartPasteSection()
            }

            if contextSummary.isEmpty && rawTranscript.isEmpty && postProcessedTranscript.isEmpty && postProcessingPrompt.isEmpty {
                Text("No debug data for this entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func debugRow(title: String, value: String, copyText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.bold())
            ScrollView {
                Text(value)
                    .textSelection(.enabled)
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

            if let copyText {
                Button("Copy \(title)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                }
                .font(.body)
            }
        }
    }

    private func screenshotSection(status: String, dataURL: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Context Screenshot")
                .font(.body.bold())
            Text("Status: \(status)")
                .font(.caption)
                .foregroundStyle(isScreenshotUnavailable(status) ? .red : .secondary)

            if let dataURL,
               let image = imageFromDataURL(dataURL) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 320, alignment: .center)
                        .padding(10)
                }
                .frame(maxHeight: 320)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                if let payloadBytes = screenshotPayloadBytes(dataURL: dataURL) {
                    Text("Screenshot payload: \(payloadBytes / 1024) KB (Base64)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("Open in Preview") {
                        openImageInPreview(image)
                    }
                    .font(.body)

                    Button("Copy Screenshot") {
                        copyImageToPasteboard(image)
                    }
                    .font(.body)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No screenshot image available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
            }
        }
    }

    private func screenshotPayloadBytes(dataURL: String) -> Int? {
        guard let commaIndex = dataURL.lastIndex(of: ",") else {
            return nil
        }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)?.count
    }

    private func isScreenshotUnavailable(_ status: String) -> Bool {
        let lowered = status.lowercased()
        return lowered.contains("could not") || lowered.contains("no screenshot") || lowered.contains("not available")
    }

    private func openImageInPreview(_ image: NSImage) {
        guard let imageData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: imageData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voice-to-text-context-screenshot.png", isDirectory: false)
        do {
            try pngData.write(to: tempURL)
            NSWorkspace.shared.open(tempURL)
        } catch {
            return
        }
    }

    private func copyImageToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    // MARK: - Smart Paste Section

    /// Builds the Smart Paste panel: app type, how text was read, and the before/after context around the cursor.
    private func smartPasteSection() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Smart Paste Formatting")
                .font(.body.bold())
            
            // Build human-readable labels via the shared helper.
            // This panel passes empty strings (never nil), so a failed read is flagged by isBlindApp.
            // "Has text" needs a real character; a lone space or newline does not count.
            let hasText = contextPrecedingText.contains(where: { !$0.isWhitespace })
                || contextFollowingText.contains(where: { !$0.isWhitespace })
            let appTypeLabel = ContextDebugLabels.appType(appKind)
            let readLabel = ContextDebugLabels.howTextWasRead(extractionMethod)
            let detected = ContextDebugLabels.surroundingText(hasText: hasText, readFailed: isBlindApp)

            let combined = """
            App Type: \(appTypeLabel)
            How text was read: \(readLabel)
            Text around cursor: \(detected)
            Cursor position: \(cursorPosition ?? "unknown")

            Preceding Text: "\(contextPrecedingText)"
            Raw Transcript: "\(rawTranscript)"
            Raw LLM Output: "\(postProcessedTranscript)"
            Formatted Output: "\(formattedTranscript)"
            Following Text: "\(contextFollowingText)"

            Resulting Text: "\(contextPrecedingText)\(formattedTranscript)\(contextFollowingText)"
            Smart paste: \(ContextDebugLabels.ruleSummary(contextFormatRule))
            """
            
            ScrollView {
                Text(combined)
                    .textSelection(.enabled)
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
            
            Button("Copy Smart Paste Log") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(combined, forType: .string)
            }
            .font(.body)
        }
    }
}
