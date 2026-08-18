import AppKit
import AVFoundation
import Combine
import Foundation

final class ArchiveService: ObservableObject {
    @Published var recorderConnected = false
    @Published var recorderName = ""
    @Published var syncMessage = "Idle"
    @Published var lastNoteTitle: String?
    @Published var lastNoteDate: Date?
    @Published var isProcessing = false
    @Published var processingMessage = ""
    @Published var errorMessage: String?
    @Published var destinationLabel = "Local"
    @Published var destinationMissing = false
    @Published var notes: [ArchiveNote] = []
    @Published var searchQuery = ""
    @Published var selectedSidebar: ArchiveSidebarItem = .inbox
    @Published var selectedNoteID: String?
    @Published var libraryPathDisplay = ""

    let settings: ArchiveSettings
    private weak var appState: AppState?
    private let monitor = VolumeMonitor()
    private let libraryScanner = ArchiveLibrary()
    private var dropTimer: Timer?
    private var jobQueue: [PendingIngest] = []
    private var queuedPaths = Set<String>()
    private var isRunningJobs = false
    private var connectedRecorderURL: URL?
    private let ioQueue = DispatchQueue(label: "com.zachlatta.freeflow.archive-io", qos: .userInitiated)

    private struct PendingIngest {
        var url: URL
        var sourceVolume: String?
        var deleteSource: Bool
    }

    init(appState: AppState, settings: ArchiveSettings = ArchiveSettings()) {
        self.appState = appState
        self.settings = settings
        self.destinationLabel = settings.provider.shortLabel
    }

    var filteredNotes: [ArchiveNote] {
        let sidebarFiltered: [ArchiveNote]
        switch selectedSidebar {
        case .inbox:
            sidebarFiltered = notes.filter { $0.relativeFolder == FolderRouter.inbox }
        case .today:
            sidebarFiltered = notes.filter { Calendar.current.isDateInToday($0.date) }
        case .folder(let name):
            sidebarFiltered = notes.filter { $0.relativeFolder == name }
        case .tag(let tag):
            sidebarFiltered = notes.filter { $0.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sidebarFiltered }
        return sidebarFiltered.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.transcript.localizedCaseInsensitiveContains(query)
                || note.summary.joined(separator: " ").localizedCaseInsensitiveContains(query)
                || note.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var selectedNote: ArchiveNote? {
        notes.first(where: { $0.id == selectedNoteID }) ?? filteredNotes.first
    }

    var folderNames: [String] {
        libraryScanner.folders(from: notes).filter { $0 != FolderRouter.inbox }
    }

    var tagNames: [String] {
        libraryScanner.tags(from: notes)
    }

    var inboxCount: Int {
        notes.filter { $0.relativeFolder == FolderRouter.inbox }.count
    }

    func lastNoteRelativeLabel() -> String? {
        guard let title = lastNoteTitle else { return nil }
        guard let date = lastNoteDate else { return title }
        return "\(title) (\(Self.relativeTime(since: date)))"
    }

    private static func relativeTime(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    func start() {
        monitor.onMount = { [weak self] url in
            self?.ioQueue.async {
                self?.inspectMountedVolume(url)
            }
        }
        monitor.onUnmount = { [weak self] url in
            DispatchQueue.main.async {
                self?.handleUnmount(url)
            }
        }
        monitor.start()
        ioQueue.async { [weak self] in
            self?.refreshDestinationOnIO()
            self?.refreshLibraryOnIO()
            self?.monitor.scanExisting()
        }
        startDropPolling()
    }

    func refreshDestination() {
        ioQueue.async { [weak self] in
            self?.refreshDestinationOnIO()
        }
    }

    func refreshLibrary() {
        ioQueue.async { [weak self] in
            self?.refreshLibraryOnIO()
        }
    }

    func openLibraryInFinder() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.refreshDestinationOnIO()
            guard let root = self.computeLibraryRoot() else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.open(root)
            }
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func materialize(_ url: URL) {
        ioQueue.async {
            guard FileManager.default.isUbiquitousItem(at: url) else { return }
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    func chooseDestinationFolder(provider: CloudProvider) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder FlowArchive should write into."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.settings.saveBookmark(for: url)
            self?.settings.provider = provider == .idrive ? .idrive : .custom
            self?.refreshDestination()
            self?.refreshLibrary()
        }
    }

    private func refreshDestinationOnIO() {
        let root = computeLibraryRoot()
        let missing: Bool
        if let root {
            missing = false
            try? ArchivePaths.ensureDirectory(root)
            try? ArchivePaths.ensureDirectory(ArchivePaths.inbox(in: root))
            if settings.dropFolderEnabled {
                try? ArchivePaths.ensureDirectory(ArchivePaths.dropFolder(in: root))
            }
        } else {
            missing = true
        }
        let path = root?.path ?? ""
        let label = settings.provider.shortLabel
        DispatchQueue.main.async { [weak self] in
            self?.destinationLabel = label
            self?.destinationMissing = missing
            self?.libraryPathDisplay = path
        }
    }

    private func refreshLibraryOnIO() {
        let root = computeLibraryRoot()
        let scanned = root.map { libraryScanner.scan(libraryRoot: $0) } ?? []
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notes = scanned
            if self.lastNoteTitle == nil, let newest = scanned.first {
                self.lastNoteTitle = newest.title
                self.lastNoteDate = newest.date
            }
        }
    }

    /// Lightweight path for UI and ingest. Does not probe iCloud with `fileExists` when signed in.
    func computeLibraryRoot() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let documents = CloudDestination.documentsRoot()

        switch settings.provider {
        case .icloud:
            let signedIn = FileManager.default.ubiquityIdentityToken != nil
            if let parent = CloudDestination.iCloudDriveRoot(home: home, probeExists: !signedIn) {
                return ArchivePaths.libraryRoot(in: parent)
            }
            return ArchivePaths.libraryRoot(in: documents)
        case .gdrive:
            if let parent = CloudDestination.googleDriveRoots(home: home).first {
                return ArchivePaths.libraryRoot(in: parent)
            }
            return ArchivePaths.libraryRoot(in: documents)
        case .idrive:
            if let parent = CloudDestination.iDriveRoots(
                home: home,
                volumes: monitor.mountedVolumes()
            ).first ?? settings.resolvedCustomURL() {
                return ArchivePaths.libraryRoot(in: parent)
            }
            return ArchivePaths.libraryRoot(in: documents)
        case .local:
            return ArchivePaths.libraryRoot(in: documents)
        case .custom:
            if let parent = settings.resolvedCustomURL() {
                return ArchivePaths.libraryRoot(in: parent)
            }
            return ArchivePaths.libraryRoot(in: documents)
        }
    }

    private func startDropPolling() {
        dropTimer?.invalidate()
        dropTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.ioQueue.async {
                self?.scanDropFolderOnIO()
            }
        }
        ioQueue.async { [weak self] in
            self?.scanDropFolderOnIO()
        }
    }

    private func inspectMountedVolume(_ url: URL) {
        let name = VolumeMonitor.volumeName(for: url)
        let uuid = VolumeMonitor.volumeUUID(for: url) ?? ""
        let extra = settings.extraVolumeNameList
        let nameMatch = RecorderVolumeMatcher.matches(
            volumeName: name,
            extraNames: extra,
            hasRecorderStructure: false
        )
        let uuidMatch = !settings.confirmedVolumeUUID.isEmpty && uuid == settings.confirmedVolumeUUID
        let untitled = ["NO NAME", "NO_NAME", "UNTITLED", "UNTITLED 1"].contains(name.uppercased())
        let structure = (!nameMatch && !uuidMatch && untitled)
            ? RecorderVolumeMatcher.hasRecorderStructure(at: url)
            : false
        guard nameMatch || uuidMatch || structure else { return }

        if settings.confirmedVolumeUUID.isEmpty, !uuid.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.settings.confirmedVolumeUUID = uuid
            }
        }

        let enabled = settings.enabled
        let files = enabled ? recorderAudioFiles(at: url) : []
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connectedRecorderURL = url
            self.recorderConnected = true
            self.recorderName = name
            if files.isEmpty {
                self.syncMessage = "Sony Recorder connected"
                return
            }
            self.syncMessage = "Syncing: \(files.count) audio file\(files.count == 1 ? "" : "s") found…"
            for file in files {
                self.enqueue(PendingIngest(url: file, sourceVolume: name, deleteSource: false))
            }
            self.pump()
        }
    }

    private func handleUnmount(_ url: URL) {
        if connectedRecorderURL?.path == url.path {
            connectedRecorderURL = nil
            recorderConnected = false
            recorderName = ""
            if !isProcessing {
                syncMessage = "Recorder disconnected"
            }
        }
    }

    private func scanDropFolderOnIO() {
        guard settings.enabled, settings.dropFolderEnabled else { return }
        guard let root = computeLibraryRoot() else { return }
        let drop = ArchivePaths.dropFolder(in: root)
        try? ArchivePaths.ensureDirectory(drop)
        let files = audioFiles(under: drop)
        guard !files.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for file in files {
                self.enqueue(PendingIngest(url: file, sourceVolume: "Inbox drop", deleteSource: true))
            }
            self.pump()
        }
    }

    private func recorderAudioFiles(at volumeURL: URL) -> [URL] {
        RecorderVolumeMatcher.searchRoots(at: volumeURL).flatMap { audioFiles(under: $0) }
    }

    private func audioFiles(under root: URL) -> [URL] {
        let extensions = Set(settings.extensionList)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            if files.count >= 500 { break }
            if enumerator.level > 6 { enumerator.skipDescendants(); continue }
            if item.lastPathComponent.hasPrefix(".") { continue }
            if item.lastPathComponent.hasPrefix("._") { continue }
            if item.pathExtension.lowercased() == "icloud" { continue }
            if extensions.contains(item.pathExtension.lowercased()) {
                files.append(item)
            }
        }
        return files
    }

    private func enqueue(_ job: PendingIngest) {
        let path = job.url.standardizedFileURL.path
        guard !queuedPaths.contains(path) else { return }
        queuedPaths.insert(path)
        jobQueue.append(job)
    }

    private func pump() {
        guard !isRunningJobs else { return }
        isRunningJobs = true
        Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        while let job = await MainActor.run(body: { () -> PendingIngest? in
            guard !self.jobQueue.isEmpty else { return nil }
            return self.jobQueue.removeFirst()
        }) {
            await process(job)
        }
        await MainActor.run {
            self.isRunningJobs = false
            self.isProcessing = false
            self.processingMessage = ""
            if self.recorderConnected {
                self.syncMessage = "Sony Recorder connected"
            } else if !self.destinationMissing {
                self.syncMessage = "Idle"
            }
            self.refreshLibrary()
        }
    }

    private func process(_ job: PendingIngest) async {
        await MainActor.run {
            self.isProcessing = true
            self.processingMessage = "Archiving \(job.url.lastPathComponent)…"
            self.errorMessage = nil
        }

        do {
            try await archive(job)
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.queuedPaths.remove(job.url.standardizedFileURL.path)
            }
        }
    }

    private func archive(_ job: PendingIngest) async throws {
        guard let appState else { throw ArchivePipelineError.missingAPIKey }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hasher = IngestHasher(home: home)
        guard let cached = try hasher.ingestIfNew(url: job.url) else {
            if job.deleteSource {
                try? FileManager.default.removeItem(at: job.url)
            }
            _ = await MainActor.run { [path = job.url.standardizedFileURL.path] in
                self.queuedPaths.remove(path)
            }
            return
        }
        let hash = try IngestHasher.sha256Hex(of: cached)

        let transcriptionKey = appState.transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? appState.apiKey
            : appState.transcriptionAPIKey
        let transcriptionBase = appState.transcriptionAPIURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? appState.apiBaseURL
            : appState.transcriptionAPIURL
        guard !transcriptionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArchivePipelineError.missingAPIKey
        }

        let timeout = settings.transcriptionTimeoutSeconds
        let service = try TranscriptionService(
            apiKey: transcriptionKey,
            baseURL: transcriptionBase,
            transcriptionModel: appState.transcriptionModel,
            timeoutSeconds: timeout
        )

        let chunks = try await AudioChunker.chunks(for: cached)
        var segments: [(start: TimeInterval, text: String)] = []
        var texts: [String] = []
        var offset: TimeInterval = 0
        for chunk in chunks {
            let result = try await service.transcribeDetailed(fileURL: chunk.url)
            texts.append(result.text)
            if result.segments.isEmpty {
                if !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append((offset, result.text))
                }
            } else {
                for segment in result.segments where !segment.text.isEmpty {
                    segments.append((segment.start + offset, segment.text))
                }
            }
            offset += chunk.duration
            if chunk.deleteAfter {
                try? FileManager.default.removeItem(at: chunk.url)
            }
        }

        let rawTranscript = texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let organizer: OrganizerResult
        if rawTranscript.isEmpty {
            organizer = ArchiveOrganizer.fallback(from: job.url.deletingPathExtension().lastPathComponent)
        } else {
            do {
                organizer = try await ArchiveOrganizer.organize(
                    transcript: rawTranscript,
                    apiKey: appState.apiKey,
                    baseURL: appState.apiBaseURL,
                    model: appState.postProcessingModel,
                    prompt: settings.organizerPrompt
                )
            } catch {
                organizer = ArchiveOrganizer.fallback(from: rawTranscript)
            }
        }

        let relative = FolderRouter.relativeFolder(
            tags: organizer.tags,
            transcript: rawTranscript,
            rules: settings.folderRules
        )
        guard let libraryRoot = computeLibraryRoot() else {
            throw ArchivePipelineError.destinationMissing("Archive folder is unavailable.")
        }
        let destinationFolder = libraryRoot.appendingPathComponent(relative, isDirectory: true)
        try ArchivePaths.ensureDirectory(destinationFolder)

        let fileDate = (try? job.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        var stem = ArchiveMarkdownWriter.stem(date: fileDate, kebabName: organizer.filename)
        let ext = cached.pathExtension.isEmpty ? "mp3" : cached.pathExtension
        var audioDest = destinationFolder.appendingPathComponent("\(stem).\(ext)")
        var markdownDest = destinationFolder.appendingPathComponent("\(stem).md")
        var suffix = 2
        while FileManager.default.fileExists(atPath: audioDest.path)
            || FileManager.default.fileExists(atPath: markdownDest.path) {
            let uniqued = "\(stem)-\(suffix)"
            audioDest = destinationFolder.appendingPathComponent("\(uniqued).\(ext)")
            markdownDest = destinationFolder.appendingPathComponent("\(uniqued).md")
            suffix += 1
        }
        if suffix > 2 {
            stem = "\(stem)-\(suffix - 1)"
        }

        if FileManager.default.fileExists(atPath: audioDest.path) {
            try FileManager.default.removeItem(at: audioDest)
        }
        try FileManager.default.copyItem(at: cached, to: audioDest)

        let duration = Int(offset.rounded())
        let title = organizer.filename
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
        let body = ArchiveMarkdownWriter.transcriptBody(segments: segments, fallback: rawTranscript)
        let markdown = ArchiveMarkdownWriter.render(
            frontMatter: ArchiveFrontMatter(
                title: title,
                date: fileDate,
                durationSeconds: duration,
                tags: organizer.tags,
                audio: audioDest.lastPathComponent,
                hash: "sha256:\(hash)",
                sourceVolume: job.sourceVolume
            ),
            summary: organizer.summary,
            transcript: body
        )
        try markdown.write(to: markdownDest, atomically: true, encoding: .utf8)
        SpotlightAttributes.apply(to: [audioDest, markdownDest], tags: organizer.tags, hash: hash)

        if job.deleteSource {
            try? FileManager.default.removeItem(at: job.url)
        }

        let markdownPath = markdownDest.path
        await MainActor.run {
            self.queuedPaths.remove(job.url.standardizedFileURL.path)
            self.lastNoteTitle = title
            self.lastNoteDate = Date()
            self.syncMessage = "Archived \(title)"
            self.refreshLibrary()
            self.selectedNoteID = markdownPath
        }
    }
}
