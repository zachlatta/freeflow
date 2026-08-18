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

    let settings: ArchiveSettings
    private weak var appState: AppState?
    private let monitor = VolumeMonitor()
    private let libraryScanner = ArchiveLibrary()
    private var dropTimer: Timer?
    private var jobQueue: [PendingIngest] = []
    private var queuedPaths = Set<String>()
    private var isRunningJobs = false
    private var connectedRecorderURL: URL?

    private struct PendingIngest {
        var url: URL
        var sourceVolume: String?
        var deleteSource: Bool
    }

    init(appState: AppState, settings: ArchiveSettings = ArchiveSettings()) {
        self.appState = appState
        self.settings = settings
        refreshDestination()
        refreshLibrary()
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
        refreshDestination()
        refreshLibrary()
        monitor.onMount = { [weak self] url in
            self?.handleMount(url)
        }
        monitor.onUnmount = { [weak self] url in
            self?.handleUnmount(url)
        }
        monitor.start()
        monitor.scanExisting()
        startDropPolling()
    }

    func refreshDestination() {
        destinationLabel = settings.provider.shortLabel
        guard let root = resolveLibraryRoot() else { return }
        try? ArchivePaths.ensureDirectory(root)
        try? ArchivePaths.ensureDirectory(ArchivePaths.inbox(in: root))
        if settings.dropFolderEnabled {
            try? ArchivePaths.ensureDirectory(ArchivePaths.dropFolder(in: root))
        }
    }

    func refreshLibrary() {
        guard let root = resolveLibraryRoot() else {
            notes = []
            return
        }
        notes = libraryScanner.scan(libraryRoot: root)
        if lastNoteTitle == nil, let newest = notes.first {
            lastNoteTitle = newest.title
            lastNoteDate = newest.date
        }
    }

    func openLibraryInFinder() {
        guard let root = resolveLibraryRoot() else { return }
        try? ArchivePaths.ensureDirectory(root)
        NSWorkspace.shared.open(root)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func materialize(_ url: URL) {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    func chooseDestinationFolder(provider: CloudProvider) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder FlowArchive should write into."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.saveBookmark(for: url)
        settings.provider = provider == .idrive ? .idrive : .custom
        refreshDestination()
        refreshLibrary()
    }

    func resolveLibraryRoot() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let options = CloudDestination.options(home: home, volumes: monitor.mountedVolumes())
        destinationMissing = false

        func root(for provider: CloudProvider) -> URL? {
            options.first(where: { $0.provider == provider })?.root
        }

        let parent: URL?
        switch settings.provider {
        case .icloud:
            parent = root(for: .icloud)
            if parent == nil {
                destinationMissing = true
                return ArchivePaths.libraryRoot(in: CloudDestination.documentsRoot())
            }
        case .gdrive:
            parent = root(for: .gdrive)
            if parent == nil {
                destinationMissing = true
                return ArchivePaths.libraryRoot(in: CloudDestination.documentsRoot())
            }
        case .idrive:
            parent = root(for: .idrive) ?? settings.resolvedCustomURL()
            if parent == nil {
                destinationMissing = true
                return ArchivePaths.libraryRoot(in: CloudDestination.documentsRoot())
            }
        case .local:
            parent = CloudDestination.documentsRoot()
        case .custom:
            parent = settings.resolvedCustomURL()
            if parent == nil {
                destinationMissing = true
                return ArchivePaths.libraryRoot(in: CloudDestination.documentsRoot())
            }
        }

        guard let parent else { return nil }
        return ArchivePaths.libraryRoot(in: parent)
    }

    private func startDropPolling() {
        dropTimer?.invalidate()
        dropTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.scanDropFolder()
        }
        scanDropFolder()
    }

    private func handleMount(_ url: URL) {
        let name = VolumeMonitor.volumeName(for: url)
        let uuid = VolumeMonitor.volumeUUID(for: url) ?? ""
        let structure = RecorderVolumeMatcher.hasRecorderStructure(at: url)
        let nameMatch = RecorderVolumeMatcher.matches(
            volumeName: name,
            extraNames: settings.extraVolumeNameList,
            hasRecorderStructure: structure
        )
        let uuidMatch = !settings.confirmedVolumeUUID.isEmpty && uuid == settings.confirmedVolumeUUID
        guard nameMatch || uuidMatch else { return }

        if settings.confirmedVolumeUUID.isEmpty, !uuid.isEmpty {
            settings.confirmedVolumeUUID = uuid
        }
        connectedRecorderURL = url
        recorderConnected = true
        recorderName = name
        syncMessage = "Sony Recorder connected"
        enqueueRecorderFiles(at: url, volumeName: name)
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

    private func enqueueRecorderFiles(at volumeURL: URL, volumeName: String) {
        guard settings.enabled else { return }
        let files = audioFiles(under: volumeURL)
        guard !files.isEmpty else {
            syncMessage = "Sony Recorder connected"
            return
        }
        syncMessage = "Syncing: \(files.count) audio file\(files.count == 1 ? "" : "s") found…"
        for file in files {
            enqueue(PendingIngest(url: file, sourceVolume: volumeName, deleteSource: false))
        }
        pump()
    }

    private func scanDropFolder() {
        guard settings.enabled, settings.dropFolderEnabled else { return }
        guard let root = resolveLibraryRoot() else { return }
        let drop = ArchivePaths.dropFolder(in: root)
        try? ArchivePaths.ensureDirectory(drop)
        let files = audioFiles(under: drop)
        for file in files {
            enqueue(PendingIngest(url: file, sourceVolume: "Inbox drop", deleteSource: true))
        }
        if !files.isEmpty { pump() }
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
            if item.lastPathComponent.hasPrefix(".") { continue }
            if item.lastPathComponent.hasPrefix("._") { continue }
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
        guard let libraryRoot = await MainActor.run(body: { self.resolveLibraryRoot() }) else {
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
