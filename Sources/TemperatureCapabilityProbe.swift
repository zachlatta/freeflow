import Foundation

final class TemperatureCapabilityProbeCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    func schedule(
        _ requests: [URLRequest],
        operation: @escaping @Sendable (URLRequest) async -> Void
    ) {
        lock.lock()
        generation &+= 1
        let currentGeneration = generation
        task?.cancel()
        task = Task {
            for request in requests {
                guard !Task.isCancelled else { return }
                await operation(request)
                guard !Task.isCancelled else { return }
                guard self.isCurrent(currentGeneration) else { return }
            }
        }
        lock.unlock()
    }

    func waitForCurrentProbe() async {
        await currentTask()?.value
    }

    private func currentTask() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }

    private func isCurrent(_ expected: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == expected
    }
}

enum TemperatureCapabilityProbe {
    static func request(
        baseURL: String,
        apiKey: String,
        model: String,
        temperature: Double,
        isPostProcessing: Bool = false
    ) -> URLRequest? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: "\(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any]
        if isPostProcessing {
            payload = ModelConfiguration.nonContentRequestOptions(
                model: model,
                temperature: temperature,
                defaultModel: "openai/gpt-oss-20b",
                defaultReasoningEffort: "low",
                defaultMaxCompletionTokens: 4096
            )
        } else {
            payload = ["model": model, "temperature": temperature]
        }
        payload["messages"] = [
                ["role": "system", "content": "Reply OK."],
                ["role": "user", "content": "Reply OK."]
            ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }

    static func probe(_ request: URLRequest) async {
        guard TemperatureCapabilityCache.shared.capability(for: request) == nil else { return }
        do { _ = try await LLMAPITransport.data(for: request, cache: TemperatureCapabilityCache.shared) }
        catch { /* A capability probe never changes settings or reports transient errors. */ }
    }
}
