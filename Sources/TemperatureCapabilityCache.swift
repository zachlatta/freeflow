import CryptoKit
import Foundation

enum TemperatureCapability: String, Codable {
    case supported
    case unsupported
}

final class TemperatureCapabilityCache: @unchecked Sendable {
    static let shared = TemperatureCapabilityCache()
    private struct Entry: Codable {
        let digest: String
        let capability: TemperatureCapability
        let observedAt: Date
    }

    private let defaults: UserDefaults
    private let key: String
    private let now: () -> Date
    private let lifetime: TimeInterval = 7 * 24 * 60 * 60
    private let limit = 128
    private let lock = NSLock()
    private var revisions: [String: UInt64] = [:]

    struct Observation: Sendable {
        let capability: TemperatureCapability?
        fileprivate let digest: String?
        fileprivate let revision: UInt64
    }

    init(defaults: UserDefaults = .standard, key: String = "llm_temperature_capabilities_v1", now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.key = key
        self.now = now
    }

    func capability(for request: URLRequest) -> TemperatureCapability? {
        lock.lock()
        defer { lock.unlock() }
        guard let digest = Self.digest(for: request), let entries = load(),
              let entry = entries.first(where: { $0.digest == digest }),
              now().timeIntervalSince(entry.observedAt) >= 0,
              now().timeIntervalSince(entry.observedAt) < lifetime else { return nil }
        return entry.capability
    }

    func beginObservation(for request: URLRequest) -> Observation {
        lock.lock()
        defer { lock.unlock() }
        guard let digest = Self.digest(for: request) else { return Observation(capability: nil, digest: nil, revision: 0) }
        let revision = revisions[digest, default: 0] &+ 1
        revisions[digest] = revision
        guard let entries = load(),
              let entry = entries.first(where: { $0.digest == digest }),
              now().timeIntervalSince(entry.observedAt) >= 0,
              now().timeIntervalSince(entry.observedAt) < lifetime else {
            return Observation(capability: nil, digest: digest, revision: revision)
        }
        return Observation(capability: entry.capability, digest: digest, revision: revision)
    }

    func record(_ capability: TemperatureCapability, for request: URLRequest, observation: Observation? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard let digest = Self.digest(for: request) else { return }
        if let observation, observation.digest != digest || observation.revision != revisions[digest] { return }
        var entries = load() ?? []
        entries.removeAll { $0.digest == digest }
        entries.append(Entry(digest: digest, capability: capability, observedAt: now()))
        entries.sort { $0.observedAt > $1.observedAt }
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private func load() -> [Entry]? {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data),
              entries.count <= limit else { return nil }
        return entries
    }

    private static func digest(for request: URLRequest) -> String? {
        guard let url = request.url,
              let body = request.httpBody,
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let temperature = payload["temperature"] else { return nil }
        let excluded: Set<String> = ["messages", "prompt", "input"]
        let options = payload.filter { !excluded.contains($0.key) }
        let auth = request.allHTTPHeaderFields?
            .filter { ["authorization", "api-key", "x-api-key"].contains($0.key.lowercased()) }
            .map { [$0.key.lowercased(), $0.value] }
            .sorted { ($0.first ?? "") < ($1.first ?? "") } ?? []
        let identity: [String: Any] = [
            "url": url.absoluteString,
            "auth": auth,
            "options": options,
            "temperature": temperature
        ]
        guard let canonical = try? JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys]) else { return nil }
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }
}
