import Foundation

/// Session-only tally of HOW the text around the cursor was read.
///
/// Across a session this shows how often the precise accessibility paths succeed
/// versus reads that fail outright (a "blind" app).
/// `@MainActor`-isolated: it is only touched from the main dictation flow, so a
/// plain static stays Sendable-safe under Swift 6 strict concurrency.
@MainActor
enum ContextReadMetrics {

    /// Raw extraction method → how many times it was used this session.
    private static var tally: [String: Int] = [:]

    /// Record one read and return a one-line, human-readable session summary.
    /// - Parameter method: the raw extraction method; `nil`/empty means the read failed.
    static func record(_ method: String?) -> String {
        // Treat a missing method as an outright failure to read.
        let key = method.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        tally[key, default: 0] += 1

        let total   = tally.values.reduce(0, +)
        let failed  = tally["unknown"] ?? 0   // couldn't read at all
        let precise = total - failed          // accessibility paths

        return "\(total) reads this session · \(precise) precise · \(failed) unreadable"
    }
}
