import Foundation
import AppKit
import UniformTypeIdentifiers

/// Exports a pipeline history item as a self-contained ZIP.
///
/// ZIP contents:
///   case.json       – metadata, transcripts, context, prompts, settings
///   screenshot.jpg  – JPEG decoded from context screenshot data URL (if available)
///   audio.*         – original audio recording (if available)
struct TestCaseExporter {

    enum ExportError: Error, LocalizedError {
        case tempDirectoryCreationFailed(underlying: Error?)
        case zipFailed(Int32)
        case screenshotDecodeFailed

        var errorDescription: String? {
            switch self {
            case .tempDirectoryCreationFailed(let underlying):
                if let underlying {
                    return "Could not create temporary export directory: \(underlying.localizedDescription)"
                }
                return "Could not create temporary export directory"
            case .zipFailed(let code): return "zip exited with code \(code)"
            case .screenshotDecodeFailed: return "Could not decode screenshot data URL"
            }
        }
    }

    /// Presents a NSSavePanel and writes the ZIP to the chosen location.
    /// Must be called on the main thread.
    @MainActor
    static func exportWithSavePanel(
        item: PipelineHistoryItem,
        audioDirURL: URL
    ) {
        let timestamp = isoTimestamp(from: item.timestamp)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.zip]
        panel.nameFieldStringValue = "freeflow-case-\(timestamp).zip"
        panel.title = "Export Test Case"
        panel.message = "Choose where to save the test case ZIP."
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try writeZip(
                        item: item,
                        audioDirURL: audioDirURL,
                        timestamp: timestamp,
                        to: destination
                    )
                } catch {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                }
            }
        }
    }

    // MARK: - Private

    private static func writeZip(
        item: PipelineHistoryItem,
        audioDirURL: URL,
        timestamp: String,
        to destination: URL
    ) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("freeflow-case-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            throw ExportError.tempDirectoryCreationFailed(underlying: error)
        }

        // Screenshot
        var screenshotPath: String? = nil
        if let dataURL = item.contextScreenshotDataURL {
            guard let imageData = decodeDataURL(dataURL) else { throw ExportError.screenshotDecodeFailed }
            let ext = dataURL.hasPrefix("data:image/png") ? "png" : "jpg"
            try imageData.write(to: tempDir.appendingPathComponent("screenshot.\(ext)"))
            screenshotPath = "./screenshot.\(ext)"
        }

        // Audio
        var audioPath: String? = nil
        if let audioFileName = item.audioFileName {
            let src = audioDirURL.appendingPathComponent(audioFileName)
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: tempDir.appendingPathComponent(audioFileName))
                audioPath = "./\(audioFileName)"
            }
        }

        // Build pipeline dict
        var pipeline: [String: Any] = [
            "raw_transcript": item.rawTranscript,
            "post_processed_transcript": item.postProcessedTranscript,
            "context_summary": item.contextSummary,
            "context_prompt": item.contextPrompt ?? "",
            "post_processing_prompt": item.postProcessingPrompt ?? "",
            "post_processing_status": item.postProcessingStatus,
            "screenshot_status": item.contextScreenshotStatus
        ]
        if let path = screenshotPath { pipeline["screenshot_path"] = path }
        if let path = audioPath { pipeline["audio_path"] = path }

        let json: [String: Any] = [
            "id": "case-\(timestamp)",
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "intent": item.intent.rawValue,
            "run_uuid": item.id.uuidString,
            "run_timestamp": ISO8601DateFormatter().string(from: item.timestamp),
            "metadata": [
                "app_name": item.contextAppName ?? "",
                "bundle_identifier": item.contextBundleIdentifier ?? "",
                "window_title": item.contextWindowTitle ?? "",
                "selected_text": item.selectedText ?? ""
            ] as [String: Any],
            "pipeline": pipeline,
            "settings": [
                "custom_vocabulary": item.customVocabulary,
                "system_prompt": item.systemPrompt ?? "",
                "context_system_prompt": item.contextSystemPrompt ?? ""
            ] as [String: Any]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: tempDir.appendingPathComponent("case.json"))

        try? fm.removeItem(at: destination)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", destination.path, "."]
        process.currentDirectoryURL = tempDir
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ExportError.zipFailed(process.terminationStatus) }
    }

    private static func decodeDataURL(_ dataURL: String) -> Data? {
        guard let commaIndex = dataURL.lastIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    private static func isoTimestamp(from date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
