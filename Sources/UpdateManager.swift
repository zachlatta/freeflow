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

// MARK: - Update Status

enum UpdateStatus: Equatable {
    case idle
    case downloading
    case installing
    case readyToRelaunch
    case error(String)
}

// MARK: - Update Manager

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var updateAvailable = false
    @Published var latestRelease: GitHubRelease?
    @Published var latestReleaseDate: String = ""
    @Published var isChecking = false
    @Published var downloadProgress: Double?
    @Published var updateStatus: UpdateStatus = .idle
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
    private var activeDownloadTask: Task<Void, Never>?

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
            if daysSincePublished < stabilityBufferDays {
                if !userInitiated {
                    // Auto-check: silently skip, too new
                    updateAvailable = false
                    return
                }
                // Manual check: let user know and offer the update anyway
                latestRelease = release
                latestReleaseDate = releaseDateString
                updateAvailable = true
                showRecentReleaseAlert(daysSincePublished: daysSincePublished)
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

    private func showRecentReleaseAlert(daysSincePublished: Double) {
        guard let release = latestRelease else { return }

        let hoursAgo = Int(daysSincePublished * 24)
        let ageText = hoursAgo < 1 ? "less than an hour ago" : hoursAgo < 24 ? "\(hoursAgo) hour\(hoursAgo == 1 ? "" : "s") ago" : "\(Int(daysSincePublished)) day\(Int(daysSincePublished) == 1 ? "" : "s") ago"

        let alert = NSAlert()
        alert.messageText = "New Release Available"
        alert.informativeText = "A new version of FreeFlow was released \(ageText). It's very recent — you can download it now or wait a few days for stability.\n\nWould you like to download it?"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Download Now")
        alert.addButton(withTitle: "Wait")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            downloadAndInstall(release: release)
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

    func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadProgress = nil
        updateStatus = .idle
    }

    func downloadAndInstall(release: GitHubRelease) {
        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        guard let downloadURL = URL(string: dmgAsset.browserDownloadUrl) else { return }

        activeDownloadTask?.cancel()
        activeDownloadTask = Task {
            await performUpdate(downloadURL: downloadURL, expectedSize: dmgAsset.size)
        }
    }

    private func performUpdate(downloadURL: URL, expectedSize: Int) async {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("freeflow-update-\(UUID().uuidString)")

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            updateStatus = .error("Failed to create temp directory: \(error.localizedDescription)")
            return
        }

        let dmgPath = tempDir.appendingPathComponent("FreeFlow.dmg")

        // MARK: Download phase
        updateStatus = .downloading
        downloadProgress = 0

        do {
            var request = URLRequest(url: downloadURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            let totalSize = (response as? HTTPURLResponse)
                .flatMap { Int($0.value(forHTTPHeaderField: "Content-Length") ?? "") }
                ?? expectedSize

            let outputHandle = try FileHandle(forWritingTo: {
                fm.createFile(atPath: dmgPath.path, contents: nil)
                return dmgPath
            }())

            // Run the byte-iteration and file I/O off the main thread
            let mgr = self
            let downloadTask = Task.detached {
                var receivedBytes = 0
                let bufferSize = 65_536
                var buffer = Data()
                buffer.reserveCapacity(bufferSize)
                var lastProgressUpdate = CFAbsoluteTimeGetCurrent()

                for try await byte in asyncBytes {
                    try Task.checkCancellation()
                    buffer.append(byte)
                    if buffer.count >= bufferSize {
                        outputHandle.write(buffer)
                        receivedBytes += buffer.count
                        buffer.removeAll(keepingCapacity: true)

                        // Throttle progress updates to ~30fps
                        let now = CFAbsoluteTimeGetCurrent()
                        if totalSize > 0 && (now - lastProgressUpdate) >= 0.033 {
                            lastProgressUpdate = now
                            let progress = Double(receivedBytes) / Double(totalSize)
                            await MainActor.run {
                                mgr.downloadProgress = progress
                            }
                        }
                    }
                }

                // Write remaining bytes
                if !buffer.isEmpty {
                    outputHandle.write(buffer)
                    receivedBytes += buffer.count
                }
                try outputHandle.close()
            }

            try await downloadTask.value
            downloadProgress = 1.0

        } catch is CancellationError {
            try? fm.removeItem(at: tempDir)
            return
        } catch let error as URLError where error.code == .cancelled {
            try? fm.removeItem(at: tempDir)
            return
        } catch {
            updateStatus = .error("Download failed: \(error.localizedDescription)")
            downloadProgress = nil
            try? fm.removeItem(at: tempDir)
            return
        }

        // MARK: Install phase - mount DMG, extract app
        updateStatus = .installing
        downloadProgress = nil

        do {
            let mountPoint = try await Task.detached {
                try self.mountDMG(at: dmgPath)
            }.value

            defer {
                // Always try to detach
                let detach = Process()
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountPoint, "-quiet"]
                try? detach.run()
                detach.waitUntilExit()
            }

            // Find the .app inside the mounted volume
            let volumeURL = URL(fileURLWithPath: mountPoint)
            let contents = try fm.contentsOfDirectory(at: volumeURL, includingPropertiesForKeys: nil)
            guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                updateStatus = .error("No .app found in DMG.")
                try? fm.removeItem(at: tempDir)
                return
            }

            // Copy app to staging directory
            let stagingDir = fm.temporaryDirectory.appendingPathComponent("freeflow-staged-\(UUID().uuidString)")
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            let stagedApp = stagingDir.appendingPathComponent(appBundle.lastPathComponent)
            try fm.copyItem(at: appBundle, to: stagedApp)

            // Clean up DMG (detach happens in defer above, delete temp dir)
            try? fm.removeItem(at: tempDir)

            // MARK: Replace & relaunch
            updateStatus = .readyToRelaunch
            replaceAndRelaunch(stagedApp: stagedApp, stagingDir: stagingDir)

        } catch {
            updateStatus = .error("Install failed: \(error.localizedDescription)")
            try? fm.removeItem(at: tempDir)
        }
    }

    nonisolated private func mountDMG(at path: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path.path, "-nobrowse", "-noverify", "-noautoopen", "-plist"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "UpdateManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "hdiutil attach failed with exit code \(process.terminationStatus)"
            ])
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        // Parse the plist output to find mount point
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw NSError(domain: "UpdateManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not parse hdiutil output"
            ])
        }

        // Find the mount point from the entities
        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return mountPoint
            }
        }

        throw NSError(domain: "UpdateManager", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "No mount point found in hdiutil output"
        ])
    }

    private func replaceAndRelaunch(stagedApp: URL, stagingDir: URL) {
        let currentAppPath = Bundle.main.bundlePath
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let backupPath = currentAppPath + ".bak"

        // Use an argument array instead of string interpolation into a shell
        // script to avoid injection. Move old app to backup first so a failed
        // mv doesn't leave the user with no app.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        mv "$2" "$5" && mv "$3" "$2" && open "$2" && rm -rf "$4" "$5" \
            || { mv "$5" "$2" 2>/dev/null; exit 1; }
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "--",
                             pid,                // $1
                             currentAppPath,     // $2
                             stagedApp.path,      // $3
                             stagingDir.path,     // $4
                             backupPath]          // $5
        try? process.run()

        // Quit the current app
        NSApp.terminate(nil)
    }
}
