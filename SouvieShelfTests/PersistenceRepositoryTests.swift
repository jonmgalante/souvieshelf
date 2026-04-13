import XCTest
@testable import SouvieShelf

final class PersistenceRepositoryTests: XCTestCase {
    func testManagedObjectModelSatisfiesCloudKitRequirementsForConfiguredStores() throws {
        let persistenceController = try PersistenceController.inMemory()
        let model = persistenceController.container.managedObjectModel

        for scope in StoreScope.allCases {
            let entities = try XCTUnwrap(
                model.entities(forConfigurationName: scope.configurationName),
                "Expected entities for the \(scope.configurationName) configuration."
            )

            for entity in entities {
                let entityName = entity.name ?? "Unknown"
                let invalidAttributes = entity.attributesByName.values
                    .filter { !$0.isOptional && $0.defaultValue == nil }
                    .map { $0.name }
                    .sorted()
                XCTAssertTrue(
                    invalidAttributes.isEmpty,
                    "CloudKit-backed \(scope.configurationName) entity \(entityName) has non-optional attributes without defaults: \(invalidAttributes)"
                )

                let invalidRelationships = entity.relationshipsByName.values
                    .filter { !$0.isOptional }
                    .map { $0.name }
                    .sorted()
                XCTAssertTrue(
                    invalidRelationships.isEmpty,
                    "CloudKit-backed \(scope.configurationName) entity \(entityName) has non-optional relationships: \(invalidRelationships)"
                )
            }
        }
    }

    func testResolveLaunchContextReturnsNeedsPairingWhenNoLibraryExistsAndAccountIsUnavailable() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .unavailable)
        )

        let resolution = await repository.resolveLaunchContext()

        XCTAssertEqual(resolution, .needsPairing)
    }

    func testResolveLaunchContextReturnsReadyPrivateLibraryWhenOnlyPrivateLibraryExistsAndAccountIsUnavailable() async throws {
        let persistenceController = try PersistenceController.inMemory()
        try persistenceController.seedLibrary(title: "Our Library", scope: .privateLibrary)
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .unavailable)
        )

        let resolution = await repository.resolveLaunchContext()

        switch resolution {
        case .ready(let context):
            XCTAssertEqual(context.libraryTitle, "Our Library")
            XCTAssertEqual(context.storeScope, .privateLibrary)
            XCTAssertTrue(context.isOwner)
            XCTAssertEqual(context.partnerState, .none)
        default:
            XCTFail("Expected a ready(private) launch resolution.")
        }
    }

    func testResolveLaunchContextPrefersSharedStoreOverPrivateStoreWhenAccountIsUnavailable() async throws {
        let persistenceController = try PersistenceController.inMemory()
        try persistenceController.seedLibrary(title: "Our Library", scope: .privateLibrary)
        try persistenceController.seedLibrary(title: "Our Library", scope: .sharedLibrary)

        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .unavailable)
        )

        let resolution = await repository.resolveLaunchContext()

        switch resolution {
        case .ready(let context):
            XCTAssertEqual(context.libraryTitle, "Our Library")
            XCTAssertEqual(context.storeScope, .sharedLibrary)
            XCTAssertFalse(context.isOwner)
            XCTAssertEqual(context.partnerState, .connected(displayName: nil))
        default:
            XCTFail("Expected a ready(shared) launch resolution.")
        }
    }

    func testCreateLibraryCreatesPrivateOwnerContext() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )

        let createdContext = try await repository.createLibrary(title: "Our Library")
        let storedContext = await repository.libraryContext(in: .privateLibrary)

        XCTAssertEqual(createdContext.libraryTitle, "Our Library")
        XCTAssertEqual(createdContext.storeScope, .privateLibrary)
        XCTAssertTrue(createdContext.isOwner)
        XCTAssertEqual(createdContext.partnerState, .none)
        XCTAssertEqual(storedContext?.libraryID, createdContext.libraryID)
        XCTAssertEqual(storedContext?.storeScope, .privateLibrary)
    }

    func testCreateTripPersistsInExplicitLibraryScope() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let libraryContext = try await repository.createLibrary(title: "Our Library")
        let startDate = Date(timeIntervalSince1970: 1_710_000_000)
        let endDate = Date(timeIntervalSince1970: 1_710_086_400)

        let tripID = try await repository.createTrip(
            CreateTripInput(
                libraryContext: libraryContext,
                id: UUID(),
                title: "Japan",
                destinationSummary: "Kyoto and Tokyo",
                startDate: startDate,
                endDate: endDate
            )
        )

        let storedTrips = try await fetchTripSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )

        XCTAssertEqual(storedTrips.count, 1)
        XCTAssertEqual(storedTrips.first?.id, tripID)
        XCTAssertEqual(storedTrips.first?.title, "Japan")
        XCTAssertEqual(storedTrips.first?.destinationSummary, "Kyoto and Tokyo")
        XCTAssertEqual(storedTrips.first?.startDate, startDate)
        XCTAssertEqual(storedTrips.first?.endDate, endDate)
    }

    func testUpdateTripPersistsFieldChangesInPrivateStore() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let libraryContext = try await repository.createLibrary(title: "Our Library")
        let tripID = try await repository.createTrip(
            CreateTripInput(
                libraryContext: libraryContext,
                id: UUID(),
                title: "Italy",
                destinationSummary: "Rome",
                startDate: nil,
                endDate: nil
            )
        )
        let startDate = Date(timeIntervalSince1970: 1_735_084_800)
        let endDate = Date(timeIntervalSince1970: 1_735_516_800)

        try await repository.updateTrip(
            UpdateTripInput(
                libraryContext: libraryContext,
                tripID: tripID,
                title: "Japan",
                destinationSummary: "Kyoto and Tokyo",
                startDate: startDate,
                endDate: endDate
            )
        )

        let storedTrips = try await fetchTripSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )
        let storedTrip = try XCTUnwrap(storedTrips.first)

        XCTAssertEqual(storedTrip.id, tripID)
        XCTAssertEqual(storedTrip.title, "Japan")
        XCTAssertEqual(storedTrip.destinationSummary, "Kyoto and Tokyo")
        XCTAssertEqual(storedTrip.startDate, startDate)
        XCTAssertEqual(storedTrip.endDate, endDate)
        XCTAssertNil(storedTrip.deletedAt)
    }

    func testUpdateTripUsesSharedStoreWhenLibraryContextTargetsSharedLibrary() async throws {
        let persistenceController = try PersistenceController.inMemory()
        try persistenceController.seedLibrary(title: "Our Library", scope: .sharedLibrary)
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let resolvedLibraryContext = await repository.libraryContext(in: .sharedLibrary)
        let libraryContext = try XCTUnwrap(resolvedLibraryContext)
        let tripID = try await repository.createTrip(
            CreateTripInput(
                libraryContext: libraryContext,
                id: UUID(),
                title: "Portugal",
                destinationSummary: "Lisbon",
                startDate: nil,
                endDate: nil
            )
        )

        try await repository.updateTrip(
            UpdateTripInput(
                libraryContext: libraryContext,
                tripID: tripID,
                title: "Portugal Coast",
                destinationSummary: "Lisbon and Porto",
                startDate: nil,
                endDate: nil
            )
        )

        let sharedSnapshots = try await fetchTripSnapshots(
            persistenceController: persistenceController,
            scope: .sharedLibrary
        )
        let privateSnapshots = try await fetchTripSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )

        XCTAssertEqual(sharedSnapshots.count, 1)
        XCTAssertEqual(sharedSnapshots.first?.title, "Portugal Coast")
        XCTAssertEqual(sharedSnapshots.first?.destinationSummary, "Lisbon and Porto")
        XCTAssertTrue(privateSnapshots.isEmpty)
    }

    func testSoftDeleteTripMarksTripDeletedWithoutDetachingSouvenirs() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let libraryContext = try await repository.createLibrary(title: "Our Library")
        let tripID = try await repository.createTrip(
            CreateTripInput(
                libraryContext: libraryContext,
                id: UUID(),
                title: "Japan",
                destinationSummary: "Kyoto",
                startDate: nil,
                endDate: nil
            )
        )
        _ = try await repository.createSouvenir(
            CreateSouvenirInput(
                libraryContext: libraryContext,
                id: UUID(),
                tripID: tripID,
                title: "Tea cup",
                story: nil,
                acquiredOn: nil,
                gotItInPlace: nil,
                fromPlace: nil,
                photos: [makeImportedPhoto(id: UUID())]
            )
        )

        try await repository.softDeleteTrip(id: tripID, libraryContext: libraryContext)

        let storedTrips = try await fetchTripSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )
        let storedSouvenirs = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )
        let storedTrip = try XCTUnwrap(storedTrips.first)
        let storedSouvenir = try XCTUnwrap(storedSouvenirs.first)

        XCTAssertEqual(storedTrip.id, tripID)
        XCTAssertNotNil(storedTrip.deletedAt)
        XCTAssertEqual(storedSouvenir.tripID, tripID)
        XCTAssertNil(storedSouvenir.deletedAt)
    }

    func testRestoreTripClearsDeletedAtWithoutDetachingSouvenirs() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let libraryContext = try await repository.createLibrary(title: "Our Library")
        let tripID = try await repository.createTrip(
            CreateTripInput(
                libraryContext: libraryContext,
                id: UUID(),
                title: "Japan",
                destinationSummary: "Kyoto",
                startDate: nil,
                endDate: nil
            )
        )
        _ = try await repository.createSouvenir(
            CreateSouvenirInput(
                libraryContext: libraryContext,
                id: UUID(),
                tripID: tripID,
                title: "Tea cup",
                story: nil,
                acquiredOn: nil,
                gotItInPlace: nil,
                fromPlace: nil,
                photos: [makeImportedPhoto(id: UUID())]
            )
        )

        try await repository.softDeleteTrip(id: tripID, libraryContext: libraryContext)
        try await repository.restoreTrip(id: tripID, libraryContext: libraryContext)

        let storedTrips = try await fetchTripSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )
        let storedSouvenirs = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )
        let storedTrip = try XCTUnwrap(storedTrips.first)
        let storedSouvenir = try XCTUnwrap(storedSouvenirs.first)

        XCTAssertEqual(storedTrip.id, tripID)
        XCTAssertNil(storedTrip.deletedAt)
        XCTAssertEqual(storedSouvenir.tripID, tripID)
        XCTAssertNil(storedSouvenir.deletedAt)
    }

    func testCreateSouvenirPersistsPhotoAndPlaceFieldsInPrivateStore() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let libraryContext = try await repository.createLibrary(title: "Our Library")
        let tripID = try await repository.createTrip(
            CreateTripInput(
                libraryContext: libraryContext,
                id: UUID(),
                title: "Portugal",
                destinationSummary: "Lisbon",
                startDate: nil,
                endDate: nil
            )
        )
        let acquiredDate = Date(timeIntervalSince1970: 1_709_000_000)
        let photoID = UUID()

        let souvenirID = try await repository.createSouvenir(
            CreateSouvenirInput(
                libraryContext: libraryContext,
                id: UUID(),
                tripID: tripID,
                title: "Azulejo tile",
                story: "Found on our last afternoon together.",
                acquiredOn: acquiredDate,
                gotItInPlace: PlaceDraft(
                    title: "Feira da Ladra",
                    locality: "Lisbon",
                    country: "Portugal",
                    latitude: 38.7223,
                    longitude: -9.1393
                ),
                fromPlace: PlaceDraft(
                    title: "Porto",
                    locality: "Porto",
                    country: "Portugal",
                    latitude: 41.1579,
                    longitude: -8.6291
                ),
                photos: [makeImportedPhoto(id: photoID)]
            )
        )

        let storedSouvenirs = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )

        XCTAssertEqual(storedSouvenirs.count, 1)
        XCTAssertEqual(storedSouvenirs.first?.id, souvenirID)
        XCTAssertEqual(storedSouvenirs.first?.title, "Azulejo tile")
        XCTAssertEqual(storedSouvenirs.first?.story, "Found on our last afternoon together.")
        XCTAssertEqual(storedSouvenirs.first?.acquiredDate, acquiredDate)
        XCTAssertEqual(storedSouvenirs.first?.gotItInName, "Feira da Ladra")
        XCTAssertEqual(storedSouvenirs.first?.gotItInCity, "Lisbon")
        XCTAssertEqual(storedSouvenirs.first?.gotItInCountryCode, "Portugal")
        XCTAssertEqual(storedSouvenirs.first?.fromName, "Porto")
        XCTAssertEqual(storedSouvenirs.first?.fromCity, "Porto")
        XCTAssertEqual(storedSouvenirs.first?.fromCountryCode, "Portugal")
        XCTAssertEqual(storedSouvenirs.first?.tripID, tripID)

        let storedPhotoAssets = storedSouvenirs.first?.photos
        XCTAssertEqual(storedPhotoAssets?.count, 1)
        XCTAssertEqual(storedPhotoAssets?.first?.id, photoID)
        XCTAssertEqual(storedPhotoAssets?.first?.pixelWidth, 1200)
        XCTAssertEqual(storedPhotoAssets?.first?.pixelHeight, 800)
        XCTAssertTrue(storedPhotoAssets?.first?.isPrimary == true)
    }

    func testCreateSouvenirUsesSharedStoreWhenLibraryContextTargetsSharedLibrary() async throws {
        let persistenceController = try PersistenceController.inMemory()
        try persistenceController.seedLibrary(title: "Our Library", scope: .sharedLibrary)
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let resolvedLibraryContext = await repository.libraryContext(in: .sharedLibrary)
        let libraryContext = try XCTUnwrap(resolvedLibraryContext)

        _ = try await repository.createSouvenir(
            CreateSouvenirInput(
                libraryContext: libraryContext,
                id: UUID(),
                tripID: nil,
                title: nil,
                story: nil,
                acquiredOn: nil,
                gotItInPlace: nil,
                fromPlace: nil,
                photos: [makeImportedPhoto(id: UUID())]
            )
        )

        let sharedSouvenirs = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .sharedLibrary
        )
        let privateSouvenirs = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )

        XCTAssertEqual(sharedSouvenirs.count, 1)
        XCTAssertEqual(privateSouvenirs.count, 0)
    }

    func testUpdateSouvenirPersistsFieldChangesAndPhotoMutationsInPrivateStore() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let libraryContext = try await repository.createLibrary(title: "Our Library")
        let originalTripID = try await repository.createTrip(
            CreateTripInput(
                libraryContext: libraryContext,
                id: UUID(),
                title: "Italy",
                destinationSummary: "Rome",
                startDate: nil,
                endDate: nil
            )
        )
        let replacementTripID = try await repository.createTrip(
            CreateTripInput(
                libraryContext: libraryContext,
                id: UUID(),
                title: "Japan",
                destinationSummary: "Kyoto",
                startDate: nil,
                endDate: nil
            )
        )

        let souvenirID = try await repository.createSouvenir(
            CreateSouvenirInput(
                libraryContext: libraryContext,
                id: UUID(),
                tripID: originalTripID,
                title: "Original title",
                story: "Original story",
                acquiredOn: Date(timeIntervalSince1970: 1_700_000_000),
                gotItInPlace: PlaceDraft(
                    title: "Trevi Fountain",
                    locality: "Rome",
                    country: "Italy",
                    latitude: 41.9009,
                    longitude: 12.4833
                ),
                fromPlace: PlaceDraft(
                    title: "Florence",
                    locality: "Florence",
                    country: "Italy",
                    latitude: 43.7696,
                    longitude: 11.2558
                ),
                photos: [
                    makeImportedPhoto(id: UUID()),
                    makeImportedPhoto(id: UUID())
                ]
            )
        )

        let originalSnapshots = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )
        let originalSnapshot = try XCTUnwrap(originalSnapshots.first)
        let retainedPhotoID = try XCTUnwrap(originalSnapshot.photos.last?.id)
        let newPhoto = makeImportedPhoto(id: UUID())

        try await repository.updateSouvenir(
            UpdateSouvenirInput(
                libraryContext: libraryContext,
                souvenirID: souvenirID,
                tripID: replacementTripID,
                title: "Updated title",
                story: "",
                acquiredOn: nil,
                gotItInPlace: PlaceDraft(
                    title: "Nishiki Market",
                    locality: "Kyoto",
                    country: "Japan",
                    latitude: 35.0045,
                    longitude: 135.7681
                ),
                fromPlace: nil,
                photoOrder: [retainedPhotoID, newPhoto.id],
                addedPhotos: [newPhoto],
                primaryPhotoID: retainedPhotoID
            )
        )

        let updatedSnapshots = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )
        let updatedSnapshot = try XCTUnwrap(updatedSnapshots.first)

        XCTAssertEqual(updatedSnapshot.title, "Updated title")
        XCTAssertNil(updatedSnapshot.story)
        XCTAssertNil(updatedSnapshot.acquiredDate)
        XCTAssertEqual(updatedSnapshot.tripID, replacementTripID)
        XCTAssertEqual(updatedSnapshot.gotItInName, "Nishiki Market")
        XCTAssertEqual(updatedSnapshot.gotItInCity, "Kyoto")
        XCTAssertEqual(updatedSnapshot.gotItInCountryCode, "Japan")
        XCTAssertNil(updatedSnapshot.fromName)
        XCTAssertNil(updatedSnapshot.fromCity)
        XCTAssertNil(updatedSnapshot.fromCountryCode)
        XCTAssertEqual(updatedSnapshot.photos.compactMap(\.id), [retainedPhotoID, newPhoto.id])
        XCTAssertEqual(updatedSnapshot.photos.filter(\.isPrimary).count, 1)
        XCTAssertEqual(updatedSnapshot.photos.first?.id, retainedPhotoID)
        XCTAssertEqual(updatedSnapshot.photos.first?.isPrimary, true)
    }

    func testUpdateSouvenirUsesSharedStoreWhenLibraryContextTargetsSharedLibrary() async throws {
        let persistenceController = try PersistenceController.inMemory()
        try persistenceController.seedLibrary(title: "Our Library", scope: .sharedLibrary)
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let resolvedLibraryContext = await repository.libraryContext(in: .sharedLibrary)
        let libraryContext = try XCTUnwrap(resolvedLibraryContext)
        let souvenirID = try await repository.createSouvenir(
            CreateSouvenirInput(
                libraryContext: libraryContext,
                id: UUID(),
                tripID: nil,
                title: "Before",
                story: nil,
                acquiredOn: nil,
                gotItInPlace: nil,
                fromPlace: nil,
                photos: [makeImportedPhoto(id: UUID())]
            )
        )
        let originalSharedSnapshots = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .sharedLibrary
        )
        let originalSharedSnapshot = try XCTUnwrap(originalSharedSnapshots.first)
        let existingPhotoID = try XCTUnwrap(originalSharedSnapshot.photos.first?.id)

        try await repository.updateSouvenir(
            UpdateSouvenirInput(
                libraryContext: libraryContext,
                souvenirID: souvenirID,
                tripID: nil,
                title: "After",
                story: "Shared edit",
                acquiredOn: nil,
                gotItInPlace: nil,
                fromPlace: nil,
                photoOrder: [existingPhotoID],
                addedPhotos: [],
                primaryPhotoID: existingPhotoID
            )
        )

        let sharedSnapshots = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .sharedLibrary
        )
        let sharedSnapshot = try XCTUnwrap(sharedSnapshots.first)
        let privateSnapshots = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )

        XCTAssertEqual(sharedSnapshot.title, "After")
        XCTAssertEqual(sharedSnapshot.story, "Shared edit")
        XCTAssertTrue(privateSnapshots.isEmpty)
    }

    func testSoftDeleteSouvenirMarksRecordDeletedWithoutRemovingIt() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let libraryContext = try await repository.createLibrary(title: "Our Library")
        let souvenirID = try await repository.createSouvenir(
            CreateSouvenirInput(
                libraryContext: libraryContext,
                id: UUID(),
                tripID: nil,
                title: "Tea tin",
                story: nil,
                acquiredOn: nil,
                gotItInPlace: nil,
                fromPlace: nil,
                photos: [makeImportedPhoto(id: UUID())]
            )
        )

        try await repository.softDeleteSouvenir(id: souvenirID, libraryContext: libraryContext)

        let storedSnapshots = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )
        let storedSnapshot = try XCTUnwrap(storedSnapshots.first)

        XCTAssertEqual(storedSnapshot.id, souvenirID)
        XCTAssertNotNil(storedSnapshot.deletedAt)
    }

    func testRestoreSouvenirClearsDeletedAtInSharedStoreScope() async throws {
        let persistenceController = try PersistenceController.inMemory()
        try persistenceController.seedLibrary(title: "Our Library", scope: .sharedLibrary)
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let resolvedLibraryContext = await repository.libraryContext(in: .sharedLibrary)
        let libraryContext = try XCTUnwrap(resolvedLibraryContext)
        let souvenirID = try await repository.createSouvenir(
            CreateSouvenirInput(
                libraryContext: libraryContext,
                id: UUID(),
                tripID: nil,
                title: "Azulejo tile",
                story: nil,
                acquiredOn: nil,
                gotItInPlace: nil,
                fromPlace: nil,
                photos: [makeImportedPhoto(id: UUID())]
            )
        )

        try await repository.softDeleteSouvenir(
            id: souvenirID,
            libraryContext: libraryContext
        )
        try await repository.restoreSouvenir(
            id: souvenirID,
            libraryContext: libraryContext
        )

        let sharedSnapshots = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .sharedLibrary
        )
        let privateSnapshots = try await fetchSouvenirSnapshots(
            persistenceController: persistenceController,
            scope: .privateLibrary
        )
        let restoredSnapshot = try XCTUnwrap(sharedSnapshots.first)

        XCTAssertEqual(restoredSnapshot.id, souvenirID)
        XCTAssertNil(restoredSnapshot.deletedAt)
        XCTAssertTrue(privateSnapshots.isEmpty)
    }

    func testRestoreTripDoesNotCrossStoreScopes() async throws {
        let persistenceController = try PersistenceController.inMemory()
        try persistenceController.seedLibrary(title: "Our Library", scope: .privateLibrary)
        try persistenceController.seedLibrary(title: "Our Library", scope: .sharedLibrary)
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let resolvedPrivateContext = await repository.libraryContext(in: .privateLibrary)
        let privateContext = try XCTUnwrap(resolvedPrivateContext)
        let resolvedSharedContext = await repository.libraryContext(in: .sharedLibrary)
        let sharedContext = try XCTUnwrap(resolvedSharedContext)
        let tripID = try await repository.createTrip(
            CreateTripInput(
                libraryContext: sharedContext,
                id: UUID(),
                title: "Portugal",
                destinationSummary: "Lisbon",
                startDate: nil,
                endDate: nil
            )
        )

        try await repository.softDeleteTrip(
            id: tripID,
            libraryContext: sharedContext
        )

        do {
            try await repository.restoreTrip(
                id: tripID,
                libraryContext: privateContext
            )
            XCTFail("Expected restore to fail when using the wrong store scope.")
        } catch let error as SharingRepositoryError {
            guard case .missingTrip(let missingID, _, let scope) = error else {
                return XCTFail("Expected a missingTrip error, got \(error).")
            }

            XCTAssertEqual(missingID, tripID)
            XCTAssertEqual(scope, .privateLibrary)
        }

        let sharedSnapshots = try await fetchTripSnapshots(
            persistenceController: persistenceController,
            scope: .sharedLibrary
        )
        let sharedTrip = try XCTUnwrap(sharedSnapshots.first)

        XCTAssertEqual(sharedTrip.id, tripID)
        XCTAssertNotNil(sharedTrip.deletedAt)
    }

    func testSouvenirPhotoEditLogicPromotesNextPhotoWhenPrimaryIsRemoved() throws {
        let primaryPhoto = EditableSouvenirPhoto(
            importedPhoto: makeImportedPhoto(id: UUID()),
            isPrimary: true
        )
        let secondaryPhoto = EditableSouvenirPhoto(
            importedPhoto: makeImportedPhoto(id: UUID()),
            isPrimary: false
        )

        let remainingPhotos = try SouvenirPhotoEditLogic.removingPhoto(
            withID: primaryPhoto.id,
            from: [primaryPhoto, secondaryPhoto]
        )

        XCTAssertEqual(remainingPhotos.count, 1)
        XCTAssertEqual(remainingPhotos.first?.id, secondaryPhoto.id)
        XCTAssertEqual(remainingPhotos.first?.isPrimary, true)
    }

    func testSouvenirPhotoEditLogicRejectsRemovingLastPhoto() {
        let onlyPhoto = EditableSouvenirPhoto(
            importedPhoto: makeImportedPhoto(id: UUID()),
            isPrimary: true
        )

        XCTAssertThrowsError(
            try SouvenirPhotoEditLogic.removingPhoto(
                withID: onlyPhoto.id,
                from: [onlyPhoto]
            )
        ) { error in
            XCTAssertEqual(error as? SouvenirPhotoEditError, .lastPhotoRequired)
        }
    }

    func testPartnerStateResolverReturnsNoneWhenOwnerHasNoPartnerParticipant() {
        let state = ShareParticipantStateResolver.partnerState(
            isOwner: true,
            participants: [
                ShareParticipantSnapshot(role: .owner, acceptance: .accepted, displayName: "You")
            ]
        )

        XCTAssertEqual(state, .none)
    }

    func testPartnerStateResolverReturnsInviteSentWhenPartnerIsPending() {
        let state = ShareParticipantStateResolver.partnerState(
            isOwner: true,
            participants: [
                ShareParticipantSnapshot(role: .owner, acceptance: .accepted, displayName: "You"),
                ShareParticipantSnapshot(role: .partner, acceptance: .pending, displayName: "Taylor")
            ]
        )

        XCTAssertEqual(state, .inviteSent)
    }

    func testPartnerStateResolverReturnsConnectedOwnerNameForParticipant() {
        let state = ShareParticipantStateResolver.partnerState(
            isOwner: false,
            participants: [
                ShareParticipantSnapshot(role: .owner, acceptance: .accepted, displayName: "Taylor"),
                ShareParticipantSnapshot(role: .partner, acceptance: .accepted, displayName: nil)
            ]
        )

        XCTAssertEqual(state, .connected(displayName: "Taylor"))
    }

    func testPlacePresentationLogicPrefersCityAndCountryAndAggregatesCounts() {
        let groups = PlacePresentationLogic.groups(
            from: [
                PlaceCandidate(
                    name: "Nishiki Market",
                    city: "Kyoto",
                    country: "Japan",
                    latitude: 35.0045,
                    longitude: 135.7681,
                    thumbnailData: nil
                ),
                PlaceCandidate(
                    name: "Gion",
                    city: "Kyoto",
                    country: "Japan",
                    latitude: nil,
                    longitude: nil,
                    thumbnailData: nil
                ),
                PlaceCandidate(
                    name: "Canal Cruise",
                    city: "Amsterdam",
                    country: "Netherlands",
                    latitude: 52.3676,
                    longitude: 4.9041,
                    thumbnailData: nil
                )
            ]
        )

        XCTAssertEqual(groups.map(\.title), ["Kyoto, Japan", "Amsterdam, Netherlands"])
        XCTAssertEqual(groups.first?.souvenirCount, 2)
        XCTAssertEqual(groups.first?.key.label, "Kyoto, Japan")
        XCTAssertEqual(groups.first?.key.identifier, "city|kyoto|country|japan")
        XCTAssertEqual(groups.first?.key.latitude, 35.0045)
        XCTAssertEqual(groups.first?.key.longitude, 135.7681)
    }

    func testPlacePresentationLogicFallsBackToNameCountryCountryOnlyAndSingleFieldRules() {
        let groups = PlacePresentationLogic.groups(
            from: [
                PlaceCandidate(
                    name: "Blue Lagoon",
                    city: nil,
                    country: "Iceland",
                    latitude: nil,
                    longitude: nil,
                    thumbnailData: nil
                ),
                PlaceCandidate(
                    name: nil,
                    city: nil,
                    country: "Portugal",
                    latitude: nil,
                    longitude: nil,
                    thumbnailData: nil
                )
            ]
        )

        XCTAssertEqual(groups.map(\.title), ["Blue Lagoon, Iceland", "Portugal"])
        XCTAssertEqual(
            PlacePresentationLogic.displayTitle(
                name: "Blue Lagoon",
                city: nil,
                country: "Iceland"
            ),
            "Blue Lagoon, Iceland"
        )
        XCTAssertEqual(
            PlacePresentationLogic.displayTitle(
                name: nil,
                city: nil,
                country: "Portugal"
            ),
            "Portugal"
        )
        XCTAssertEqual(
            PlacePresentationLogic.displayTitle(
                name: nil,
                city: "Kyoto",
                country: nil
            ),
            "Kyoto"
        )
        XCTAssertEqual(
            PlacePresentationLogic.displayTitle(
                name: "Blue Lagoon",
                city: nil,
                country: nil
            ),
            "Blue Lagoon"
        )
    }

    func testPlacePresentationLogicMatchesUsingSameNormalizedKeyAsGrouping() throws {
        let placeKey = try XCTUnwrap(
            PlacePresentationLogic.placeKey(
                name: "Nishiki Market",
                city: "Kyoto",
                country: "Japan"
            )
        )

        XCTAssertTrue(
            PlacePresentationLogic.matches(
                placeKey: placeKey,
                name: "Gion",
                city: "Kyoto",
                country: "Japan"
            )
        )
        XCTAssertFalse(
            PlacePresentationLogic.matches(
                placeKey: placeKey,
                name: "Nishiki Market",
                city: "Kyoto",
                country: "Portugal"
            )
        )
        XCTAssertFalse(
            PlacePresentationLogic.matches(
                placeKey: placeKey,
                name: nil,
                city: nil,
                country: nil
            )
        )
    }

    func testTripPresentationLogicFormatsDateRangeVariants() {
        var calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone
        calendar.locale = locale

        let startDate = Date(timeIntervalSince1970: 1_736_035_200) // Jan 5 2025 00:00:00 UTC
        let endDate = Date(timeIntervalSince1970: 1_736_208_000) // Jan 7 2025 00:00:00 UTC

        XCTAssertEqual(
            TripPresentationLogic.dateRangeSummary(
                startDate: startDate,
                endDate: endDate,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Jan 5, 2025 - Jan 7, 2025"
        )
        XCTAssertEqual(
            TripPresentationLogic.dateRangeSummary(
                startDate: startDate,
                endDate: nil,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Starts Jan 5, 2025"
        )
        XCTAssertEqual(
            TripPresentationLogic.dateRangeSummary(
                startDate: nil,
                endDate: endDate,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Ends Jan 7, 2025"
        )
        XCTAssertNil(
            TripPresentationLogic.dateRangeSummary(
                startDate: nil,
                endDate: nil,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
    }

    func testTripFormLogicRejectsBlankTitlesAndInvalidDateRanges() {
        let startDate = Date(timeIntervalSince1970: 1_736_035_200)
        let endDate = Date(timeIntervalSince1970: 1_736_208_000)

        XCTAssertEqual(
            TripFormLogic.validationMessage(
                title: "   ",
                hasStartDate: false,
                startDate: startDate,
                hasEndDate: false,
                endDate: endDate
            ),
            "Trip title is required."
        )
        XCTAssertEqual(
            TripFormLogic.validationMessage(
                title: "Japan",
                hasStartDate: true,
                startDate: endDate,
                hasEndDate: true,
                endDate: startDate
            ),
            "End date can't be before the start date."
        )
        XCTAssertTrue(
            TripFormLogic.canSave(
                title: "Japan",
                hasStartDate: true,
                startDate: startDate,
                hasEndDate: true,
                endDate: endDate,
                isSaving: false
            )
        )
    }

    func testMapPresentationLogicFiltersByPlaceUsingNormalizedPlaceKeyAndValidCoordinates() throws {
        let placeKey = try XCTUnwrap(
            PlacePresentationLogic.placeKey(
                name: "Nishiki Market",
                city: "Kyoto",
                country: "Japan"
            )
        )
        let deletedTripDate = Date(timeIntervalSince1970: 1_736_035_200)
        let keptSouvenirID = UUID()

        let annotations = MapPresentationLogic.annotations(
            from: [
                MapSouvenirRecord(
                    souvenirID: keptSouvenirID,
                    title: "  Matcha whisk  ",
                    acquiredDate: nil,
                    updatedAt: nil,
                    tripID: UUID(),
                    tripTitle: "Spring in Japan",
                    tripDeletedAt: deletedTripDate,
                    gotItInName: "Gion",
                    gotItInCity: "Kyoto",
                    gotItInCountry: "Japan",
                    latitude: 35.0116,
                    longitude: 135.7681,
                    thumbnailData: nil
                ),
                MapSouvenirRecord(
                    souvenirID: UUID(),
                    title: "Pastel tile",
                    acquiredDate: nil,
                    updatedAt: nil,
                    tripID: UUID(),
                    tripTitle: "Lisbon",
                    tripDeletedAt: nil,
                    gotItInName: "Feira da Ladra",
                    gotItInCity: "Lisbon",
                    gotItInCountry: "Portugal",
                    latitude: 38.7223,
                    longitude: -9.1393,
                    thumbnailData: nil
                ),
                MapSouvenirRecord(
                    souvenirID: UUID(),
                    title: nil,
                    acquiredDate: nil,
                    updatedAt: nil,
                    tripID: UUID(),
                    tripTitle: nil,
                    tripDeletedAt: nil,
                    gotItInName: "Nishiki Market",
                    gotItInCity: "Kyoto",
                    gotItInCountry: "Japan",
                    latitude: 0,
                    longitude: 0,
                    thumbnailData: nil
                )
            ],
            filterContext: .place(
                placeKey,
                storeScope: .privateLibrary
            )
        )

        XCTAssertEqual(annotations.map(\.souvenirID), [keptSouvenirID])
        XCTAssertEqual(annotations.first?.title, "Matcha whisk")
        XCTAssertNil(annotations.first?.tripTitle)
        XCTAssertEqual(annotations.first?.placeSummary, "Kyoto, Japan")
    }

    func testMapPresentationLogicTripFilterKeepsSouvenirWhenLinkedTripIsSoftDeleted() {
        let tripID = UUID()

        let annotations = MapPresentationLogic.annotations(
            from: [
                MapSouvenirRecord(
                    souvenirID: UUID(),
                    title: nil,
                    acquiredDate: nil,
                    updatedAt: nil,
                    tripID: tripID,
                    tripTitle: "Old trip",
                    tripDeletedAt: Date(timeIntervalSince1970: 1_736_035_200),
                    gotItInName: "Blue Lagoon",
                    gotItInCity: nil,
                    gotItInCountry: "Iceland",
                    latitude: 63.8804,
                    longitude: -22.4495,
                    thumbnailData: nil
                )
            ],
            filterContext: .trip(
                tripID,
                storeScope: .privateLibrary
            )
        )

        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations.first?.title, "Untitled souvenir")
        XCTAssertNil(annotations.first?.tripTitle)
        XCTAssertEqual(annotations.first?.placeSummary, "Blue Lagoon, Iceland")
    }

    func testTripMapFetchRequestIncludesSortDescriptors() async throws {
        let persistenceController = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(
            persistenceController: persistenceController,
            iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .available)
        )
        let libraryContext = try await repository.createLibrary(title: "Our Library")

        let request = repository.tripFetchRequest(
            tripID: UUID(),
            activeLibraryContext: libraryContext
        )

        XCTAssertEqual(request.sortDescriptors?.count, 2)
        XCTAssertEqual(request.sortDescriptors?.first?.key, "updatedAt")
        XCTAssertEqual(request.sortDescriptors?.first?.ascending, false)
        XCTAssertEqual(request.sortDescriptors?.dropFirst().first?.key, "createdAt")
        XCTAssertEqual(request.sortDescriptors?.dropFirst().first?.ascending, false)
    }

    private func fetchTripSnapshots(
        persistenceController: PersistenceController,
        scope: StoreScope
    ) async throws -> [TripSnapshot] {
        let store = try persistenceController.persistentStore(for: scope)
        return try await persistenceController.performBackgroundTask { context in
            let request = Trip.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            request.affectedStores = [store]
            return try context.fetch(request).map {
                TripSnapshot(
                    id: $0.id,
                    title: $0.title,
                    destinationSummary: $0.destinationSummary,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    deletedAt: $0.deletedAt
                )
            }
        }
    }

    private func fetchSouvenirSnapshots(
        persistenceController: PersistenceController,
        scope: StoreScope
    ) async throws -> [SouvenirSnapshot] {
        let store = try persistenceController.persistentStore(for: scope)
        return try await persistenceController.performBackgroundTask { context in
            let request = Souvenir.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            request.affectedStores = [store]
            return try context.fetch(request).map { souvenir in
                let photos = ((souvenir.photos as? Set<PhotoAsset>) ?? [])
                    .sorted { lhs, rhs in
                        lhs.sortIndex < rhs.sortIndex
                    }
                    .map {
                        PhotoAssetSnapshot(
                            id: $0.id,
                            pixelWidth: $0.pixelWidth,
                            pixelHeight: $0.pixelHeight,
                            isPrimary: $0.isPrimary
                        )
                    }

                return SouvenirSnapshot(
                    id: souvenir.id,
                    title: souvenir.title,
                    story: souvenir.story,
                    acquiredDate: souvenir.acquiredDate,
                    deletedAt: souvenir.deletedAt,
                    gotItInName: souvenir.gotItInName,
                    gotItInCity: souvenir.gotItInCity,
                    gotItInCountryCode: souvenir.gotItInCountryCode,
                    fromName: souvenir.fromName,
                    fromCity: souvenir.fromCity,
                    fromCountryCode: souvenir.fromCountryCode,
                    tripID: souvenir.trip?.id,
                    photos: photos
                )
            }
        }
    }

    private func makeImportedPhoto(id: UUID) -> ImportedPhoto {
        ImportedPhoto(
            id: id,
            localIdentifier: nil,
            displayImageData: Data([0x01, 0x02, 0x03]),
            thumbnailData: Data([0x04, 0x05, 0x06]),
            pixelWidth: 1200,
            pixelHeight: 800,
            capturedAt: nil,
            suggestedLocation: nil
        )
    }

    private struct TripSnapshot {
        var id: UUID?
        var title: String?
        var destinationSummary: String?
        var startDate: Date?
        var endDate: Date?
        var deletedAt: Date?
    }

    private struct SouvenirSnapshot {
        var id: UUID?
        var title: String?
        var story: String?
        var acquiredDate: Date?
        var deletedAt: Date?
        var gotItInName: String?
        var gotItInCity: String?
        var gotItInCountryCode: String?
        var fromName: String?
        var fromCity: String?
        var fromCountryCode: String?
        var tripID: UUID?
        var photos: [PhotoAssetSnapshot]
    }

    private struct PhotoAssetSnapshot {
        var id: UUID?
        var pixelWidth: Int32
        var pixelHeight: Int32
        var isPrimary: Bool
    }
}
