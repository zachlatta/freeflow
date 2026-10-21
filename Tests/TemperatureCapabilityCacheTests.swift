import Foundation

enum TemperatureCapabilityCacheTests {
    static func run() {
        let suite = "TemperatureCapabilityCacheTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 1_000)
        let cache = TemperatureCapabilityCache(defaults: defaults, key: "cache", now: { now })
        func request(model: String = "model", temperature: Double = 0, token: String = "secret", host: String = "provider.invalid") -> URLRequest {
            var request = URLRequest(url: URL(string: "https://\(host)/v1/chat/completions")!)
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
        TestSupport.expect(cache.capability(for: request(host: "draft-provider.invalid")) == nil, "Capability is endpoint-specific")
        let stored = String(data: defaults.data(forKey: "cache")!, encoding: .utf8)!
        TestSupport.expect(!stored.contains("secret") && !stored.contains("private prompt"), "Cache stores no credentials or prompt")
        now.addTimeInterval(7 * 24 * 60 * 60)
        TestSupport.expect(cache.capability(for: original) == nil, "Expired capability is unknown")

        now = Date(timeIntervalSince1970: 2_000)
        let stale = cache.beginObservation(for: original)
        let latest = cache.beginObservation(for: original)
        cache.record(.unsupported, for: original, observation: latest)
        cache.record(.supported, for: original, observation: stale)
        TestSupport.expect(cache.capability(for: original) == .unsupported, "Stale success cannot overwrite newer runtime rejection")

        now = Date(timeIntervalSince1970: 3_000)
        let supported = request(model: "supported")
        cache.record(.supported, for: supported)
        now.addTimeInterval((7 * 24 * 60 * 60) / 2 - 1)
        cache.record(.supported, for: supported)
        now.addTimeInterval((7 * 24 * 60 * 60) / 2 + 1)
        TestSupport.expect(cache.capability(for: supported) == nil, "Fresh positive evidence does not rewrite the cache before half-TTL")
    }
}
