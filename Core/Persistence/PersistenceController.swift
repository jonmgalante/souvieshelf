import CloudKit
import CoreData
import Foundation
import OSLog

final class PersistenceController: @unchecked Sendable {
    enum StoreLoadMode: Sendable {
        case sqlite
        case inMemory
    }

    enum PersistenceError: LocalizedError {
        case missingModel(name: String)
        case missingEntity(name: String)
        case failedToLoadPersistentStore(
            scope: StoreScope,
            storeURL: URL?,
            underlyingError: NSError
        )
        case missingPersistentStore(scope: StoreScope)
        case incompletePersistentStoreMapping

        var errorDescription: String? {
            switch self {
            case .missingModel(let name):
                return "Couldn't locate the Core Data model named \(name)."
            case .missingEntity(let name):
                return "Couldn't locate the Core Data entity named \(name)."
            case let .failedToLoadPersistentStore(scope, storeURL, underlyingError):
                let storePath = storeURL?.path(percentEncoded: false) ?? "memory"
                var components = [
                    "Couldn't load the \(scope.configurationName) persistent store at \(storePath).",
                    "[\(underlyingError.domain) \(underlyingError.code)] \(underlyingError.localizedDescription)"
                ]

                if let failureReason = underlyingError.localizedFailureReason,
                   !failureReason.isEmpty {
                    components.append("Reason: \(failureReason)")
                }

                if let nestedError = underlyingError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    components.append(
                        "Underlying: [\(nestedError.domain) \(nestedError.code)] \(nestedError.localizedDescription)"
                    )
                }

                return components.joined(separator: " ")
            case .missingPersistentStore(let scope):
                return "Couldn't resolve the \(scope.configurationName) persistent store."
            case .incompletePersistentStoreMapping:
                return "Couldn't map all configured persistent stores after loading."
            }
        }
    }

    struct Configuration: Sendable {
        let modelName: String
        let cloudKitContainerIdentifier: String
        let privateStoreFileName: String
        let sharedStoreFileName: String

        static let live = Configuration(
            modelName: "SouvieShelfModel",
            // Assumes the eventual CloudKit container follows the current bundle identifier
            // until project entitlements are finalized in a later task.
            cloudKitContainerIdentifier: "iCloud.com.example.SouvieShelf",
            privateStoreFileName: "SouvieShelf-Private.sqlite",
            sharedStoreFileName: "SouvieShelf-Shared.sqlite"
        )
    }

    let container: NSPersistentCloudKitContainer
    let configuration: Configuration

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    private let logger: Logger
    private let storesByScope: [StoreScope: NSPersistentStore]

    init(
        configuration: Configuration = .live,
        storeLoadMode: StoreLoadMode = .sqlite
    ) throws {
        self.configuration = configuration
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "SouvieShelf",
            category: "Persistence"
        )

        let managedObjectModel = try Self.loadManagedObjectModel(named: configuration.modelName)
        self.container = NSPersistentCloudKitContainer(
            name: configuration.modelName,
            managedObjectModel: managedObjectModel
        )

        let storeURLs = try Self.makeStoreURLs(
            configuration: configuration,
            storeLoadMode: storeLoadMode
        )
        container.persistentStoreDescriptions = [
            Self.makePersistentStoreDescription(
                scope: .privateLibrary,
                configuration: configuration,
                storeLoadMode: storeLoadMode,
                url: storeURLs.privateStoreURL
            ),
            Self.makePersistentStoreDescription(
                scope: .sharedLibrary,
                configuration: configuration,
                storeLoadMode: storeLoadMode,
                url: storeURLs.sharedStoreURL
            )
        ]

        self.storesByScope = try Self.loadPersistentStores(
            in: container,
            logger: logger
        )

        let viewContext = container.viewContext
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.undoManager = nil
        viewContext.name = "SouvieShelf.ViewContext"
    }

    static func live() throws -> PersistenceController {
        try PersistenceController()
    }

    static func inMemory() throws -> PersistenceController {
        try PersistenceController(storeLoadMode: .inMemory)
    }

    func persistentStore(for scope: StoreScope) throws -> NSPersistentStore {
        guard let store = storesByScope[scope] else {
            throw PersistenceError.missingPersistentStore(scope: scope)
        }

        return store
    }

    func storeScope(for store: NSPersistentStore) -> StoreScope? {
        storesByScope.first(where: { $0.value === store })?.key
    }

    func performBackgroundTask<T>(
        _ block: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                context.undoManager = nil
                context.name = "SouvieShelf.BackgroundContext"

                do {
                    continuation.resume(returning: try block(context))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func seedLibrary(
        title: String,
        scope: StoreScope,
        now: Date = .now
    ) throws {
        let store = try persistentStore(for: scope)
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        context.name = "SouvieShelf.SeedContext"

        var thrownError: Error?
        context.performAndWait {
            do {
                guard let entity = NSEntityDescription.entity(forEntityName: "Library", in: context) else {
                    throw PersistenceError.missingEntity(name: "Library")
                }

                let library = Library(entity: entity, insertInto: context)
                library.id = UUID()
                library.title = title
                library.createdAt = now
                library.updatedAt = now

                context.assign(library, to: store)

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
    }

    private static func makePersistentStoreDescription(
        scope: StoreScope,
        configuration: Configuration,
        storeLoadMode: StoreLoadMode,
        url: URL
    ) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.configuration = scope.configurationName
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        switch storeLoadMode {
        case .sqlite:
            let cloudKitOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: configuration.cloudKitContainerIdentifier
            )
            cloudKitOptions.databaseScope = scope == .privateLibrary ? .private : .shared
            description.cloudKitContainerOptions = cloudKitOptions
        case .inMemory:
            description.type = NSInMemoryStoreType
            description.cloudKitContainerOptions = nil
        }

        return description
    }

    private static func makeStoreURLs(
        configuration: Configuration,
        storeLoadMode: StoreLoadMode
    ) throws -> (privateStoreURL: URL, sharedStoreURL: URL) {
        switch storeLoadMode {
        case .sqlite:
            let baseURL = try makeSQLiteStoreDirectoryURL()
            return (
                baseURL.appendingPathComponent(configuration.privateStoreFileName),
                baseURL.appendingPathComponent(configuration.sharedStoreFileName)
            )
        case .inMemory:
            let baseURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SouvieShelf-InMemory", isDirectory: true)
            return (
                baseURL.appendingPathComponent(configuration.privateStoreFileName),
                baseURL.appendingPathComponent(configuration.sharedStoreFileName)
            )
        }
    }

    private static func makeSQLiteStoreDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeDirectoryURL = baseURL.appendingPathComponent("SouvieShelf", isDirectory: true)

        try fileManager.createDirectory(
            at: storeDirectoryURL,
            withIntermediateDirectories: true
        )

        return storeDirectoryURL
    }

    private static func loadPersistentStores(
        in container: NSPersistentCloudKitContainer,
        logger: Logger
    ) throws -> [StoreScope: NSPersistentStore] {
        let coordinator = container.persistentStoreCoordinator
        let lock = NSLock()
        let group = DispatchGroup()
        var firstError: PersistenceError?
        var descriptionsByScope: [StoreScope: NSPersistentStoreDescription] = [:]

        container.persistentStoreDescriptions.forEach { _ in
            group.enter()
        }

        container.loadPersistentStores { description, error in
            defer { group.leave() }

            guard let scope = description.configuration.flatMap(StoreScope.init(configurationName:)) else {
                logger.error("Loaded a persistent store with an unknown configuration.")
                return
            }

            if let error {
                let nsError = error as NSError
                let storePath = description.url?.path(percentEncoded: false) ?? "memory"
                let failureReason = nsError.localizedFailureReason ?? "none"
                logger.error(
                    "Failed loading the \(scope.configurationName, privacy: .public) store at \(storePath, privacy: .public): [\(nsError.domain, privacy: .public) \(nsError.code)] \(nsError.localizedDescription, privacy: .public) reason=\(failureReason, privacy: .public)"
                )
                lock.lock()
                if firstError == nil {
                    firstError = .failedToLoadPersistentStore(
                        scope: scope,
                        storeURL: description.url,
                        underlyingError: nsError
                    )
                }
                lock.unlock()
                return
            }

            let storePath = description.url?.path(percentEncoded: false) ?? "memory"
            logger.info(
                "Loaded the \(scope.configurationName, privacy: .public) store from \(storePath, privacy: .public)"
            )

            lock.lock()
            descriptionsByScope[scope] = description
            lock.unlock()
        }

        group.wait()

        if let firstError {
            throw firstError
        }

        var storesByScope: [StoreScope: NSPersistentStore] = [:]
        for (scope, description) in descriptionsByScope {
            if let url = description.url,
               let store = coordinator.persistentStores.first(where: { $0.url == url }) {
                storesByScope[scope] = store
            }
        }

        let orderedScopes: [StoreScope] = [.privateLibrary, .sharedLibrary]
        for (index, store) in coordinator.persistentStores.enumerated() where index < orderedScopes.count {
            let scope = orderedScopes[index]
            if storesByScope[scope] == nil {
                storesByScope[scope] = store
            }
        }

        guard storesByScope.count == StoreScope.allCases.count else {
            logger.error("Persistent stores loaded but not every scope could be mapped.")
            throw PersistenceError.incompletePersistentStoreMapping
        }

        return storesByScope
    }

    private static func loadManagedObjectModel(named modelName: String) throws -> NSManagedObjectModel {
        let candidateBundles = Self.candidateBundles()

        for bundle in candidateBundles {
            if let modelURL = bundle.url(forResource: modelName, withExtension: "momd")
                ?? bundle.url(forResource: modelName, withExtension: "mom"),
               let model = NSManagedObjectModel(contentsOf: modelURL) {
                return model
            }
        }

        if let mergedModel = NSManagedObjectModel.mergedModel(from: candidateBundles) {
            return mergedModel
        }

        throw PersistenceError.missingModel(name: modelName)
    }

    private static func candidateBundles() -> [Bundle] {
        let bundles = [
            Bundle.main,
            Bundle(for: ModelBundleToken.self)
        ] + Bundle.allFrameworks

        var seenIdentifiers = Set<String>()
        return bundles.filter { bundle in
            let identifier = bundle.bundleURL.path()
            return seenIdentifiers.insert(identifier).inserted
        }
    }
}

private final class ModelBundleToken {}
