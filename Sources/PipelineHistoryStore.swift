import Foundation
import CoreData

final class PipelineHistoryStore {
    private let container: NSPersistentContainer

    init() {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "PipelineHistory", managedObjectModel: model)

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let baseURL = appSupport.appendingPathComponent("FreeFlow", isDirectory: true)
            try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let storeURL = baseURL.appendingPathComponent("PipelineHistory.sqlite")
            let description = NSPersistentStoreDescription(url: storeURL)
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { _, _ in }
    }

    func loadAllHistory() -> [PipelineHistoryItem] {
        let request = pipelineHistoryRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        guard let entities = try? container.viewContext.fetch(request) else {
            return []
        }

        return entities.compactMap(Self.makeHistoryItem(from:))
    }

    func append(_ item: PipelineHistoryItem, maxCount: Int) -> [String] {
        insert(item)
        return trim(to: maxCount)
    }

    func delete(id: UUID) -> String? {
        let request = pipelineHistoryRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? container.viewContext.fetch(request).first else {
            return nil
        }

        let audioFileName = entity.audioFileName
        container.viewContext.delete(entity)
        saveContext()
        return audioFileName
    }

    func clearAll() -> [String] {
        let request = pipelineHistoryRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        guard let entities = try? container.viewContext.fetch(request) else {
            return []
        }

        let audioFileNames = entities.compactMap(\.audioFileName)
        for entity in entities {
            container.viewContext.delete(entity)
        }
        saveContext()
        return audioFileNames
    }

    func trim(to maxCount: Int) -> [String] {
        guard maxCount > 0 else {
            let audioFileNames = clearAll()
            return audioFileNames
        }

        let request = pipelineHistoryRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        guard let entities = try? container.viewContext.fetch(request), entities.count > maxCount else {
            return []
        }

        let dropped = entities[maxCount...]
        let audioFileNames = dropped.compactMap(\.audioFileName)
        for entity in dropped {
            container.viewContext.delete(entity)
        }
        saveContext()
        return audioFileNames
    }

    private func insert(_ item: PipelineHistoryItem) {
        let context = container.viewContext
        let entity = PipelineHistoryEntry(context: context)
        entity.id = item.id
        entity.timestamp = item.timestamp
        entity.rawTranscript = item.rawTranscript
        entity.postProcessedTranscript = item.postProcessedTranscript
        entity.postProcessingPrompt = item.postProcessingPrompt
        entity.contextSummary = item.contextSummary
        entity.contextPrompt = item.contextPrompt
        entity.contextScreenshotDataURL = item.contextScreenshotDataURL
        entity.contextScreenshotStatus = item.contextScreenshotStatus
        entity.postProcessingStatus = item.postProcessingStatus
        entity.debugStatus = item.debugStatus
        entity.customVocabulary = item.customVocabulary
        entity.audioFileName = item.audioFileName
        saveContext()
    }

    private func saveContext() {
        guard container.viewContext.hasChanges else { return }
        try? container.viewContext.save()
    }

    private func pipelineHistoryRequest() -> NSFetchRequest<PipelineHistoryEntry> {
        NSFetchRequest<PipelineHistoryEntry>(entityName: "PipelineHistoryEntry")
    }

    private static func makeHistoryItem(from entity: PipelineHistoryEntry) -> PipelineHistoryItem {
        PipelineHistoryItem(
            timestamp: entity.timestamp ?? Date(),
            rawTranscript: entity.rawTranscript ?? "",
            postProcessedTranscript: entity.postProcessedTranscript ?? "",
            postProcessingPrompt: entity.postProcessingPrompt,
            contextSummary: entity.contextSummary ?? "",
            contextPrompt: entity.contextPrompt,
            contextScreenshotDataURL: entity.contextScreenshotDataURL,
            contextScreenshotStatus: entity.contextScreenshotStatus ?? "available (image)",
            postProcessingStatus: entity.postProcessingStatus ?? "",
            debugStatus: entity.debugStatus ?? "",
            customVocabulary: entity.customVocabulary ?? "",
            audioFileName: entity.audioFileName
        )
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "PipelineHistoryEntry"
        entity.managedObjectClassName = NSStringFromClass(PipelineHistoryEntry.self)

        entity.properties = [
            makeAttribute(name: "id", type: .UUIDAttributeType, isOptional: false),
            makeAttribute(name: "timestamp", type: .dateAttributeType, isOptional: false),
            makeAttribute(name: "rawTranscript", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "postProcessedTranscript", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "postProcessingPrompt", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextSummary", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "contextPrompt", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextScreenshotDataURL", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextScreenshotStatus", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "postProcessingStatus", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "debugStatus", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "customVocabulary", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "audioFileName", type: .stringAttributeType, isOptional: true)
        ]

        model.entities = [entity]
        return model
    }

    private static func makeAttribute(name: String, type: NSAttributeType, isOptional: Bool) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        return attribute
    }
}

@objc(PipelineHistoryEntry)
final class PipelineHistoryEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var timestamp: Date?
    @NSManaged var rawTranscript: String?
    @NSManaged var postProcessedTranscript: String?
    @NSManaged var postProcessingPrompt: String?
    @NSManaged var contextSummary: String?
    @NSManaged var contextPrompt: String?
    @NSManaged var contextScreenshotDataURL: String?
    @NSManaged var contextScreenshotStatus: String?
    @NSManaged var postProcessingStatus: String?
    @NSManaged var debugStatus: String?
    @NSManaged var customVocabulary: String?
    @NSManaged var audioFileName: String?
}
