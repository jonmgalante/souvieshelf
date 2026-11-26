import CoreData
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import XCTest
@testable import SouvieShelf

@MainActor
final class OnePhotoCaptureTests: XCTestCase {
    private let newYork = ImportedPhotoLocation(latitude: 40.7128, longitude: -74.006)
    private let ravello = PlaceDraft(title: "Ravello", country: "IT", latitude: 40.6491, longitude: 14.6115)

    private func capture(_ date: String? = nil, location: ImportedPhotoLocation? = nil) -> CameraCapture {
        var metadata: [String: Any] = [:]
        if let date {
            metadata[kCGImagePropertyExifDictionary as String] = [kCGImagePropertyExifDateTimeOriginal: date]
        }
        if let location {
            metadata[kCGImagePropertyGPSDictionary as String] = [
                kCGImagePropertyGPSLatitude: abs(location.latitude), kCGImagePropertyGPSLatitudeRef: location.latitude < 0 ? "S" : "N",
                kCGImagePropertyGPSLongitude: abs(location.longitude), kCGImagePropertyGPSLongitudeRef: location.longitude < 0 ? "W" : "E"
            ] as [CFString: Any]
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { $0.fill(CGRect(x: 0, y: 0, width: 12, height: 12)) }
        return CameraCapture(image: image, metadata: metadata)
    }

    private func makeShelf(importer: (any PhotoImporting)? = nil) async throws -> (AddSouvenirViewModel, PersistenceController, DeferredPlaceLookup) {
        let persistence = try PersistenceController.inMemory()
        let repository = PersistenceBackedAppBackend(persistenceController: persistence,
                                                    iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .unavailable))
        let library = try await repository.createLibrary(title: "Our Library")
        let lookup = DeferredPlaceLookup()
        let model = AddSouvenirViewModel(activeLibraryContext: library, souvenirRepository: repository,
                                        permissionCoordinator: PreviewPermissionCoordinator(), photoImporter: importer ?? LivePhotoImportService(),
                                        locationSuggester: lookup)
        return (model, persistence, lookup)
    }

    func testQuickSaveDuringLookupStoresNewYorkOnlyOnPhotoAndCreatesOneObject() async throws {
        let (model, persistence, lookup) = try await makeShelf()
        await model.importCameraCapture(capture("2026:02:14 12:00:00", location: newYork))
        let date = try XCTUnwrap(model.importedPhoto?.capturedAt)
        let lookupTask = Task { await model.resolveSuggestedPlace() }
        await fulfillment(of: [lookup.started], timeout: 3)
        XCTAssertTrue(model.canSave)
        async let first = model.save()
        async let second = model.save()
        let results = await [first, second].compactMap { $0 }
        XCTAssertEqual(results.count, 1)
        let repeated = await model.save()
        XCTAssertNil(repeated)
        let records = try persistence.viewContext.fetch(Souvenir.fetchRequest())
        let item = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(item.acquiredDate)
        XCTAssertNil(item.gotItInName)
        XCTAssertNil(item.fromName)
        XCTAssertNil(item.trip)
        XCTAssertEqual(item.gotItInLatitude, 0)
        XCTAssertEqual(item.gotItInLongitude, 0)
        let asset = try XCTUnwrap((item.photos as? Set<PhotoAsset>)?.first)
        XCTAssertEqual(asset.capturedAt, date)
        XCTAssertEqual(asset.captureLatitude?.doubleValue, newYork.latitude)
        XCTAssertEqual(asset.captureLongitude?.doubleValue, newYork.longitude)
        lookup.finish(nil)
        await lookupTask.value
    }

    func testEarlierLookupCannotChangeReplacementPhotoOrManualFields() async throws {
        let (model, _, lookup) = try await makeShelf()
        await model.importCameraCapture(capture("2026:02:14 12:00:00", location: newYork))
        let pending = Task { await model.resolveSuggestedPlace() }
        await fulfillment(of: [lookup.started], timeout: 3)
        model.gotItInPlace = ravello
        let manualDate = Date(timeIntervalSince1970: 1_700_000_000)
        model.acquiredDate = manualDate
        await model.importCameraCapture(capture())
        lookup.finish(PlaceDraft(title: "New York", latitude: newYork.latitude, longitude: newYork.longitude))
        await pending.value
        XCTAssertNil(model.suggestedPlace)
        XCTAssertNil(model.importedPhoto?.capturedAt)
        XCTAssertEqual(model.gotItInPlace, ravello)
        XCTAssertEqual(model.acquiredDate, manualDate)
        XCTAssertNil(model.fromPlace)
    }

    func testNewerSelectionWinsWhenEarlierTransferFinishesLast() async throws {
        let importer = DelayedFirstImport()
        let (model, _, _) = try await makeShelf(importer: importer)
        let older = Task { await model.importCameraCapture(capture("2026:02:14 12:00:00", location: newYork)) }
        await fulfillment(of: [importer.started], timeout: 3)
        XCTAssertFalse(model.canSave)
        await model.importCameraCapture(capture())
        let latest = try XCTUnwrap(model.importedPhoto)
        importer.resumeFirst()
        await older.value
        XCTAssertEqual(model.importedPhoto, latest)
        XCTAssertNil(model.suggestedPlace)
        XCTAssertTrue(model.canSave)
    }

    func testLookupUpdatesOnlyASuggestionUntilUserChoosesIt() async throws {
        let (model, persistence, lookup) = try await makeShelf()
        await model.importCameraCapture(capture("2025:05:18 12:00:00", location: .init(latitude: 40.6491, longitude: 14.6115)))
        let task = Task { await model.resolveSuggestedPlace() }
        await fulfillment(of: [lookup.started], timeout: 3)
        let manual = PlaceDraft(title: "Amalfi", country: "IT")
        model.gotItInPlace = manual
        lookup.finish(ravello)
        await task.value
        XCTAssertEqual(model.gotItInPlace, manual)
        XCTAssertNil(model.acquiredDate)
        model.gotItInPlace = model.suggestedPlace
        model.acquiredDate = model.importedPhoto?.capturedAt
        let saved = await model.save()
        XCTAssertNotNil(saved)
        let item = try XCTUnwrap(persistence.viewContext.fetch(Souvenir.fetchRequest()).first)
        XCTAssertEqual(item.gotItInName, "Ravello")
        XCTAssertEqual(item.acquiredDate, model.importedPhoto?.capturedAt)
        XCTAssertNil(item.fromName)
    }

    func testMetadataFreeDraftSurvivesWriteFailureAndRetriesOffline() async throws {
        let (model, persistence, lookup) = try await makeShelf()
        await model.importCameraCapture(capture())
        let photo = try XCTUnwrap(model.importedPhoto)
        await model.resolveSuggestedPlace()
        XCTAssertEqual(lookup.calls, 0)
        model.story = "Found on the last morning."
        model.selectedTrip = TripSelection(id: UUID(), title: "Missing trip", subtitle: nil)
        let failed = await model.save()
        XCTAssertNil(failed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.importedPhoto, photo)
        XCTAssertEqual(model.story, "Found on the last morning.")
        XCTAssertTrue(try persistence.viewContext.fetch(Souvenir.fetchRequest()).isEmpty)
        model.selectedTrip = nil
        let saved = await model.save()
        XCTAssertNotNil(saved)
        let item = try XCTUnwrap(persistence.viewContext.fetch(Souvenir.fetchRequest()).first)
        XCTAssertEqual(item.story, model.story)
        XCTAssertNil(item.acquiredDate)
        XCTAssertNil(item.gotItInName)
        XCTAssertNil(item.fromName)
    }

    func testFailedOwnerShareAttachmentRetriesWithTheSamePhotoAndSouvenir() async throws {
        let persistence = try PersistenceController.inMemory()
        try persistence.seedLibrary(title: "Our Library", scope: .privateLibrary)
        let context = persistence.viewContext
        let library = try XCTUnwrap(context.fetch(Library.fetchRequest()).first)
        let libraryID = try XCTUnwrap(library.id)
        let item = Souvenir(entity: try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Souvenir", in: context)), insertInto: context)
        item.id = UUID()
        item.library = library
        item.needsCaptureShareAttachment = true
        let photo = PhotoAsset(entity: try XCTUnwrap(NSEntityDescription.entity(forEntityName: "PhotoAsset", in: context)), insertInto: context)
        photo.id = UUID()
        photo.souvenir = item
        let store = try persistence.persistentStore(for: .privateLibrary)
        context.assign(item, to: store)
        context.assign(photo, to: store)
        try context.save()
        let expectedIDs = Set([item.objectID, photo.objectID])
        func backend() -> PersistenceBackedAppBackend {
            PersistenceBackedAppBackend(persistenceController: persistence,
                                        iCloudStatusProvider: FixedICloudStatusProvider(fixedStatus: .unavailable))
        }
        do {
            try await backend().attachPendingCaptures(in: libraryID) { ids in
                XCTAssertEqual(Set(ids), expectedIDs)
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("Expected the simulated connection loss")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }
        var attachments = 0
        try await backend().attachPendingCaptures(in: libraryID) { ids in
            XCTAssertEqual(Set(ids), expectedIDs)
            attachments += 1
        }
        XCTAssertEqual(attachments, 1)
        try await backend().attachPendingCaptures(in: libraryID) { _ in XCTFail("Already attached") }
        XCTAssertEqual(try context.count(for: Souvenir.fetchRequest()), 1)
    }

    func testOldPrivateAndSharedStoresReopenWithUnknownPhotoMetadata() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "SouvieShelfModel", withExtension: "momd"))
        let old = try XCTUnwrap(NSManagedObjectModel(contentsOf: bundle.appendingPathComponent("SouvieShelfModel.mom")))
        let current = try XCTUnwrap(NSManagedObjectModel(contentsOf: bundle))
        for scope in StoreScope.allCases {
            let database = folder.appendingPathComponent(scope.configurationName + ".sqlite")
            let previous = NSPersistentStoreCoordinator(managedObjectModel: old)
            let store = try previous.addPersistentStore(type: .sqlite, configuration: scope.configurationName, at: database)
            let before = NSManagedObjectContext(.mainQueue)
            before.persistentStoreCoordinator = previous
            let item = NSEntityDescription.insertNewObject(forEntityName: "Souvenir", into: before)
            item.setValue("Plate", forKey: "title")
            let photo = NSEntityDescription.insertNewObject(forEntityName: "PhotoAsset", into: before)
            photo.setValue(Data([1, 2, 3]), forKey: "displayImageData")
            photo.setValue(item, forKey: "souvenir")
            try before.save()
            before.reset()
            try previous.remove(store)
            let next = NSPersistentStoreCoordinator(managedObjectModel: current)
            _ = try next.addPersistentStore(type: .sqlite, configuration: scope.configurationName, at: database,
                                            options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true])
            let after = NSManagedObjectContext(.mainQueue)
            after.persistentStoreCoordinator = next
            let restored = try XCTUnwrap(after.fetch(PhotoAsset.fetchRequest()).first)
            XCTAssertEqual(restored.souvenir?.title, "Plate")
            XCTAssertEqual(restored.displayImageData, Data([1, 2, 3]))
            XCTAssertNil(restored.capturedAt)
            XCTAssertNil(restored.captureLatitude)
            XCTAssertNil(restored.captureLongitude)
            XCTAssertEqual(restored.souvenir?.needsCaptureShareAttachment, false)
        }
    }
}

@MainActor private final class DeferredPlaceLookup: LocationSuggesting {
    let started = XCTestExpectation(description: "Photo place lookup started")
    private(set) var calls = 0
    private var continuation: CheckedContinuation<PlaceDraft?, Never>?

    func suggestedPlace(for location: ImportedPhotoLocation) async -> PlaceDraft? {
        calls += 1
        return await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }

    func finish(_ result: PlaceDraft?) {
        continuation?.resume(returning: result)
        continuation = nil
    }
    func searchPlaces(matching query: String) async throws -> [PlaceDraft] { throw URLError(.notConnectedToInternet) }
    func currentLocationPlace() async throws -> PlaceDraft { throw URLError(.notConnectedToInternet) }
}

@MainActor private final class DelayedFirstImport: PhotoImporting {
    let started = XCTestExpectation(description: "First image transfer started")
    private let importer = LivePhotoImportService()
    private var isFirst = true
    private var continuation: CheckedContinuation<Void, Never>?

    func importCameraCapture(_ capture: CameraCapture) async throws -> ImportedPhoto {
        if isFirst {
            isFirst = false
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        return try await importer.importCameraCapture(capture)
    }

    func resumeFirst() {
        continuation?.resume()
        continuation = nil
    }

    func importPhotoLibraryItem(_ item: PhotosPickerItem) async throws -> ImportedPhoto {
        try await importer.importPhotoLibraryItem(item)
    }
}
