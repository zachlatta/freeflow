import Foundation
import AppKit

// MARK: - Data Models

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlUrl: String
    let publishedAt: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

// MARK: - Update Manager

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var updateAvailable = false
    @Published var latestRelease: GitHubRelease?
    @Published var latestReleaseDate: String = ""
    @Published var isChecking = false
    @Published var lastCheckDate: Date? {
        didSet {
            if let date = lastCheckDate {
                UserDefaults.standard.set(date, forKey: "updateLastCheckDate")
            }
        }
    }

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "updateAutoCheckEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "updateAutoCheckEnabled") }
    }

    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: "updateSkippedVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "updateSkippedVersion") }
    }

    private let releasesURL = URL(string: "https://api.github.com/repos/zachlatta/freeflow/releases/latest")!
    private let stabilityBufferDays: TimeInterval = 3
    private let checkIntervalSeconds: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private var periodicTimer: Timer?

    private init() {
        lastCheckDate = UserDefaults.standard.object(forKey: "updateLastCheckDate") as? Date
    }

    // MARK: - Periodic Checks

    func startPeriodicChecks() {
        // Initial check after 5 second delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.shouldAutoCheck() {
                    await self.checkForUpdates(userInitiated: false)
                }
            }
        }

        // Re-evaluate hourly (handles sleep/wake)
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.shouldAutoCheck() {
                    await self.checkForUpdates(userInitiated: false)
                }
            }
        }
    }

    private func shouldAutoCheck() -> Bool {
        guard autoCheckEnabled else { return false }
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) > checkIntervalSeconds
    }

    // MARK: - Check for Updates

    func checkForUpdates(userInitiated: Bool) async {
        let currentBuildTag = Bundle.main.infoDictionary?["FreeFlowBuildTag"] as? String

        // Dev builds (no embedded tag): skip auto-checks, but allow manual checks
        if !userInitiated && currentBuildTag == nil {
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                if userInitiated { showErrorAlert("Could not reach GitHub.") }
                return
            }

            // 404 means no releases exist yet
            if httpResponse.statusCode == 404 {
                lastCheckDate = Date()
                updateAvailable = false
                latestRelease = nil
                if userInitiated { showUpToDateAlert() }
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if userInitiated { showErrorAlert("GitHub returned status \(httpResponse.statusCode).") }
                return
            }

            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)
            lastCheckDate = Date()

            // Parse the published date
            let iso8601 = ISO8601DateFormatter()
            iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let iso8601Basic = ISO8601DateFormatter()
            iso8601Basic.formatOptions = [.withInternetDateTime]

            guard let publishedDate = iso8601.date(from: release.publishedAt)
                    ?? iso8601Basic.date(from: release.publishedAt) else {
                if userInitiated { showErrorAlert("Could not parse release date.") }
                return
            }

            // Format the release date for display
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            let releaseDateString = dateFormatter.string(from: publishedDate)

            // If this is the same build we're running, no update available
            if let currentTag = currentBuildTag, release.tagName == currentTag {
                updateAvailable = false
                latestRelease = nil
                if userInitiated { showUpToDateAlert() }
                return
            }

            // Check stability buffer (3 days since published)
            let daysSincePublished = Date().timeIntervalSince(publishedDate) / (24 * 60 * 60)
            guard daysSincePublished >= stabilityBufferDays else {
                // Too new, don't offer yet
                updateAvailable = false
                if userInitiated { showUpToDateAlert() }
                return
            }

            // Check if user skipped this version (only for auto checks)
            if !userInitiated && skippedVersion == release.tagName {
                updateAvailable = false
                return
            }

            latestRelease = release
            latestReleaseDate = releaseDateString
            updateAvailable = true

            if userInitiated {
                showUpdateAlert()
            }
        } catch {
            if userInitiated {
                showErrorAlert("Failed to check for updates: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Alerts

    func showUpdateAlert() {
        guard let release = latestRelease else { return }

        let alert = NSAlert()
        alert.messageText = "A New Version is Available"
        alert.informativeText = "A new version of FreeFlow (released \(latestReleaseDate)) is available.\n\nWould you like to download the update?"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            downloadAndInstall(release: release)
        case .alertThirdButtonReturn:
            skippedVersion = release.tagName
            updateAvailable = false
            latestRelease = nil
        default:
            break // Remind me later — do nothing
        }
    }

    func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "You're running the latest version of FreeFlow."
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Download and Install

    func downloadAndInstall(release: GitHubRelease) {
        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            // No DMG found, open the release page instead
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        guard let downloadURL = URL(string: dmgAsset.browserDownloadUrl) else { return }

        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destURL = downloadsDir.appendingPathComponent(dmgAsset.name)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: destURL)

        let progressAlert = NSAlert()
        progressAlert.messageText = "Downloading Update..."
        progressAlert.informativeText = "Downloading FreeFlow update..."
        progressAlert.alertStyle = .informational
        progressAlert.icon = NSApp.applicationIconImage
        progressAlert.addButton(withTitle: "Cancel")

        // Start download in background
        let task = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                NSApp.abortModal()

                if let error {
                    self?.showErrorAlert("Download failed: \(error.localizedDescription)")
                    return
                }

                guard let tempURL else {
                    self?.showErrorAlert("Download failed: no file received.")
                    return
                }

                do {
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    NSWorkspace.shared.open(destURL)
                    self?.showInstallInstructions()
                } catch {
                    self?.showErrorAlert("Failed to save download: \(error.localizedDescription)")
                }
            }
        }
        task.resume()

        let response = progressAlert.runModal()
        if response == .alertFirstButtonReturn {
            task.cancel()
        }
    }

    private func showInstallInstructions() {
        let alert = NSAlert()
        alert.messageText = "Update Downloaded"
        alert.informativeText = "The DMG has been opened. To install:\n\n1. Drag FreeFlow to your Applications folder\n2. Replace the existing copy when prompted\n3. Relaunch FreeFlow"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
