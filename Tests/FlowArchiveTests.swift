import Foundation

enum FlowArchiveTests {
    static func run() {
        testKebabCase()
        testStemAndTimestamps()
        testMarkdownRoundTrip()
        testFolderRouter()
        testVolumeMatcher()
        testCloudDestinationDetection()
        testIngestHasherDedupes()
        testOrganizerJSONParse()
        print("FlowArchiveTests passed")
    }

    private static func testKebabCase() {
        expectEqual(ArchiveMarkdownWriter.kebabCase("Product Launch Strategy"), "product-launch-strategy")
        expectEqual(ArchiveMarkdownWriter.kebabCase("  Hello, World!! "), "hello-world")
        expectEqual(ArchiveMarkdownWriter.kebabCase(""), "untitled-recording")
    }

    private static func testStemAndTimestamps() {
        let date = ArchiveMarkdownWriter.dateFormatter.date(from: "2026-08-17")!
        expectEqual(
            ArchiveMarkdownWriter.stem(date: date, kebabName: "Marketing Budget Thoughts"),
            "2026-08-17_marketing-budget-thoughts"
        )
        expectEqual(ArchiveMarkdownWriter.formatTimestamp(72), "[01:12]")
        expectEqual(ArchiveMarkdownWriter.formatTimestamp(3723), "[1:02:03]")
    }

    private static func testMarkdownRoundTrip() {
        let date = ArchiveMarkdownWriter.dateFormatter.date(from: "2026-08-17")!
        let markdown = ArchiveMarkdownWriter.render(
            frontMatter: ArchiveFrontMatter(
                title: "Marketing Budget Thoughts",
                date: date,
                durationSeconds: 252,
                tags: ["marketing", "budget"],
                audio: "2026-08-17_marketing-budget-thoughts.mp3",
                hash: "sha256:abc",
                sourceVolume: "IC RECORDER"
            ),
            summary: ["Discussed Q3 ad spend shifts.", "Reallocate $10k by Friday."],
            transcript: "[00:00] Hey, so I'm thinking about the marketing budget."
        )
        guard let parsed = ArchiveMarkdownWriter.parse(markdown) else {
            fatalError("Failed to parse rendered markdown")
        }
        expectEqual(parsed.frontMatter.title, "Marketing Budget Thoughts")
        expectEqual(parsed.frontMatter.audio, "2026-08-17_marketing-budget-thoughts.mp3")
        expectEqual(parsed.frontMatter.hash, "sha256:abc")
        expect(parsed.frontMatter.tags == ["marketing", "budget"], "tags mismatch")
        expect(parsed.summary.count == 2, "summary count")
        expect(parsed.transcript.contains("marketing budget"), "transcript missing")
    }

    private static func testFolderRouter() {
        let rules = [
            FolderRule(keyword: "Project X", folder: "Projects/Project X"),
            FolderRule(keyword: "meetings", folder: "Meetings")
        ]
        expectEqual(
            FolderRouter.relativeFolder(tags: ["ideas"], transcript: "Notes from Project X sync", rules: rules),
            "Projects/Project X"
        )
        expectEqual(
            FolderRouter.relativeFolder(tags: ["meetings"], transcript: "weekly", rules: rules),
            "Meetings"
        )
        expectEqual(
            FolderRouter.relativeFolder(tags: ["ideas"], transcript: "random thought", rules: rules),
            "Inbox"
        )
        expectEqual(FolderRouter.sanitizeRelativePath("../secret"), "Inbox")
        expectEqual(FolderRouter.sanitizeRelativePath("Projects/Project X"), "Projects/Project X")
    }

    private static func testVolumeMatcher() {
        expect(RecorderVolumeMatcher.matches(volumeName: "IC RECORDER"), "IC RECORDER should match")
        expect(RecorderVolumeMatcher.matches(volumeName: "RECORDS"), "RECORDS should match")
        expect(RecorderVolumeMatcher.matches(volumeName: "SONY_CARD", extraNames: ["SONY_CARD"]), "extra name")
        expect(!RecorderVolumeMatcher.matches(volumeName: "Macintosh HD"), "internal disk should not match")
        expect(
            RecorderVolumeMatcher.matches(volumeName: "NOPE", hasRecorderStructure: true),
            "structure hint should match"
        )
    }

    private static func testCloudDestinationDetection() {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("fa-home-\(UUID().uuidString)")
        let icloud = home
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let gdrive = home
            .appendingPathComponent("Library/CloudStorage/GoogleDrive-user/My Drive")
        let idrive = home.appendingPathComponent("IDrive")
        try? fm.createDirectory(at: icloud, withIntermediateDirectories: true)
        try? fm.createDirectory(at: gdrive, withIntermediateDirectories: true)
        try? fm.createDirectory(at: idrive, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        expect(CloudDestination.iCloudDriveRoot(home: home, fileManager: fm)?.path == icloud.path, "icloud root")
        let gdriveRoots = CloudDestination.googleDriveRoots(home: home, fileManager: fm)
        expect(gdriveRoots.contains(where: { $0.path.contains("GoogleDrive-") }), "gdrive root")
        expect(CloudDestination.iDriveRoots(home: home, fileManager: fm).contains(where: { $0.path.contains("IDrive") }), "idrive root")

        let options = CloudDestination.options(home: home, fileManager: fm)
        expectEqual(CloudDestination.defaultProvider(from: options).rawValue, "icloud")
        expect(ArchivePaths.libraryRoot(in: icloud).lastPathComponent == "FlowArchive", "library folder name")
        expect(
            ArchivePaths.libraryRoot(in: icloud.appendingPathComponent("FlowArchive")).lastPathComponent == "FlowArchive",
            "do not nest FlowArchive"
        )
    }

    private static func testIngestHasherDedupes() {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("fa-cache-\(UUID().uuidString)")
        try? fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let source = home.appendingPathComponent("take1.mp3")
        try? "audio-bytes".data(using: .utf8)?.write(to: source)

        let hasher = IngestHasher(home: home, fileManager: fm)
        do {
            let first = try hasher.ingestIfNew(url: source)
            expect(first != nil, "first ingest should copy")
            let second = try hasher.ingestIfNew(url: source)
            expect(second == nil, "duplicate ingest should skip")
            let hash = try IngestHasher.sha256Hex(of: source)
            expect(hasher.contains(hash: hash), "manifest should remember hash")
        } catch {
            fatalError("ingest hasher failed: \(error)")
        }
    }

    private static func testOrganizerJSONParse() {
        let raw = """
        ```json
        {"filename":"Product Launch Strategy","summary":["One","Two","Three"],"tags":["#Launch","ideas"]}
        ```
        """
        do {
            let result = try ArchiveOrganizer.parse(raw)
            expectEqual(result.filename, "product-launch-strategy")
            expect(result.summary == ["One", "Two", "Three"], "summary parse")
            expect(result.tags == ["launch", "ideas"], "tag parse")
        } catch {
            fatalError("organizer parse failed: \(error)")
        }
    }

    private static func expectEqual(_ actual: String, _ expected: String, file: StaticString = #file, line: UInt = #line) {
        expect(actual == expected, "Expected \(expected.debugDescription), got \(actual.debugDescription)", file: file, line: line)
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
