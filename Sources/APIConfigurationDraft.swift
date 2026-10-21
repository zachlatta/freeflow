import Foundation

/// A form's raw edits and the last complete saved configuration it observed.
/// Endpoint/credential pairs reconcile together; a dirty half protects both.
struct APIConfigurationDraft {
    var apiKey = ""
    var baseURL = ""
    var transcriptionAPIURL = ""
    var transcriptionAPIKey = ""

    private var baseline: ValidatedAPIConfiguration?
    private var presentation = UUID()
    private var isPresented = false

    struct Submission: Sendable {
        let configuration: ValidatedAPIConfiguration
        fileprivate let presentation: UUID
    }

    var configuration: ValidatedAPIConfiguration {
        ValidatedAPIConfiguration(
            apiKey: apiKey,
            baseURL: baseURL,
            transcriptionAPIURL: transcriptionAPIURL,
            transcriptionAPIKey: transcriptionAPIKey
        )
    }

    var submission: Submission {
        Submission(configuration: configuration, presentation: presentation)
    }

    mutating func present(_ saved: ValidatedAPIConfiguration) {
        presentation = UUID()
        isPresented = true
        reconcile(saved)
    }

    mutating func dismiss() {
        isPresented = false
    }

    func isCurrent(_ submission: Submission) -> Bool {
        isPresented && presentation == submission.presentation
    }

    func matches(_ submission: Submission) -> Bool {
        isCurrent(submission) && configuration == submission.configuration
    }

    mutating func reconcile(_ saved: ValidatedAPIConfiguration) {
        if baseline == nil || (apiKey == baseline?.apiKey && baseURL == baseline?.baseURL) {
            apiKey = saved.apiKey
            baseURL = saved.baseURL
        }
        if baseline == nil || (transcriptionAPIURL == baseline?.transcriptionAPIURL && transcriptionAPIKey == baseline?.transcriptionAPIKey) {
            transcriptionAPIURL = saved.transcriptionAPIURL
            transcriptionAPIKey = saved.transcriptionAPIKey
        }
        baseline = saved
    }

    /// Normalize only the unchanged form that actually submitted this snapshot.
    /// Other presentations receive the commit through complete-snapshot reconciliation.
    @discardableResult
    mutating func accept(_ saved: ValidatedAPIConfiguration, for submission: Submission) -> Bool {
        guard matches(submission) else { return false }
        apiKey = saved.apiKey
        baseURL = saved.baseURL
        transcriptionAPIURL = saved.transcriptionAPIURL
        transcriptionAPIKey = saved.transcriptionAPIKey
        baseline = saved
        return true
    }

    func showsSavedSuccess(_ successful: ValidatedAPIConfiguration?, committed: ValidatedAPIConfiguration) -> Bool {
        isPresented && successful == configuration && successful == committed
    }
}
