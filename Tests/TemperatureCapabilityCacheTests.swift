import Foundation

private actor ProbeGate {
    private var hasStarted = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func blockOldProbe() async {
        hasStarted = true
        startedWaiter?.resume()
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor ProbeResults {
    private(set) var applied: [String] = []
    func apply(_ value: String) { applied.append(value) }
}

enum TemperatureCapabilityCacheTests {
    static func run() async {
        let suite = "TemperatureCapabilityCacheTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 1_000)
        let cache = TemperatureCapabilityCache(defaults: defaults, key: "cache", now: { now })
        func request(model: String = "model", temperature: Double = 0, token: String = "secret") -> URLRequest {
            var request = URLRequest(url: URL(string: "https://provider.invalid/v1/chat/completions")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try! JSONSerialization.data(withJSONObject: ["model": model, "temperature": temperature, "messages": [["role": "user", "content": "private prompt"]]])
            return request
        }
        let original = request()
        cache.record(.unsupported, for: original)
        TestSupport.expect(cache.capability(for: original) == .unsupported, "Unsupported capability persists")
        TestSupport.expect(cache.capability(for: request(model: "other")) == nil, "Capability is model-specific")
        TestSupport.expect(cache.capability(for: request(temperature: 0.2)) == nil, "Capability is temperature-specific")
        TestSupport.expect(cache.capability(for: request(token: "other")) == nil, "Capability is account-specific")
        let stored = String(data: defaults.data(forKey: "cache")!, encoding: .utf8)!
        TestSupport.expect(!stored.contains("secret") && !stored.contains("private prompt"), "Cache stores no credentials or prompt")
        now.addTimeInterval(7 * 24 * 60 * 60)
        TestSupport.expect(cache.capability(for: original) == nil, "Expired capability is unknown")

        now = Date(timeIntervalSince1970: 2_000)
        let stale = cache.beginObservation(for: original)
        let latest = cache.beginObservation(for: original)
        cache.record(.unsupported, for: original, observation: latest)
        cache.record(.supported, for: original, observation: stale)
        TestSupport.expect(cache.capability(for: original) == .unsupported, "Late stale probe cannot overwrite newer runtime rejection")

        let cleanupProbe = TemperatureCapabilityProbe.request(
            baseURL: "https://provider.invalid/v1",
            apiKey: "synthetic-secret",
            model: "openai/gpt-oss-20b",
            temperature: 0,
            isPostProcessing: true
        )!
        let cleanupPayload = try! JSONSerialization.jsonObject(with: cleanupProbe.httpBody!) as! [String: Any]
        let cleanupOptions = ModelConfiguration.nonContentRequestOptions(
            model: "openai/gpt-oss-20b",
            temperature: 0,
            defaultModel: "openai/gpt-oss-20b",
            defaultReasoningEffort: "low",
            defaultMaxCompletionTokens: 4096
        )
        TestSupport.expect(cleanupPayload.filter { $0.key != "messages" } as NSDictionary == cleanupOptions as NSDictionary, "Cleanup probe shares production non-content options")
        let probeMessages = cleanupPayload["messages"] as! [[String: Any]]
        let serializedMessages = String(data: try! JSONSerialization.data(withJSONObject: probeMessages), encoding: .utf8)!
        TestSupport.expect(serializedMessages.contains("Reply OK") && !serializedMessages.contains("private prompt") && !serializedMessages.contains("synthetic-secret"), "Probe contains only fixed synthetic content")

        let contextProbe = TemperatureCapabilityProbe.request(
            baseURL: "https://provider.invalid/v1",
            apiKey: "synthetic-secret",
            model: "qwen/qwen3.6-27b",
            temperature: 0.2
        )!
        let contextPayload = try! JSONSerialization.jsonObject(with: contextProbe.httpBody!) as! [String: Any]
        TestSupport.expect(contextPayload.keys.sorted() == ["messages", "model", "temperature"], "Context probe matches production reasoning/token options")

        let coordinator = TemperatureCapabilityProbeCoordinator()
        let gate = ProbeGate()
        let results = ProbeResults()
        let old = URLRequest(url: URL(string: "https://provider.invalid/old")!)
        let new = URLRequest(url: URL(string: "https://provider.invalid/new")!)
        coordinator.schedule([old]) { request in
            await gate.blockOldProbe()
            guard !Task.isCancelled else { return }
            await results.apply(request.url!.lastPathComponent)
        }
        await gate.waitUntilStarted()
        coordinator.schedule([new]) { request in
            guard !Task.isCancelled else { return }
            await results.apply(request.url!.lastPathComponent)
        }
        await gate.release()
        await coordinator.waitForCurrentProbe()
        let applied = await results.applied
        TestSupport.expect(applied == ["new"], "Superseded save probe cannot apply stale result")
    }
}
