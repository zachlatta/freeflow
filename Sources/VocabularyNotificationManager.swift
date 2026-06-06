import Foundation

// MARK: - Vocabulary Notification Manager

/// Manages the transient status bar visual checkmark notification when pasting a word.
@MainActor
final class VocabularyNotificationManager: ObservableObject, @unchecked Sendable {
    static let shared = VocabularyNotificationManager()
    
    @Published var showCheckmark: Bool = false
    private var flashTask: Task<Void, Never>?
    
    private init() {}
    
    /// Flashes a checkmark in the menu bar for 2 seconds, cancelling any previous flash tasks.
    func flashCheckmark() {
        flashTask?.cancel()
        flashTask = Task {
            self.showCheckmark = true
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                self.showCheckmark = false
            } catch {
                // Task was cancelled, leave the checkmark state alone for the next task
            }
        }
    }
}

