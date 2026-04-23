import Foundation

public struct PipelineHistoryItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let rawTranscript: String
    public let finalTranscript: String
    public let modelUsed: String
    public let transcriptionModel: String
    public let systemPrompt: String
    public let note: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawTranscript: String,
        finalTranscript: String,
        modelUsed: String,
        transcriptionModel: String,
        systemPrompt: String,
        note: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawTranscript = rawTranscript
        self.finalTranscript = finalTranscript
        self.modelUsed = modelUsed
        self.transcriptionModel = transcriptionModel
        self.systemPrompt = systemPrompt
        self.note = note
    }
}

public final class PipelineHistoryStore {
    public static let maxItems = 20
    public static let shared = PipelineHistoryStore()

    private let fileURL: URL?
    private let queue = DispatchQueue(label: "com.shebetoff.freeflow.history", attributes: .concurrent)

    public init() {
        if let container = SharedStorage.shared.appGroupContainerURL() {
            self.fileURL = container.appendingPathComponent("pipeline_history.json")
        } else {
            let documents = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            self.fileURL = documents?.appendingPathComponent("pipeline_history.json")
        }
    }

    public func all() -> [PipelineHistoryItem] {
        queue.sync { readFromDisk() }
    }

    public func append(_ item: PipelineHistoryItem) {
        queue.async(flags: .barrier) {
            var items = self.readFromDisk()
            items.insert(item, at: 0)
            if items.count > Self.maxItems {
                items = Array(items.prefix(Self.maxItems))
            }
            self.writeToDisk(items)
        }
    }

    public func remove(id: UUID) {
        queue.async(flags: .barrier) {
            var items = self.readFromDisk()
            items.removeAll { $0.id == id }
            self.writeToDisk(items)
        }
    }

    public func clear() {
        queue.async(flags: .barrier) { self.writeToDisk([]) }
    }

    private func readFromDisk() -> [PipelineHistoryItem] {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PipelineHistoryItem].self, from: data)) ?? []
    }

    private func writeToDisk(_ items: [PipelineHistoryItem]) {
        guard let fileURL else { return }
        let parent = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
