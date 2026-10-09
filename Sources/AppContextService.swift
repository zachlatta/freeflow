import Foundation
import ApplicationServices
import AppKit

struct AppSelectionSnapshot {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
}

struct AppContext {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let currentActivity: String
    let contextSystemPrompt: String?
    let contextPrompt: String?
    let screenshotDataURL: String?
    let screenshotMimeType: String?
    let screenshotError: String?

    var contextSummary: String {
        currentActivity
    }

    var summaryForPostProcessing: String {
        ContextInferenceFailure.usableSummary(currentActivity)
    }
}

enum DesktopScreenshotFallbackPreference {
    static let storageKey = "context_desktop_screenshot_fallback_enabled"

    static func load(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: storageKey) == nil
            ? true
            : defaults.bool(forKey: storageKey)
    }

    static func save(_ enabled: Bool, to defaults: UserDefaults) {
        defaults.set(enabled, forKey: storageKey)
    }
}

final class AppContextService {
    static let defaultContextModel = "qwen/qwen3.8-27b"
    static let defaultContextPrompt = """
You are a context synthesis assistant for a speech-to-text pipeline.
Given app/window metadata and an optional screenshot, output exactly two sentences that describe what the user is doing right now and the likely writing intent in the current window.
Prioritize concrete details only from the context: for email, identify recipients, subject or thread cues, and whether the user is replying or composing; for terminal/code/text work, identify the active command, file, document title, or topic.
If details are missing, state uncertainty instead of inventing facts.
Return only two sentences, no labels, no markdown, no extra commentary.
"""
    static let defaultContextPromptDate = "2026-02-24"
    static let defaultScreenshotMaxDimension: CGFloat = 1024

    private let apiKey: String
    private let baseURL: String
    private let customContextPrompt: String
    private let contextModel: String
    private let maxScreenshotDataURILength = 500_000
    private let screenshotCompressionPrimary = 0.5
    private let screenshotMaxDimension: CGFloat
    private let desktopScreenshotFallbackEnabled: Bool
    private var contextRequestTimeoutSeconds: TimeInterval {
        let override = UserDefaults.standard.double(forKey: "context_request_timeout_seconds")
        return override > 0 ? override : 20
    }

    init(
        apiKey: String,
        baseURL: String = "https://api.groq.com/openai/v1",
        customContextPrompt: String = "",
        contextModel: String = AppContextService.defaultContextModel,
        screenshotMaxDimension: CGFloat = AppContextService.defaultScreenshotMaxDimension,
        desktopScreenshotFallbackEnabled: Bool = true
    ) {
        self.apiKey = apiKey
        self.desktopScreenshotFallbackEnabled = desktopScreenshotFallbackEnabled
        self.baseURL = baseURL
        self.customContextPrompt = customContextPrompt
        let trimmedModel = contextModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.contextModel = trimmedModel.isEmpty ? Self.defaultContextModel : trimmedModel
        self.screenshotMaxDimension = screenshotMaxDimension > 0
            ? screenshotMaxDimension
            : AppContextService.defaultScreenshotMaxDimension
    }

    private func resolveContextPrompt() -> String {
        let trimmedPrompt = customContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty ? Self.defaultContextPrompt : trimmedPrompt
    }

    func collectSelectionSnapshot() -> AppSelectionSnapshot {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppSelectionSnapshot(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil
            )
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        return AppSelectionSnapshot(
            appName: frontmostApp.localizedName,
            bundleIdentifier: frontmostApp.bundleIdentifier,
            windowTitle: focusedWindowTitle(from: appElement) ?? frontmostApp.localizedName,
            selectedText: rawSelectedText(from: appElement)
        )
    }

    func collectContext() async -> AppContext {
        let contextSystemPrompt = resolveContextPrompt()

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil,
                currentActivity: "You are dictating in an unrecognized context.",
                contextSystemPrompt: contextSystemPrompt,
                contextPrompt: nil,
                screenshotDataURL: nil,
                screenshotMimeType: nil,
                screenshotError: "No frontmost application"
            )
        }

        let appName = frontmostApp.localizedName
        let bundleIdentifier = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

        let windowTitle = focusedWindowTitle(from: appElement) ?? appName
        let selectedText = selectedText(from: appElement)
        let screenshot = captureActiveWindowScreenshot(
            processIdentifier: frontmostApp.processIdentifier,
            appElement: appElement,
            focusedWindowTitle: windowTitle
        )
        let currentActivity: String
        let contextPrompt: String?
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch await inferActivityWithLLM(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                selectedText: selectedText,
                screenshotDataURL: screenshot.dataURL,
                contextSystemPrompt: contextSystemPrompt
            ) {
            case .success(let result):
                currentActivity = result.activity
                contextPrompt = result.prompt
            case .failure(let error):
                currentActivity = error.summary
                contextPrompt = nil
            }
        } else {
            currentActivity = ContextInferenceFailure.missingAPIKey.summary
            contextPrompt = nil
        }

        return AppContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: selectedText,
            currentActivity: currentActivity,
            contextSystemPrompt: contextSystemPrompt,
            contextPrompt: contextPrompt,
            screenshotDataURL: screenshot.dataURL,
            screenshotMimeType: screenshot.mimeType,
            screenshotError: screenshot.error
        )
    }

    private func inferActivityWithLLM(
        appName: String?,
        bundleIdentifier: String?,
        windowTitle: String?,
        selectedText: String?,
        screenshotDataURL: String?,
        contextSystemPrompt: String
    ) async -> Result<(activity: String, prompt: String), ContextInferenceFailure> {
        let attempts: [(model: String, screenshotDataURL: String?)] =
            if let screenshotDataURL {
                [
                    (contextModel, screenshotDataURL),
                    (contextModel, nil)
                ]
            } else {
                [
                    (contextModel, nil)
                ]
            }

        var lastFailure = ContextInferenceFailure.emptySummary
        for attempt in attempts {
            switch await inferActivityWithLLM(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                selectedText: selectedText,
                screenshotDataURL: attempt.screenshotDataURL,
                contextSystemPrompt: contextSystemPrompt,
                model: attempt.model
            ) {
            case .success(let inferred): return .success(inferred)
            case .failure(let error):
                lastFailure = error
                // Removing an image cannot repair auth, a missing model, or
                // throttling. Avoid sending the same failing request twice.
                if case .httpStatus(let status) = error,
                   [401, 403, 404, 429].contains(status) { return .failure(error) }
            }
        }

        return .failure(lastFailure)
    }

    private func inferActivityWithLLM(
        appName: String?,
        bundleIdentifier: String?,
        windowTitle: String?,
        selectedText: String?,
        screenshotDataURL: String?,
        contextSystemPrompt: String,
        model: String
    ) async -> Result<(activity: String, prompt: String), ContextInferenceFailure> {
        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = contextRequestTimeoutSeconds
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let metadata = """
App: \(appName ?? "Unknown")
Bundle ID: \(bundleIdentifier ?? "Unknown")
Window: \(windowTitle ?? "Unknown")
Selected text: \(selectedText ?? "None")
"""

            let textOnlyPrompt = "Analyze the context and infer the user's current activity in exactly two sentences.\n\n\(metadata)"
            var userMessageDescription: String
            var userMessage: Any = textOnlyPrompt

            if let screenshotDataURL {
                userMessageDescription = "[screenshot attached]\nAnalyze the screenshot plus metadata to infer current activity.\n\(metadata)"
                userMessage = [
                    [
                        "type": "text",
                        "text": "Analyze the screenshot plus metadata to infer current activity."
                    ],
                    [
                        "type": "text",
                        "text": metadata
                    ],
                    [
                        "type": "image_url",
                        "image_url": ["url": screenshotDataURL]
                    ]
                ]
            } else {
                userMessageDescription = textOnlyPrompt
            }

            let fullPrompt = "Model: \(model)\n\n[System]\n\(contextSystemPrompt)\n[User]\n\(userMessageDescription)"

            var payload: [String: Any] = [
                "model": model,
                "temperature": 0.2,
                "messages": [
                    ["role": "system", "content": contextSystemPrompt],
                    ["role": "user", "content": userMessage]
                ]
            ]

            payload.merge(Self.inferenceRequestOptions(for: model)) { _, option in option }

            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let (data, response) = try await LLMAPITransport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            return Self.inferenceResult(data: data, status: httpResponse.statusCode, model: model, prompt: fullPrompt)
        } catch {
            if (error as? URLError)?.code == .timedOut { return .failure(.timeout) }
            return .failure(.network)
        }
    }

    static func inferenceRequestOptions(for model: String) -> [String: Any] {
        // Two sentences need a small completion budget. Leaving this unset
        // can reserve more output tokens than Groq's free-tier TPM limit.
        var options: [String: Any] = ["max_completion_tokens": 512]
        let config = ModelConfiguration.config(for: model)
        if let effort = config.reasoningEffort { options["reasoning_effort"] = effort }
        if let include = config.includeReasoning { options["include_reasoning"] = include }
        return options
    }

    static func inferenceResult(
        data: Data, status: Int, model: String, prompt: String
    ) -> Result<(activity: String, prompt: String), ContextInferenceFailure> {
        guard status == 200 else { return .failure(.httpStatus(status)) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return .failure(.invalidResponse)
        }
        guard let activity = activitySummary(from: content, model: model) else {
            return .failure(.emptySummary)
        }
        return .success((activity: activity, prompt: prompt))
    }

    static func activitySummary(from rawContent: String, model: String) -> String? {
        var content = rawContent
        if ModelConfiguration.config(for: model).shouldStripThinkTags {
            content = ModelConfiguration.stripThinkTags(content)
        }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return normalizedActivitySummary(cleaned)
    }

    private static func normalizedActivitySummary(_ value: String) -> String {
        let sentences = value
            .split(whereSeparator: { $0 == "." || $0 == "。" || $0 == "!" || $0 == "?" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.count <= 2 {
            return value
        }

        let firstTwo = sentences.prefix(2)
        return firstTwo.joined(separator: ". ") + "."
    }

    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        guard let focusedWindow = accessibilityElement(from: appElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }

        if let windowTitle = accessibilityString(from: focusedWindow, attribute: kAXTitleAttribute as CFString) {
            return trimmedText(windowTitle)
        }

        return nil
    }

    private func selectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           let selectedText = accessibilityString(from: focusedElement, attribute: kAXSelectedTextAttribute as CFString) {
            return trimmedText(selectedText)
        }

        if let selectedText = accessibilityString(from: appElement, attribute: kAXSelectedTextAttribute as CFString) {
            return trimmedText(selectedText)
        }

        return nil
    }

    private func rawSelectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           let selectedText = accessibilityRawString(from: focusedElement, attribute: kAXSelectedTextAttribute as CFString) {
            return selectedText
        }

        if let selectedText = accessibilityRawString(from: appElement, attribute: kAXSelectedTextAttribute as CFString) {
            return selectedText
        }

        return nil
    }

    private func accessibilityElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func accessibilityString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return trimmedText(stringValue)
    }

    private func accessibilityRawString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue.isEmpty ? nil : stringValue
    }

    private func accessibilityPoint(from element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(rawValue, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func accessibilitySize(from element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(rawValue, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func captureActiveWindowScreenshot(
        processIdentifier: pid_t,
        appElement: AXUIElement,
        focusedWindowTitle: String?
    ) -> (dataURL: String?, mimeType: String?, error: String?) {
        if !CGPreflightScreenCaptureAccess() {
            return (
                nil,
                nil,
                "Screen recording permission not granted. Enable in System Settings > Privacy & Security > Screen Recording."
            )
        }

        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]

        guard let windows else {
            return (nil, nil, "Unable to read window list")
        }

        let ownerPIDKey = kCGWindowOwnerPID as String
        let layerKey = kCGWindowLayer as String
        let onScreenKey = kCGWindowIsOnscreen as String
        let windowIDKey = kCGWindowNumber as String
        let boundsKey = kCGWindowBounds as String
        let nameKey = kCGWindowName as String

        struct CandidateWindow {
            let id: CGWindowID
            let layer: Int
            let area: Int
            let bounds: CGRect?
            let name: String?
        }

        let candidateWindows = windows.compactMap { windowInfo -> CandidateWindow? in
            guard let ownerPID = windowInfo[ownerPIDKey] as? Int,
                  ownerPID == processIdentifier else {
                return nil
            }
            guard let isOnScreen = windowInfo[onScreenKey] as? Bool, isOnScreen else { return nil }
            guard let windowIDValue = windowInfo[windowIDKey] as? Int else { return nil }
            let layer = (windowInfo[layerKey] as? Int) ?? 0
            let bounds = boundsRect(windowInfo[boundsKey])
            let width = bounds?.width ?? 1
            let height = bounds?.height ?? 1
            let area = Int(width * height)
            let name = trimmedText(windowInfo[nameKey] as? String)

            return CandidateWindow(
                id: CGWindowID(windowIDValue),
                layer: layer,
                area: area,
                bounds: bounds,
                name: name
            )
        }

        if let focusedWindowBounds = focusedWindowBounds(from: appElement), !focusedWindowBounds.isNull {
            if let activeWindow = candidateWindows
                .compactMap({ candidate -> (CandidateWindow, CGFloat)? in
                    guard let candidateBounds = candidate.bounds else { return nil }
                    let intersection = candidateBounds.intersection(focusedWindowBounds)
                    guard !intersection.isNull else { return nil }
                    let overlap = intersection.width * intersection.height
                    return (candidate, overlap)
                })
                .sorted(by: { lhs, rhs in
                    if lhs.0.layer == rhs.0.layer {
                        return lhs.1 > rhs.1
                    }
                    return lhs.0.layer < rhs.0.layer
                })
                    .first?.0 {
                if let dataURL = captureWindowImage(
                    windowID: activeWindow.id,
                    fileType: .jpeg,
                    mimeType: "image/jpeg",
                    compression: screenshotCompressionPrimary,
                    maxDimension: screenshotMaxDimension
                ) {
                    return (dataURL, "image/jpeg", nil)
                }
            }

            if let focusedWindowTitle,
               let activeWindow = candidateWindows
                   .filter({ candidate in
                       let normalizedName = candidate.name?
                           .lowercased()
                           .trimmingCharacters(in: .whitespacesAndNewlines)
                       let normalizedTarget = focusedWindowTitle
                           .lowercased()
                           .trimmingCharacters(in: .whitespacesAndNewlines)
                       guard let normalizedName, !normalizedName.isEmpty,
                             !normalizedTarget.isEmpty else {
                           return false
                       }

                       return normalizedName == normalizedTarget || normalizedName.contains(normalizedTarget)
                   })
                   .sorted(by: { lhs, rhs in
                       if lhs.layer == rhs.layer {
                           return lhs.area > rhs.area
                       }
                       return lhs.layer < rhs.layer
                   })
                   .first {
                if let dataURL = captureWindowImage(
                    windowID: activeWindow.id,
                    fileType: .jpeg,
                    mimeType: "image/jpeg",
                    compression: screenshotCompressionPrimary,
                    maxDimension: screenshotMaxDimension
                ) {
                    return (dataURL, "image/jpeg", nil)
                }
            }
        }

        return captureDesktopFallback {
            captureDesktopScreenshot()
        }
    }

    // Keep the preference boundary ahead of all desktop capture and image work.
    // The injected operation also lets tests verify this without Screen Recording.
    func captureDesktopFallback(
        using capture: () -> (dataURL: String?, mimeType: String?, error: String?)
    ) -> (dataURL: String?, mimeType: String?, error: String?) {
        guard desktopScreenshotFallbackEnabled else {
            return (nil, nil, "Active-window screenshot unavailable; full-desktop fallback is disabled in Settings.")
        }
        return capture()
    }

    private func captureDesktopScreenshot() -> (dataURL: String?, mimeType: String?, error: String?) {
        guard let fullScreenImage = CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return (nil, nil, "Could not capture screenshot from the active window")
        }

        if let croppedImage = croppedWhitespaceImage(from: fullScreenImage),
           let dataURL = convertImageToDataURL(
            croppedImage,
            mimeType: "image/jpeg",
            fileType: .jpeg,
            compression: screenshotCompressionPrimary,
            maxDimension: screenshotMaxDimension
        ) {
            return (dataURL, "image/jpeg", nil)
        }

        return (nil, nil, "Could not capture screenshot within size limits")
    }

    private func captureWindowImage(
        windowID: CGWindowID,
        fileType: NSBitmapImageRep.FileType,
        mimeType: String,
        compression: Double? = nil,
        maxDimension: CGFloat? = nil
    ) -> String? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution]
        ) else {
            return nil
        }

        if let dataURL = convertImageToDataURL(
            image,
            mimeType: mimeType,
            fileType: fileType,
            compression: compression,
            maxDimension: maxDimension
        ) {
            return dataURL
        }

        return nil
    }

    private func boundsValue(_ value: Any?) -> CGSize? {
        guard let bounds = value as? [String: Any],
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private func boundsRect(_ value: Any?) -> CGRect? {
        guard let bounds = value as? [String: Any],
              let x = bounds["X"] as? CGFloat,
              let y = bounds["Y"] as? CGFloat,
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func focusedWindowBounds(from appElement: AXUIElement) -> CGRect? {
        guard let focusedWindow = accessibilityElement(
            from: appElement,
            attribute: kAXFocusedWindowAttribute as CFString
        ),
              let point = accessibilityPoint(from: focusedWindow, attribute: kAXPositionAttribute as CFString),
              let size = accessibilitySize(from: focusedWindow, attribute: kAXSizeAttribute as CFString) else {
            return nil
        }

        return CGRect(origin: point, size: size)
    }

    private func convertImageToDataURL(
        _ image: CGImage,
        mimeType: String,
        fileType: NSBitmapImageRep.FileType,
        compression: Double?,
        maxDimension: CGFloat?
    ) -> String? {
        let compressionSteps: [Double] = if let compression {
            [compression, compression * 0.5, compression * 0.25]
        } else {
            [1.0]
        }
        let dimensionSteps: [CGFloat?] = if let maxDimension {
            [maxDimension, maxDimension * 0.75, maxDimension * 0.5]
        } else {
            [nil]
        }

        for dim in dimensionSteps {
            let imageToEncode = dim.flatMap { resizedImage(for: image, maxDimension: $0) } ?? image
            let rep = NSBitmapImageRep(cgImage: imageToEncode)

            for comp in compressionSteps {
                guard let imageData = rep.representation(
                    using: fileType,
                    properties: [.compressionFactor: comp]
                ) else { continue }

                let base64 = imageData.base64EncodedString()
                if base64.count <= maxScreenshotDataURILength {
                    return "data:\(mimeType);base64,\(base64)"
                }
            }
        }

        return nil
    }

    private func croppedWhitespaceImage(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let byteCount = bytesPerRow * height
        var pixelData = Array(repeating: UInt8(0), count: byteCount)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }

        let drawRect = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        context.draw(image, in: drawRect)

        let whiteThreshold: UInt8 = 245
        let alphaThreshold: UInt8 = 5
        var minX = width
        var minY = height
        var maxX: Int = -1
        var maxY: Int = -1
        var hasContent = false

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let offset = rowOffset + x * bytesPerPixel
                let r = pixelData[offset]
                let g = pixelData[offset + 1]
                let b = pixelData[offset + 2]
                let a = pixelData[offset + 3]

                if a <= alphaThreshold { continue }
                if r >= whiteThreshold && g >= whiteThreshold && b >= whiteThreshold {
                    continue
                }

                hasContent = true
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard hasContent else { return image }

        let cropRect = CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )

        return image.cropping(to: cropRect) ?? image
    }

    private func resizedImage(for image: CGImage, maxDimension: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        guard width > maxDimension || height > maxDimension else {
            return image
        }

        let scale = min(maxDimension / width, maxDimension / height, 1.0)
        let targetSize = CGSize(width: width * scale, height: height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: targetSize))
        return context.makeImage()
    }

    private func trimmedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.isEmpty ? nil : trimmed
    }
}
