import CloudKit
import CoreData
import Foundation
import OSLog

protocol ICloudStatusProviding: Sendable {
    func status() async -> ICloudStatus
}

struct CloudKitICloudStatusProvider: ICloudStatusProviding {
    let containerIdentifier: String

    func status() async -> ICloudStatus {
        do {
            let accountStatus = try await CKContainer(identifier: containerIdentifier).accountStatus()
            return accountStatus == .available ? .available : .unavailable
        } catch {
            return .unavailable
        }
    }
}

struct FixedICloudStatusProvider: ICloudStatusProviding {
    let fixedStatus: ICloudStatus

    func status() async -> ICloudStatus {
        fixedStatus
    }
}

enum SharingRepositoryError: LocalizedError {
    case missingLibrary(id: UUID, scope: StoreScope)
    case missingActiveLibrary
    case missingSouvenir(id: UUID, libraryID: UUID, scope: StoreScope)
    case missingTrip(id: UUID, libraryID: UUID, scope: StoreScope)
    case ownerLibraryRequired(scope: StoreScope)
    case cloudKitUnavailable
    case missingShareRecord
    case missingEntity(name: String)
    case missingImportedPhoto
    case invalidTripTitle
    case invalidTripDateRange
    case shareAttachmentMissingObject(objectID: NSManagedObjectID)
    case conflictingExistingShare(objectID: NSManagedObjectID)
    case editPermissionDenied(scope: StoreScope)
    case souvenirRequiresAtLeastOnePhoto
    case invalidPhotoOrdering
    case missingPhotoAsset(id: UUID, souvenirID: UUID)
    case missingAddedPhoto(id: UUID, souvenirID: UUID)

    var errorDescription: String? {
        switch self {
        case .missingLibrary(let id, let scope):
            "Couldn't find library \(id.uuidString) in the \(scope.configurationName) store."
        case .missingActiveLibrary:
            "Couldn't resolve an active library before saving."
        case .missingSouvenir(let id, let libraryID, let scope):
            "Couldn't find souvenir \(id.uuidString) in library \(libraryID.uuidString) for the \(scope.configurationName) store."
        case .missingTrip(let id, let libraryID, let scope):
            "Couldn't find trip \(id.uuidString) in library \(libraryID.uuidString) for the \(scope.configurationName) store."
        case .ownerLibraryRequired(let scope):
            "Only the owner's private library can launch CloudKit sharing. Current scope: \(scope.configurationName)."
        case .cloudKitUnavailable:
            "CloudKit sharing isn't available in the current store configuration."
        case .missingShareRecord:
            "CloudKit didn't return a share record for this library."
        case .missingEntity(let name):
            "Couldn't locate the Core Data entity named \(name)."
        case .missingImportedPhoto:
            "Create souvenir requires at least one imported photo."
        case .invalidTripTitle:
            "Trip title can't be empty."
        case .invalidTripDateRange:
            "End date can't be before the start date."
        case .shareAttachmentMissingObject:
            "Couldn't find a saved child object while attaching it to the library share."
        case .conflictingExistingShare:
            "A child object is already associated with a different CloudKit share."
        case .editPermissionDenied:
            "You don't have permission to edit this library right now."
        case .souvenirRequiresAtLeastOnePhoto:
            "Keep at least one photo on every souvenir."
        case .invalidPhotoOrdering:
            "Couldn't reconcile the updated photo selection."
        case .missingPhotoAsset:
            "Couldn't find one of the existing photos for this souvenir."
        case .missingAddedPhoto:
            "Couldn't prepare one of the newly added photos for saving."
        }
    }
}

final class PersistenceBackedAppBackend: @unchecked Sendable, BootstrapRepository, LibraryRepository, SharingRepository, SouvenirRepository, TripRepository, DeletedRepository, MapRepository {
    private let persistenceController: PersistenceController
    private let iCloudStatusProvider: any ICloudStatusProviding
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SouvieShelf",
        category: "Repositories"
    )

    init(
        persistenceController: PersistenceController,
        iCloudStatusProvider: any ICloudStatusProviding
    ) {
        self.persistenceController = persistenceController
        self.iCloudStatusProvider = iCloudStatusProvider
    }

    func iCloudStatus() async -> ICloudStatus {
        let status = await iCloudStatusProvider.status()
        logger.info("Resolved iCloud availability as \(status.logLabel, privacy: .public)")
        return status
    }

    func resolveLaunchContext() async -> LaunchContextResolution {
        if let context = await libraryContext(in: .sharedLibrary) {
            logger.info("Launch resolution selected the shared-library branch.")
            return .ready(context)
        }

        if let context = await libraryContext(in: .privateLibrary) {
            logger.info("Launch resolution selected the private-library branch.")
            return .ready(context)
        }

        logger.info("Launch resolution selected the first-run branch because no library exists yet.")
        return .needsPairing
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard supportsCloudKitSharing else {
            throw SharingRepositoryError.cloudKitUnavailable
        }

        let sharedStore = try persistenceController.persistentStore(for: .sharedLibrary)
        logger.info(
            "Accepting CloudKit share metadata into the shared store for container \(metadata.containerIdentifier, privacy: .public)."
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            persistenceController.container.acceptShareInvitations(
                from: [metadata],
                into: sharedStore
            ) { acceptedMetadata, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let acceptedCount = acceptedMetadata?.count ?? 0
                self.logger.info(
                    "Core Data accepted \(acceptedCount, privacy: .public) CloudKit share invitation record(s)."
                )
                continuation.resume(returning: ())
            }
        }

        logger.info("Accepted CloudKit share metadata into the shared store.")
        await waitForSharedLibraryImport()
    }

    func createLibrary(title: String) async throws -> ActiveLibraryContext {
        let now = Date()
        let libraryID = UUID()
        let privateStore = try persistenceController.persistentStore(for: .privateLibrary)

        do {
            let context = try await persistenceController.performBackgroundTask { context in
                guard let entity = NSEntityDescription.entity(forEntityName: "Library", in: context) else {
                    throw PersistenceController.PersistenceError.missingEntity(name: "Library")
                }

                let library = Library(entity: entity, insertInto: context)
                library.id = libraryID
                library.title = title
                library.createdAt = now
                library.updatedAt = now

                context.assign(library, to: privateStore)

                if context.hasChanges {
                    try context.save()
                }

                return Self.makeActiveLibraryContext(
                    libraryID: libraryID,
                    libraryTitle: title,
                    scope: .privateLibrary,
                    shareSummary: Self.makeFallbackShareSummary(
                        libraryTitle: title,
                        scope: .privateLibrary
                    )
                )
            }

            logger.info(
                "Created library \(context.libraryID.uuidString, privacy: .public) in the private store."
            )
            return context
        } catch {
            logger.error("Failed creating the private library: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func activeLibraryContext() async -> ActiveLibraryContext? {
        if let sharedContext = await libraryContext(in: .sharedLibrary) {
            return sharedContext
        }

        return await libraryContext(in: .privateLibrary)
    }

    func libraryContext(in scope: StoreScope) async -> ActiveLibraryContext? {
        do {
            guard let snapshot = try await fetchPreferredLibrarySnapshot(in: scope) else {
                return nil
            }

            if snapshot.totalLibraryCount > 1 {
                logger.warning(
                    "Detected \(snapshot.totalLibraryCount, privacy: .public) libraries in the \(scope.logLabel, privacy: .public) store. Using the earliest-created library."
                )
            }

            let shareSummary = await fetchShareSummary(libraryID: snapshot.libraryID, scope: scope)
                ?? Self.makeFallbackShareSummary(libraryTitle: snapshot.libraryTitle, scope: scope)

            return Self.makeActiveLibraryContext(
                libraryID: snapshot.libraryID,
                libraryTitle: snapshot.libraryTitle,
                scope: scope,
                shareSummary: shareSummary
            )
        } catch {
            logger.error(
                "Failed fetching the active library from the \(scope.logLabel, privacy: .public) scope: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    func fetchShareSummary(libraryID: UUID, scope: StoreScope) async -> ShareSummary? {
        do {
            guard let snapshot = try await fetchLibrarySnapshot(libraryID: libraryID, scope: scope) else {
                return nil
            }

            guard supportsCloudKitSharing else {
                return Self.makeFallbackShareSummary(
                    libraryTitle: snapshot.libraryTitle,
                    scope: scope
                )
            }

            let existingShare = try await fetchExistingLibraryShare(libraryID: libraryID, scope: scope)
            if let existingShare {
                let nonOwnerParticipantCount = existingShare.participants.filter {
                    $0.role != .owner && $0.acceptanceStatus != .removed
                }.count
                if nonOwnerParticipantCount > 1 {
                    logger.warning(
                        "Detected \(nonOwnerParticipantCount, privacy: .public) non-owner participants on library \(libraryID.uuidString, privacy: .public). SouvieShelf will keep presenting a single-partner summary."
                    )
                }

                logger.info(
                    "Fetched existing CloudKit share metadata for library \(libraryID.uuidString, privacy: .public) in the \(scope.logLabel, privacy: .public) store."
                )
                return Self.makeShareSummary(
                    libraryTitle: snapshot.libraryTitle,
                    scope: scope,
                    share: existingShare
                )
            }

            logger.info(
                "No existing CloudKit share metadata exists for library \(libraryID.uuidString, privacy: .public) in the \(scope.logLabel, privacy: .public) store."
            )
            return Self.makeUnsharedLibrarySummary(
                libraryTitle: snapshot.libraryTitle,
                scope: scope
            )
        } catch {
            logger.error(
                "Failed fetching CloudKit share metadata for library \(libraryID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )

            if let snapshot = try? await fetchLibrarySnapshot(libraryID: libraryID, scope: scope) {
                return Self.makeFallbackShareSummary(
                    libraryTitle: snapshot.libraryTitle,
                    scope: scope
                )
            }

            return nil
        }
    }

    @MainActor
    func prepareShareController(
        libraryID: UUID,
        scope: StoreScope
    ) async throws -> LibraryShareControllerContext {
        guard scope == .privateLibrary else {
            throw SharingRepositoryError.ownerLibraryRequired(scope: scope)
        }

        guard supportsCloudKitSharing else {
            throw SharingRepositoryError.cloudKitUnavailable
        }

        guard let snapshot = try await fetchLibrarySnapshot(libraryID: libraryID, scope: scope) else {
            throw SharingRepositoryError.missingLibrary(id: libraryID, scope: scope)
        }

        let share: CKShare
        if let existingShare = try await fetchExistingLibraryShare(libraryID: libraryID, scope: scope) {
            logger.info(
                "Preparing native share UI using the existing library share for \(libraryID.uuidString, privacy: .public)."
            )
            share = try await normalizeShare(existingShare, libraryTitle: snapshot.libraryTitle, scope: scope)
        } else {
            logger.info(
                "Creating a new library share for \(libraryID.uuidString, privacy: .public) before presenting native share UI."
            )
            share = try await createLibraryShare(
                libraryID: libraryID,
                scope: scope,
                libraryTitle: snapshot.libraryTitle
            )
        }

        logger.info(
            "Prepared native CloudKit share presentation for library \(libraryID.uuidString, privacy: .public)."
        )
        return LibraryShareControllerContext(
            libraryID: libraryID,
            libraryTitle: snapshot.libraryTitle,
            share: share,
            container: cloudKitContainer
        )
    }

    func attachObjectsToLibraryShareIfNeeded(
        objectIDs: [NSManagedObjectID],
        libraryID: UUID,
        scope: StoreScope
    ) async throws {
        guard !objectIDs.isEmpty else {
            return
        }

        guard scope == .privateLibrary else {
            return
        }

        guard supportsCloudKitSharing else {
            logger.info("Skipping library share attachment because CloudKit sharing is unavailable.")
            return
        }

        guard let existingShare = try await fetchExistingLibraryShare(libraryID: libraryID, scope: scope) else {
            logger.info(
                "Skipping library share attachment for \(objectIDs.count, privacy: .public) object(s) because the library does not have an existing share."
            )
            return
        }

        logger.info(
            "Attaching \(objectIDs.count, privacy: .public) new owner-side object(s) to the existing library share for \(libraryID.uuidString, privacy: .public)."
        )

        try await withCheckedThrowingContinuation { continuation in
            let context = makeBackgroundContext(named: "SouvieShelf.ShareAttachContext")
            context.perform {
                do {
                    let existingShareMap = try self.persistenceController.container.fetchShares(matching: objectIDs)
                    var unresolvedObjects: [NSManagedObject] = []

                    for objectID in objectIDs {
                        if let existingObjectShare = existingShareMap[objectID] {
                            guard existingObjectShare.recordID == existingShare.recordID else {
                                throw SharingRepositoryError.conflictingExistingShare(objectID: objectID)
                            }

                            continue
                        }

                        guard let object = try? context.existingObject(with: objectID) else {
                            throw SharingRepositoryError.shareAttachmentMissingObject(objectID: objectID)
                        }

                        unresolvedObjects.append(object)
                    }

                    guard !unresolvedObjects.isEmpty else {
                        continuation.resume(returning: ())
                        return
                    }

                    // Core Data performs its own traversal when adding objects to an existing share.
                    // Manual QA should confirm that newly saved child objects join the library share
                    // without re-sharing already shared ancestors in a conflicting way.
                    self.persistenceController.container.share(
                        unresolvedObjects,
                        to: existingShare
                    ) { _, share, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        guard share != nil else {
                            continuation.resume(throwing: SharingRepositoryError.missingShareRecord)
                            return
                        }

                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        logger.info(
            "Attached \(objectIDs.count, privacy: .public) object(s) to the existing library share for \(libraryID.uuidString, privacy: .public)."
        )
    }

    func createSouvenir(_ input: CreateSouvenirInput) async throws -> UUID {
        guard !input.photos.isEmpty else {
            throw SharingRepositoryError.missingImportedPhoto
        }

        let activeLibraryContext = input.libraryContext
        let now = Date()
        let createdObjectIDs = try await withCheckedThrowingContinuation { continuation in
            let context = makeBackgroundContext(named: "SouvieShelf.CreateSouvenirContext")
            context.perform {
                do {
                    let store = try self.persistenceController.persistentStore(for: activeLibraryContext.storeScope)
                    guard let souvenirEntity = NSEntityDescription.entity(
                        forEntityName: "Souvenir",
                        in: context
                    ) else {
                        throw SharingRepositoryError.missingEntity(name: "Souvenir")
                    }

                    guard let library = try self.fetchLibrary(
                        libraryID: activeLibraryContext.libraryID,
                        scope: activeLibraryContext.storeScope,
                        in: context
                    ) else {
                        throw SharingRepositoryError.missingLibrary(
                            id: activeLibraryContext.libraryID,
                            scope: activeLibraryContext.storeScope
                        )
                    }

                    let souvenir = Souvenir(entity: souvenirEntity, insertInto: context)
                    souvenir.id = input.id
                    souvenir.title = Self.normalizedOptionalString(input.title)
                    souvenir.story = Self.normalizedOptionalString(input.story)
                    souvenir.acquiredDate = input.acquiredOn
                    souvenir.createdAt = now
                    souvenir.updatedAt = now
                    souvenir.library = library

                    Self.apply(place: input.gotItInPlace, to: souvenir, kind: .gotItIn)
                    Self.apply(place: input.fromPlace, to: souvenir, kind: .from)

                    if let tripID = input.tripID {
                        guard let trip = try self.fetchTrip(
                            tripID: tripID,
                            libraryID: activeLibraryContext.libraryID,
                            scope: activeLibraryContext.storeScope,
                            in: context
                        ) else {
                            throw SharingRepositoryError.missingTrip(
                                id: tripID,
                                libraryID: activeLibraryContext.libraryID,
                                scope: activeLibraryContext.storeScope
                            )
                        }

                        souvenir.trip = trip
                    }

                    var createdObjects: [NSManagedObject] = [souvenir]
                    createdObjects.reserveCapacity(input.photos.count + 1)

                    guard let photoAssetEntity = NSEntityDescription.entity(
                        forEntityName: "PhotoAsset",
                        in: context
                    ) else {
                        throw SharingRepositoryError.missingEntity(name: "PhotoAsset")
                    }

                    for (index, photo) in input.photos.enumerated() {
                        let asset = PhotoAsset(entity: photoAssetEntity, insertInto: context)
                        asset.id = photo.id
                        asset.createdAt = now
                        asset.displayImageData = photo.displayImageData
                        asset.thumbnailData = photo.thumbnailData
                        asset.pixelWidth = photo.pixelWidth
                        asset.pixelHeight = photo.pixelHeight
                        asset.isPrimary = index == 0
                        asset.sortIndex = Int16(index)
                        asset.souvenir = souvenir
                        context.assign(asset, to: store)
                        createdObjects.append(asset)
                    }

                    library.updatedAt = now
                    context.assign(souvenir, to: store)
                    try context.obtainPermanentIDs(for: Array(context.insertedObjects))

                    if context.hasChanges {
                        try context.save()
                    }

                    let createdObjectIDs = createdObjects.map(\.objectID)
                    if createdObjectIDs.contains(where: \.isTemporaryID) {
                        throw SharingRepositoryError.shareAttachmentMissingObject(objectID: souvenir.objectID)
                    }

                    continuation.resume(returning: createdObjectIDs)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        try await attachObjectsToLibraryShareIfNeeded(
            objectIDs: createdObjectIDs,
            libraryID: activeLibraryContext.libraryID,
            scope: activeLibraryContext.storeScope
        )

        logger.info(
            "Created souvenir \(input.id.uuidString, privacy: .public) in the \(activeLibraryContext.storeScope.logLabel, privacy: .public) library."
        )
        return input.id
    }

    func canEditSouvenir(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async -> Bool {
        do {
            return try await persistenceController.performBackgroundTask { context in
                context.name = "SouvieShelf.CanEditSouvenirContext"
                guard let souvenir = try self.fetchSouvenir(
                    souvenirID: id,
                    libraryID: libraryContext.libraryID,
                    scope: libraryContext.storeScope,
                    includeSoftDeleted: false,
                    in: context
                ) else {
                    return false
                }

                guard let library = souvenir.library else {
                    return false
                }

                return try self.currentUserCanWrite(
                    library: library,
                    scope: libraryContext.storeScope
                )
            }
        } catch {
            logger.error(
                "Failed resolving edit permission for souvenir \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func updateSouvenir(_ input: UpdateSouvenirInput) async throws {
        guard !input.photoOrder.isEmpty else {
            throw SharingRepositoryError.souvenirRequiresAtLeastOnePhoto
        }

        let activeLibraryContext = input.libraryContext
        let now = Date()
        let newPhotoObjectIDs = try await persistenceController.performBackgroundTask { context in
            context.name = "SouvieShelf.UpdateSouvenirContext"

            let store = try self.persistenceController.persistentStore(for: activeLibraryContext.storeScope)
            guard let souvenir = try self.fetchSouvenir(
                souvenirID: input.souvenirID,
                libraryID: activeLibraryContext.libraryID,
                scope: activeLibraryContext.storeScope,
                includeSoftDeleted: false,
                in: context
            ) else {
                throw SharingRepositoryError.missingSouvenir(
                    id: input.souvenirID,
                    libraryID: activeLibraryContext.libraryID,
                    scope: activeLibraryContext.storeScope
                )
            }

            guard let library = souvenir.library else {
                throw SharingRepositoryError.missingLibrary(
                    id: activeLibraryContext.libraryID,
                    scope: activeLibraryContext.storeScope
                )
            }

            guard try self.currentUserCanWrite(
                library: library,
                scope: activeLibraryContext.storeScope
            ) else {
                throw SharingRepositoryError.editPermissionDenied(scope: activeLibraryContext.storeScope)
            }

            let requestedPhotoIDs = input.photoOrder
            let requestedPhotoIDSet = Set(requestedPhotoIDs)
            guard requestedPhotoIDSet.count == requestedPhotoIDs.count,
                  requestedPhotoIDSet.contains(input.primaryPhotoID) else {
                throw SharingRepositoryError.invalidPhotoOrdering
            }

            let existingPhotos = ((souvenir.photos as? Set<PhotoAsset>) ?? [])
            let existingPhotosByID = Dictionary(
                uniqueKeysWithValues: existingPhotos.compactMap { asset in
                    asset.id.map { ($0, asset) }
                }
            )

            var addedPhotosByID: [UUID: ImportedPhoto] = [:]
            for addedPhoto in input.addedPhotos {
                guard addedPhotosByID.updateValue(addedPhoto, forKey: addedPhoto.id) == nil else {
                    throw SharingRepositoryError.invalidPhotoOrdering
                }
            }

            let existingPhotoIDs = Set(existingPhotosByID.keys)
            let addedPhotoIDs = Set(addedPhotosByID.keys)
            guard existingPhotoIDs.isDisjoint(with: addedPhotoIDs) else {
                throw SharingRepositoryError.invalidPhotoOrdering
            }
            let expectedPhotoIDs = existingPhotoIDs.intersection(requestedPhotoIDSet).union(addedPhotoIDs)

            guard expectedPhotoIDs == requestedPhotoIDSet,
                  addedPhotoIDs.isSubset(of: requestedPhotoIDSet) else {
                throw SharingRepositoryError.invalidPhotoOrdering
            }

            if let tripID = input.tripID {
                guard let trip = try self.fetchTrip(
                    tripID: tripID,
                    libraryID: activeLibraryContext.libraryID,
                    scope: activeLibraryContext.storeScope,
                    in: context
                ) else {
                    throw SharingRepositoryError.missingTrip(
                        id: tripID,
                        libraryID: activeLibraryContext.libraryID,
                        scope: activeLibraryContext.storeScope
                    )
                }

                souvenir.trip = trip
            } else {
                souvenir.trip = nil
            }

            souvenir.title = Self.normalizedOptionalString(input.title)
            souvenir.story = Self.normalizedOptionalString(input.story)
            souvenir.acquiredDate = input.acquiredOn
            souvenir.updatedAt = now
            library.updatedAt = now

            Self.apply(place: input.gotItInPlace, to: souvenir, kind: .gotItIn)
            Self.apply(place: input.fromPlace, to: souvenir, kind: .from)

            let removedPhotoIDs = existingPhotoIDs.subtracting(requestedPhotoIDSet)
            for removedPhotoID in removedPhotoIDs {
                guard let asset = existingPhotosByID[removedPhotoID] else {
                    throw SharingRepositoryError.missingPhotoAsset(
                        id: removedPhotoID,
                        souvenirID: input.souvenirID
                    )
                }

                context.delete(asset)
            }

            guard let photoAssetEntity = NSEntityDescription.entity(
                forEntityName: "PhotoAsset",
                in: context
            ) else {
                throw SharingRepositoryError.missingEntity(name: "PhotoAsset")
            }

            var newPhotoAssets: [PhotoAsset] = []
            var resolvedPhotosByID = existingPhotosByID

            for addedPhotoID in addedPhotoIDs {
                guard let addedPhoto = addedPhotosByID[addedPhotoID] else {
                    throw SharingRepositoryError.missingAddedPhoto(
                        id: addedPhotoID,
                        souvenirID: input.souvenirID
                    )
                }

                let asset = PhotoAsset(entity: photoAssetEntity, insertInto: context)
                asset.id = addedPhoto.id
                asset.createdAt = now
                asset.displayImageData = addedPhoto.displayImageData
                asset.thumbnailData = addedPhoto.thumbnailData
                asset.pixelWidth = addedPhoto.pixelWidth
                asset.pixelHeight = addedPhoto.pixelHeight
                asset.souvenir = souvenir
                context.assign(asset, to: store)
                newPhotoAssets.append(asset)
                resolvedPhotosByID[addedPhotoID] = asset
            }

            for (index, photoID) in requestedPhotoIDs.enumerated() {
                guard let asset = resolvedPhotosByID[photoID] else {
                    throw SharingRepositoryError.invalidPhotoOrdering
                }

                asset.sortIndex = Int16(index)
                asset.isPrimary = photoID == input.primaryPhotoID
            }

            try context.obtainPermanentIDs(for: newPhotoAssets)

            if context.hasChanges {
                try context.save()
            }

            let objectIDs = newPhotoAssets.map(\.objectID)
            if objectIDs.contains(where: \.isTemporaryID) {
                throw SharingRepositoryError.shareAttachmentMissingObject(objectID: souvenir.objectID)
            }

            return objectIDs
        }

        try await attachObjectsToLibraryShareIfNeeded(
            objectIDs: newPhotoObjectIDs,
            libraryID: activeLibraryContext.libraryID,
            scope: activeLibraryContext.storeScope
        )

        logger.info(
            "Updated souvenir \(input.souvenirID.uuidString, privacy: .public) in the \(activeLibraryContext.storeScope.logLabel, privacy: .public) library."
        )
    }

    func createTrip(_ input: CreateTripInput) async throws -> UUID {
        let title = Self.normalizedOptionalString(input.title)
        guard let title else {
            throw SharingRepositoryError.invalidTripTitle
        }

        let activeLibraryContext = input.libraryContext
        let now = Date()
        let createdObjectID = try await withCheckedThrowingContinuation { continuation in
            let context = makeBackgroundContext(named: "SouvieShelf.CreateTripContext")
            context.perform {
                do {
                    let store = try self.persistenceController.persistentStore(for: activeLibraryContext.storeScope)
                    guard let tripEntity = NSEntityDescription.entity(
                        forEntityName: "Trip",
                        in: context
                    ) else {
                        throw SharingRepositoryError.missingEntity(name: "Trip")
                    }

                    guard let library = try self.fetchLibrary(
                        libraryID: activeLibraryContext.libraryID,
                        scope: activeLibraryContext.storeScope,
                        in: context
                    ) else {
                        throw SharingRepositoryError.missingLibrary(
                            id: activeLibraryContext.libraryID,
                            scope: activeLibraryContext.storeScope
                        )
                    }

                    let trip = Trip(entity: tripEntity, insertInto: context)
                    trip.id = input.id
                    trip.title = title
                    trip.destinationSummary = Self.normalizedOptionalString(input.destinationSummary)
                    trip.startDate = input.startDate
                    trip.endDate = input.endDate
                    trip.createdAt = now
                    trip.updatedAt = now
                    trip.library = library

                    library.updatedAt = now
                    context.assign(trip, to: store)
                    try context.obtainPermanentIDs(for: [trip])

                    if context.hasChanges {
                        try context.save()
                    }

                    continuation.resume(returning: trip.objectID)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        try await attachObjectsToLibraryShareIfNeeded(
            objectIDs: [createdObjectID],
            libraryID: activeLibraryContext.libraryID,
            scope: activeLibraryContext.storeScope
        )

        logger.info(
            "Created trip \(input.id.uuidString, privacy: .public) in the \(activeLibraryContext.storeScope.logLabel, privacy: .public) library."
        )
        return input.id
    }

    func canEditTrip(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async -> Bool {
        do {
            return try await persistenceController.performBackgroundTask { context in
                context.name = "SouvieShelf.CanEditTripContext"

                guard let trip = try self.fetchTrip(
                    tripID: id,
                    libraryID: libraryContext.libraryID,
                    scope: libraryContext.storeScope,
                    in: context
                ) else {
                    return false
                }

                guard let library = trip.library else {
                    return false
                }

                return try self.currentUserCanWrite(
                    library: library,
                    scope: libraryContext.storeScope
                )
            }
        } catch {
            logger.error(
                "Failed resolving edit permission for trip \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func updateTrip(_ input: UpdateTripInput) async throws {
        let activeLibraryContext = input.libraryContext
        guard let normalizedTitle = Self.normalizedOptionalString(input.title) else {
            throw SharingRepositoryError.invalidTripTitle
        }

        if let startDate = input.startDate,
           let endDate = input.endDate,
           endDate < startDate {
            throw SharingRepositoryError.invalidTripDateRange
        }

        let now = Date()
        try await persistenceController.performBackgroundTask { context in
            context.name = "SouvieShelf.UpdateTripContext"

            guard let trip = try self.fetchTrip(
                tripID: input.tripID,
                libraryID: activeLibraryContext.libraryID,
                scope: activeLibraryContext.storeScope,
                in: context
            ) else {
                throw SharingRepositoryError.missingTrip(
                    id: input.tripID,
                    libraryID: activeLibraryContext.libraryID,
                    scope: activeLibraryContext.storeScope
                )
            }

            guard let library = trip.library else {
                throw SharingRepositoryError.missingLibrary(
                    id: activeLibraryContext.libraryID,
                    scope: activeLibraryContext.storeScope
                )
            }

            guard try self.currentUserCanWrite(
                library: library,
                scope: activeLibraryContext.storeScope
            ) else {
                throw SharingRepositoryError.editPermissionDenied(scope: activeLibraryContext.storeScope)
            }

            trip.title = normalizedTitle
            trip.destinationSummary = Self.normalizedOptionalString(input.destinationSummary)
            trip.startDate = input.startDate
            trip.endDate = input.endDate
            trip.updatedAt = now
            library.updatedAt = now

            if context.hasChanges {
                try context.save()
            }
        }

        logger.info(
            "Updated trip \(input.tripID.uuidString, privacy: .public) in the \(activeLibraryContext.storeScope.logLabel, privacy: .public) library."
        )
    }

    func softDeleteTrip(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async throws {
        let now = Date()

        try await persistenceController.performBackgroundTask { context in
            context.name = "SouvieShelf.SoftDeleteTripContext"

            guard let trip = try self.fetchTrip(
                tripID: id,
                libraryID: libraryContext.libraryID,
                scope: libraryContext.storeScope,
                includeSoftDeleted: true,
                in: context
            ) else {
                throw SharingRepositoryError.missingTrip(
                    id: id,
                    libraryID: libraryContext.libraryID,
                    scope: libraryContext.storeScope
                )
            }

            guard let library = trip.library else {
                throw SharingRepositoryError.missingLibrary(
                    id: libraryContext.libraryID,
                    scope: libraryContext.storeScope
                )
            }

            guard try self.currentUserCanWrite(
                library: library,
                scope: libraryContext.storeScope
            ) else {
                throw SharingRepositoryError.editPermissionDenied(scope: libraryContext.storeScope)
            }

            guard trip.deletedAt == nil else {
                return
            }

            trip.deletedAt = now
            trip.updatedAt = now
            library.updatedAt = now

            if context.hasChanges {
                try context.save()
            }
        }

        logger.info(
            "Soft-deleted trip \(id.uuidString, privacy: .public) in the \(libraryContext.storeScope.logLabel, privacy: .public) library."
        )
    }

    func softDeleteSouvenir(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async throws {
        let now = Date()

        try await persistenceController.performBackgroundTask { context in
            context.name = "SouvieShelf.SoftDeleteSouvenirContext"

            guard let souvenir = try self.fetchSouvenir(
                souvenirID: id,
                libraryID: libraryContext.libraryID,
                scope: libraryContext.storeScope,
                includeSoftDeleted: true,
                in: context
            ) else {
                throw SharingRepositoryError.missingSouvenir(
                    id: id,
                    libraryID: libraryContext.libraryID,
                    scope: libraryContext.storeScope
                )
            }

            guard let library = souvenir.library else {
                throw SharingRepositoryError.missingLibrary(
                    id: libraryContext.libraryID,
                    scope: libraryContext.storeScope
                )
            }

            guard try self.currentUserCanWrite(
                library: library,
                scope: libraryContext.storeScope
            ) else {
                throw SharingRepositoryError.editPermissionDenied(scope: libraryContext.storeScope)
            }

            guard souvenir.deletedAt == nil else {
                return
            }

            souvenir.deletedAt = now
            souvenir.updatedAt = now
            library.updatedAt = now

            if context.hasChanges {
                try context.save()
            }
        }

        logger.info(
            "Soft-deleted souvenir \(id.uuidString, privacy: .public) in the \(libraryContext.storeScope.logLabel, privacy: .public) library."
        )
    }

    func restoreSouvenir(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async throws {
        let now = Date()

        try await persistenceController.performBackgroundTask { context in
            context.name = "SouvieShelf.RestoreSouvenirContext"

            guard let souvenir = try self.fetchSouvenir(
                souvenirID: id,
                libraryID: libraryContext.libraryID,
                scope: libraryContext.storeScope,
                includeSoftDeleted: true,
                in: context
            ) else {
                throw SharingRepositoryError.missingSouvenir(
                    id: id,
                    libraryID: libraryContext.libraryID,
                    scope: libraryContext.storeScope
                )
            }

            guard let library = souvenir.library else {
                throw SharingRepositoryError.missingLibrary(
                    id: libraryContext.libraryID,
                    scope: libraryContext.storeScope
                )
            }

            guard try self.currentUserCanWrite(
                library: library,
                scope: libraryContext.storeScope
            ) else {
                throw SharingRepositoryError.editPermissionDenied(scope: libraryContext.storeScope)
            }

            guard souvenir.deletedAt != nil else {
                self.logger.warning(
                    "Skipped restoring souvenir \(id.uuidString, privacy: .public) because it is already active in the \(libraryContext.storeScope.logLabel, privacy: .public) library."
                )
                return
            }

            souvenir.deletedAt = nil
            souvenir.updatedAt = now
            library.updatedAt = now

            if context.hasChanges {
                try context.save()
            }
        }

        logger.info(
            "Restored souvenir \(id.uuidString, privacy: .public) in the \(libraryContext.storeScope.logLabel, privacy: .public) library."
        )
    }

    func restoreTrip(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async throws {
        let now = Date()

        try await persistenceController.performBackgroundTask { context in
            context.name = "SouvieShelf.RestoreTripContext"

            guard let trip = try self.fetchTrip(
                tripID: id,
                libraryID: libraryContext.libraryID,
                scope: libraryContext.storeScope,
                includeSoftDeleted: true,
                in: context
            ) else {
                throw SharingRepositoryError.missingTrip(
                    id: id,
                    libraryID: libraryContext.libraryID,
                    scope: libraryContext.storeScope
                )
            }

            guard let library = trip.library else {
                throw SharingRepositoryError.missingLibrary(
                    id: libraryContext.libraryID,
                    scope: libraryContext.storeScope
                )
            }

            guard try self.currentUserCanWrite(
                library: library,
                scope: libraryContext.storeScope
            ) else {
                throw SharingRepositoryError.editPermissionDenied(scope: libraryContext.storeScope)
            }

            guard trip.deletedAt != nil else {
                self.logger.warning(
                    "Skipped restoring trip \(id.uuidString, privacy: .public) because it is already active in the \(libraryContext.storeScope.logLabel, privacy: .public) library."
                )
                return
            }

            trip.deletedAt = nil
            trip.updatedAt = now
            library.updatedAt = now

            if context.hasChanges {
                try context.save()
            }
        }

        logger.info(
            "Restored trip \(id.uuidString, privacy: .public) in the \(libraryContext.storeScope.logLabel, privacy: .public) library."
        )
    }

    func souvenirFetchRequest(
        for context: MapFilterContext,
        activeLibraryContext: ActiveLibraryContext
    ) -> NSFetchRequest<Souvenir> {
        let request = Souvenir.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.relationshipKeyPathsForPrefetching = ["photos", "trip"]

        var predicates: [NSPredicate] = [
            NSPredicate(format: "library.id == %@", activeLibraryContext.libraryID as CVarArg),
            NSPredicate(format: "deletedAt == NIL"),
            NSPredicate(format: "gotItInLatitude != 0 OR gotItInLongitude != 0")
        ]

        if let tripID = context.tripID {
            predicates.append(
                NSPredicate(format: "trip.id == %@", tripID as CVarArg)
            )
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        applyMapStoreScope(
            to: request,
            activeLibraryContext: activeLibraryContext,
            expectedScope: context.storeScope
        )
        return request
    }

    func tripFetchRequest(
        tripID: UUID,
        activeLibraryContext: ActiveLibraryContext
    ) -> NSFetchRequest<Trip> {
        let request = Trip.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", tripID as CVarArg),
                NSPredicate(format: "library.id == %@", activeLibraryContext.libraryID as CVarArg),
                NSPredicate(format: "deletedAt == NIL")
            ]
        )
        applyMapStoreScope(
            to: request,
            activeLibraryContext: activeLibraryContext,
            expectedScope: activeLibraryContext.storeScope
        )
        return request
    }

    private var supportsCloudKitSharing: Bool {
        persistenceController.container.persistentStoreDescriptions.contains {
            $0.cloudKitContainerOptions != nil
        }
    }

    private var cloudKitContainer: CKContainer {
        CKContainer(identifier: persistenceController.configuration.cloudKitContainerIdentifier)
    }

    private func waitForSharedLibraryImport() async {
        for attempt in 1...10 {
            if await libraryContext(in: .sharedLibrary) != nil {
                logger.info(
                    "Shared library resolved successfully after share acceptance on attempt \(attempt, privacy: .public)."
                )
                return
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        logger.warning("Accepted CloudKit share metadata, but the shared library has not resolved yet.")
    }

    private func fetchPreferredLibrarySnapshot(in scope: StoreScope) async throws -> LibrarySnapshot? {
        let store = try persistenceController.persistentStore(for: scope)
        return try await persistenceController.performBackgroundTask { context in
            let request = Library.fetchRequest()
            request.fetchLimit = 2
            request.affectedStores = [store]
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: true),
                NSSortDescriptor(key: "updatedAt", ascending: true)
            ]

            let libraries = try context.fetch(request)
            guard let library = libraries.first,
                  let libraryID = library.id,
                  let libraryTitle = library.title else {
                return nil
            }

            return LibrarySnapshot(
                libraryID: libraryID,
                libraryTitle: libraryTitle,
                totalLibraryCount: libraries.count
            )
        }
    }

    private func applyMapStoreScope<ResultType: NSManagedObject>(
        to request: NSFetchRequest<ResultType>,
        activeLibraryContext: ActiveLibraryContext,
        expectedScope: StoreScope
    ) {
        guard activeLibraryContext.storeScope == expectedScope,
              let store = try? persistenceController.persistentStore(for: activeLibraryContext.storeScope) else {
            request.predicate = NSCompoundPredicate(
                andPredicateWithSubpredicates: [
                    request.predicate ?? NSPredicate(value: true),
                    NSPredicate(value: false)
                ]
            )
            return
        }

        request.affectedStores = [store]
    }

    private func fetchLibrarySnapshot(
        libraryID: UUID,
        scope: StoreScope
    ) async throws -> LibrarySnapshot? {
        return try await persistenceController.performBackgroundTask { context in
            guard let library = try self.fetchLibrary(
                libraryID: libraryID,
                scope: scope,
                in: context
            ) else {
                return nil
            }

            guard let resolvedLibraryID = library.id,
                  let libraryTitle = library.title else {
                return nil
            }

            return LibrarySnapshot(
                libraryID: resolvedLibraryID,
                libraryTitle: libraryTitle,
                totalLibraryCount: 1
            )
        }
    }

    private func fetchExistingLibraryShare(
        libraryID: UUID,
        scope: StoreScope
    ) async throws -> CKShare? {
        try await persistenceController.performBackgroundTask { context in
            guard let library = try self.fetchLibrary(
                libraryID: libraryID,
                scope: scope,
                in: context
            ) else {
                throw SharingRepositoryError.missingLibrary(id: libraryID, scope: scope)
            }

            return try self.persistenceController.container.fetchShares(
                matching: [library.objectID]
            )[library.objectID]
        }
    }

    private func createLibraryShare(
        libraryID: UUID,
        scope: StoreScope,
        libraryTitle: String
    ) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            let context = makeBackgroundContext(named: "SouvieShelf.CreateLibraryShareContext")
            context.perform {
                do {
                    guard let library = try self.fetchLibrary(
                        libraryID: libraryID,
                        scope: scope,
                        in: context
                    ) else {
                        throw SharingRepositoryError.missingLibrary(id: libraryID, scope: scope)
                    }

                    self.persistenceController.container.share(
                        [library],
                        to: nil
                    ) { _, share, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        guard let share else {
                            continuation.resume(throwing: SharingRepositoryError.missingShareRecord)
                            return
                        }

                        Task {
                            do {
                                let normalizedShare = try await self.normalizeShare(
                                    share,
                                    libraryTitle: libraryTitle,
                                    scope: scope
                                )
                                continuation.resume(returning: normalizedShare)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func normalizeShare(
        _ share: CKShare,
        libraryTitle: String,
        scope: StoreScope
    ) async throws -> CKShare {
        var shareNeedsPersistence = false

        if share.publicPermission != .none {
            share.publicPermission = .none
            shareNeedsPersistence = true
        }

        if (share[CKShare.SystemFieldKey.title] as? String) != libraryTitle {
            share[CKShare.SystemFieldKey.title] = libraryTitle as CKRecordValue
            shareNeedsPersistence = true
        }

        if shareNeedsPersistence {
            let store = try persistenceController.persistentStore(for: scope)
            return try await withCheckedThrowingContinuation { continuation in
                self.persistenceController.container.persistUpdatedShare(
                    share,
                    in: store
                ) { persistedShare, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let persistedShare else {
                        continuation.resume(throwing: SharingRepositoryError.missingShareRecord)
                        return
                    }

                    continuation.resume(returning: persistedShare)
                }
            }
        }

        return share
    }

    private func fetchLibrary(
        libraryID: UUID,
        scope: StoreScope,
        in context: NSManagedObjectContext
    ) throws -> Library? {
        let store = try persistenceController.persistentStore(for: scope)
        let request = Library.fetchRequest()
        request.fetchLimit = 1
        request.affectedStores = [store]
        request.predicate = NSPredicate(format: "id == %@", libraryID as CVarArg)

        return try context.fetch(request).first
    }

    private func fetchTrip(
        tripID: UUID,
        libraryID: UUID,
        scope: StoreScope,
        includeSoftDeleted: Bool = false,
        in context: NSManagedObjectContext
    ) throws -> Trip? {
        let store = try persistenceController.persistentStore(for: scope)
        let request = Trip.fetchRequest()
        request.fetchLimit = 1
        request.affectedStores = [store]

        var predicates: [NSPredicate] = [
            NSPredicate(format: "id == %@", tripID as CVarArg),
            NSPredicate(format: "library.id == %@", libraryID as CVarArg)
        ]

        if !includeSoftDeleted {
            predicates.append(NSPredicate(format: "deletedAt == NIL"))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return try context.fetch(request).first
    }

    private func fetchSouvenir(
        souvenirID: UUID,
        libraryID: UUID,
        scope: StoreScope,
        includeSoftDeleted: Bool,
        in context: NSManagedObjectContext
    ) throws -> Souvenir? {
        let store = try persistenceController.persistentStore(for: scope)
        let request = Souvenir.fetchRequest()
        request.fetchLimit = 1
        request.affectedStores = [store]

        var predicates: [NSPredicate] = [
            NSPredicate(format: "id == %@", souvenirID as CVarArg),
            NSPredicate(format: "library.id == %@", libraryID as CVarArg)
        ]

        if !includeSoftDeleted {
            predicates.append(NSPredicate(format: "deletedAt == NIL"))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return try context.fetch(request).first
    }

    private func currentUserCanWrite(
        library: Library,
        scope: StoreScope
    ) throws -> Bool {
        guard scope == .sharedLibrary else {
            return true
        }

        guard supportsCloudKitSharing else {
            return true
        }

        let share = try persistenceController.container.fetchShares(
            matching: [library.objectID]
        )[library.objectID]

        guard let share,
              let currentParticipant = share.currentUserParticipant else {
            logger.warning(
                "Missing current CloudKit participant metadata for a shared-library edit. Allowing the write path unless CloudKit later rejects it."
            )
            return true
        }

        if currentParticipant.role == .owner {
            return true
        }

        // CloudKit can transiently report `.unknown` before share metadata is fully hydrated.
        // Treat that as writable so the shared couple library stays editable unless CloudKit
        // explicitly marks the current participant as read-only.
        switch currentParticipant.permission {
        case .readWrite, .unknown:
            return true
        case .readOnly, .none:
            return false
        @unknown default:
            return false
        }
    }

    private func makeBackgroundContext(named name: String) -> NSManagedObjectContext {
        let context = persistenceController.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        context.name = name
        return context
    }

    private static func makeActiveLibraryContext(
        libraryID: UUID,
        libraryTitle: String,
        scope: StoreScope,
        shareSummary: ShareSummary
    ) -> ActiveLibraryContext {
        ActiveLibraryContext(
            libraryID: libraryID,
            storeScope: scope,
            libraryTitle: libraryTitle,
            partnerState: shareSummary.partnerState,
            isOwner: shareSummary.isOwner,
            shareSummary: shareSummary
        )
    }

    private static func makeUnsharedLibrarySummary(
        libraryTitle: String,
        scope: StoreScope
    ) -> ShareSummary {
        ShareSummary(
            libraryName: libraryTitle,
            shareExists: false,
            ownerDisplayName: scope.isOwner ? "You" : nil,
            participantCount: 1,
            isOwner: scope.isOwner,
            partnerState: scope == .sharedLibrary ? .connected(displayName: nil) : .none
        )
    }

    private static func makeFallbackShareSummary(
        libraryTitle: String,
        scope: StoreScope
    ) -> ShareSummary {
        if scope == .sharedLibrary {
            return ShareSummary(
                libraryName: libraryTitle,
                shareExists: true,
                ownerDisplayName: nil,
                participantCount: 2,
                isOwner: false,
                partnerState: .connected(displayName: nil)
            )
        }

        return makeUnsharedLibrarySummary(libraryTitle: libraryTitle, scope: scope)
    }

    private static func makeShareSummary(
        libraryTitle: String,
        scope: StoreScope,
        share: CKShare
    ) -> ShareSummary {
        let participantSnapshots = share.participants.map(makeParticipantSnapshot)
        let isOwner = share.currentUserParticipant?.role == .owner || scope.isOwner
        let partnerState = ShareParticipantStateResolver.partnerState(
            isOwner: isOwner,
            participants: participantSnapshots
        )

        return ShareSummary(
            libraryName: libraryTitle,
            shareExists: true,
            ownerDisplayName: ShareParticipantStateResolver.ownerDisplayName(
                isOwner: isOwner,
                participants: participantSnapshots
            ),
            participantCount: max(share.participants.count, 1),
            isOwner: isOwner,
            partnerState: partnerState
        )
    }

    private static func makeParticipantSnapshot(from participant: CKShare.Participant) -> ShareParticipantSnapshot {
        let formattedName = participant.userIdentity.nameComponents
            .flatMap(Self.formattedDisplayName(from:))

        let role: ShareParticipantSnapshot.Role
        switch participant.role {
        case .owner:
            role = .owner
        default:
            role = .partner
        }

        let acceptance: ShareParticipantSnapshot.Acceptance
        switch participant.acceptanceStatus {
        case .accepted:
            acceptance = .accepted
        case .pending:
            acceptance = .pending
        case .removed:
            acceptance = .removed
        default:
            acceptance = .unknown
        }

        return ShareParticipantSnapshot(
            role: role,
            acceptance: acceptance,
            displayName: formattedName
        )
    }

    private static func formattedDisplayName(from components: PersonNameComponents) -> String? {
        let formattedName = PersonNameComponentsFormatter().string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return formattedName.isEmpty ? nil : formattedName
    }
}

private extension PersistenceBackedAppBackend {
    enum SouvenirPlaceKind {
        case gotItIn
        case from
    }

    static func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = value?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func apply(
        place: PlaceDraft?,
        to souvenir: Souvenir,
        kind: SouvenirPlaceKind
    ) {
        let title = normalizedOptionalString(place?.title)
        let locality = normalizedOptionalString(place?.locality)
        let country = normalizedOptionalString(place?.country)
        let latitude = place?.latitude ?? 0
        let longitude = place?.longitude ?? 0

        switch kind {
        case .gotItIn:
            souvenir.gotItInName = title
            souvenir.gotItInCity = locality
            souvenir.gotItInCountryCode = country
            souvenir.gotItInLatitude = latitude
            souvenir.gotItInLongitude = longitude
        case .from:
            souvenir.fromName = title
            souvenir.fromCity = locality
            souvenir.fromCountryCode = country
            souvenir.fromLatitude = latitude
            souvenir.fromLongitude = longitude
        }
    }
}

private struct LibrarySnapshot: Sendable {
    let libraryID: UUID
    let libraryTitle: String
    let totalLibraryCount: Int
}

struct ShareParticipantSnapshot: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case owner
        case partner
    }

    enum Acceptance: Equatable, Sendable {
        case unknown
        case pending
        case accepted
        case removed
    }

    let role: Role
    let acceptance: Acceptance
    let displayName: String?
}

enum ShareParticipantStateResolver {
    static func partnerState(
        isOwner: Bool,
        participants: [ShareParticipantSnapshot]
    ) -> PartnerConnectionState {
        let partnerParticipant: ShareParticipantSnapshot?
        if isOwner {
            partnerParticipant = participants.first(where: { $0.role == .partner && $0.acceptance != .removed })
        } else {
            partnerParticipant = participants.first(where: { $0.role == .owner })
        }

        guard let partnerParticipant else {
            return .none
        }

        switch partnerParticipant.acceptance {
        case .accepted:
            return .connected(displayName: partnerParticipant.displayName)
        case .pending, .unknown:
            return .inviteSent
        case .removed:
            return .none
        }
    }

    static func ownerDisplayName(
        isOwner: Bool,
        participants: [ShareParticipantSnapshot]
    ) -> String? {
        if isOwner {
            return "You"
        }

        return participants.first(where: { $0.role == .owner })?.displayName
    }
}

private extension ICloudStatus {
    var logLabel: String {
        switch self {
        case .available:
            "available"
        case .unavailable:
            "unavailable"
        }
    }
}

private extension StoreScope {
    var logLabel: String {
        switch self {
        case .privateLibrary:
            "private"
        case .sharedLibrary:
            "shared"
        }
    }
}
