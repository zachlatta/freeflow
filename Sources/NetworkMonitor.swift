import Foundation
import Network

/// Live network-reachability tracker. A single long-running `NWPathMonitor`
/// keeps `isOnline` current so transcription error classification can tell a
/// real network outage apart from a slow provider — a hung socket trips the
/// request timeout, which otherwise looks identical to "the server is slow."
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.zachlatta.freeflow.network-monitor")
    private let lock = NSLock()
    private var started = false

    // Default to online so the first request, before the monitor's first path
    // update lands, is never wrongly blamed on the network.
    private var _isOnline = true

    private init() {}

    /// Current reachability. Safe to read from any thread.
    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isOnline
    }

    /// Begin monitoring. Idempotent — call once at launch.
    func start() {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            self.lock.lock()
            self._isOnline = online
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}
