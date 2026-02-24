import Foundation
import CoreData

final class PipelineHistoryStore {
    private let container: NSPersistentContainer
    private let isStoreLoaded: Bool

    init() {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "PipelineHistory", managedObjectModel: model)

        var storeURL: URL?
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FreeFlow"
            let baseURL = appSupport.appendingPathComponent(appName, isDirectory: true)
            try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            storeURL = baseURL.appendingPathComponent("PipelineHistory.sqlite")
        }

        if let storeURL {
            let description = NSPersistentStoreDescription(url: storeURL)
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            container.persistentStoreDescriptions = [description]
        } else {
            container.persistentStoreDescriptions = [NSPersistentStoreDescription()]
        }

        if Self.loadPersistentStoresSynchronously(container: container) == nil {
            isStoreLoaded = true
        } else {
            if let storeURL {
                print("[PipelineHistoryStore] Failed to load persistent store at \(storeURL.path). Attempting recovery.")
                Self.destroySQLiteStoreFiles(at: storeURL)

                // Clear any partially loaded stores and reset descriptions before retrying.
                let coordinator = container.persistentStoreCoordinator
                for store in coordinator.persistentStores {
                    try? coordinator.remove(store)
                }

                let recoveryDescription = NSPersistentStoreDescription(url: storeURL)
                recoveryDescription.shouldMigrateStoreAutomatically = true
                recoveryDescription.shouldInferMappingModelAutomatically = true
                container.persistentStoreDescriptions = [recoveryDescription]
            }

            if Self.loadPersistentStoresSynchronously(container: container) == nil {
                isStoreLoaded = true
            } else {
                print("[PipelineHistoryStore] Failed to recover persistent store. Falling back to in-memory history.")
                let description = NSPersistentStoreDescription()
                description.type = NSInMemoryStoreType
                container.persistentStoreDescriptions = [description]
                isStoreLoaded = Self.loadPersistentStoresSynchronously(container: container) == nil
            }
        }
    }

    func loadAllHistory() -> [PipelineHistoryItem] {
        var result: [PipelineHistoryItem] = []
        container.viewContext.performAndWait {
            let request = pipelineHistoryRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            guard let entities = try? container.viewContext.fetch(request) else { return }
            result = entities.compactMap(Self.makeHistoryItem(from:))
        }
        return result
    }

    func append(_ item: PipelineHistoryItem, maxCount: Int) throws -> [String] {
        guard isStoreLoaded else { return [] }
        try insert(item)
        return try trim(to: maxCount)
    }

    func delete(id: UUID) throws -> String? {
        guard isStoreLoaded else { return nil }

        var deletedAudioFileName: String?
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                guard let entity = try container.viewContext.fetch(request).first else { return }
                deletedAudioFileName = entity.audioFileName
                container.viewContext.delete(entity)
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return deletedAudioFileName
    }

    func clearAll() throws -> [String] {
        guard isStoreLoaded else { return [] }

        var audioFileNames: [String] = []
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
                guard let entities = try? container.viewContext.fetch(request) else { return }
                audioFileNames = entities.compactMap(\.audioFileName)
                for entity in entities {
                    container.viewContext.delete(entity)
                }
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return audioFileNames
    }

    func trim(to maxCount: Int) throws -> [String] {
        guard isStoreLoaded else { return [] }
        guard maxCount > 0 else {
            let audioFileNames = try clearAll()
            return audioFileNames
        }

        var audioFileNames: [String] = []
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
                guard let entities = try? container.viewContext.fetch(request), entities.count > maxCount else { return }
                let dropped = entities[maxCount...]
                audioFileNames = dropped.compactMap(\.audioFileName)
                for entity in dropped {
                    container.viewContext.delete(entity)
                }
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return audioFileNames
    }

    private func insert(_ item: PipelineHistoryItem) throws {
        guard isStoreLoaded else { return }

        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
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
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
    }

    private func saveContext() throws {
        guard container.viewContext.hasChanges else { return }
        do {
            try container.viewContext.save()
        } catch {
            container.viewContext.rollback()
            throw error
        }
    }

    private func pipelineHistoryRequest() -> NSFetchRequest<PipelineHistoryEntry> {
        NSFetchRequest<PipelineHistoryEntry>(entityName: "PipelineHistoryEntry")
    }

    private static func loadPersistentStoresSynchronously(container: NSPersistentContainer) -> Error? {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var capturedError: Error?
        var remainingCompletions = max(1, container.persistentStoreDescriptions.count)

        container.loadPersistentStores { _, error in
            lock.lock()
            if capturedError == nil, let error {
                capturedError = error
            }
            remainingCompletions -= 1
            let shouldSignal = remainingCompletions <= 0
            lock.unlock()

            if shouldSignal {
                semaphore.signal()
            }
        }

        semaphore.wait()
        return capturedError
    }

    private static func destroySQLiteStoreFiles(at storeURL: URL) {
        let basePath = storeURL.path
        let fileManager = FileManager.default
        for path in [basePath, basePath + "-wal", basePath + "-shm"] {
            try? fileManager.removeItem(atPath: path)
        }
    }

    private static func makeHistoryItem(from entity: PipelineHistoryEntry) -> PipelineHistoryItem {
        PipelineHistoryItem(
            id: entity.id,
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
