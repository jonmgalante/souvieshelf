import CloudKit
import CoreData
import Foundation

enum ICloudStatus: Equatable, Sendable {
    case available
    case unavailable
}

enum LaunchContextResolution: Equatable, Sendable {
    case iCloudUnavailable
    case needsPairing
    case ready(ActiveLibraryContext)
}

protocol BootstrapRepository: Sendable {
    func iCloudStatus() async -> ICloudStatus
    func resolveLaunchContext() async -> LaunchContextResolution
    func acceptShare(metadata: CKShare.Metadata) async throws
}

protocol LibraryRepository: Sendable {
    func createLibrary(title: String) async throws -> ActiveLibraryContext
    func activeLibraryContext() async -> ActiveLibraryContext?
    func libraryContext(in scope: StoreScope) async -> ActiveLibraryContext?
}

extension LibraryRepository {
    func createOurLibrary() async throws -> ActiveLibraryContext {
        try await createLibrary(title: "Our Library")
    }
}

@MainActor
final class LibraryShareControllerContext: Identifiable {
    nonisolated let id: UUID
    let libraryID: UUID
    let libraryTitle: String
    let share: CKShare
    let container: CKContainer

    init(
        libraryID: UUID,
        libraryTitle: String,
        share: CKShare,
        container: CKContainer
    ) {
        self.id = libraryID
        self.libraryID = libraryID
        self.libraryTitle = libraryTitle
        self.share = share
        self.container = container
    }
}

protocol SharingRepository: Sendable {
    func fetchShareSummary(libraryID: UUID, scope: StoreScope) async -> ShareSummary?
    @MainActor
    func prepareShareController(
        libraryID: UUID,
        scope: StoreScope
    ) async throws -> LibraryShareControllerContext
    func attachObjectsToLibraryShareIfNeeded(
        objectIDs: [NSManagedObjectID],
        libraryID: UUID,
        scope: StoreScope
    ) async throws
}

protocol SouvenirRepository: Sendable {
    @discardableResult
    func createSouvenir(_ input: CreateSouvenirInput) async throws -> UUID

    func canEditSouvenir(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async -> Bool
    func updateSouvenir(_ input: UpdateSouvenirInput) async throws
    func softDeleteSouvenir(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async throws
}

protocol TripRepository: Sendable {
    @discardableResult
    func createTrip(_ input: CreateTripInput) async throws -> UUID

    func canEditTrip(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async -> Bool
    func updateTrip(_ input: UpdateTripInput) async throws
    func softDeleteTrip(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async throws
}

protocol DeletedRepository: Sendable {
    func restoreSouvenir(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async throws
    func restoreTrip(
        id: UUID,
        libraryContext: ActiveLibraryContext
    ) async throws
}

protocol MapRepository: Sendable {
    func souvenirFetchRequest(
        for context: MapFilterContext,
        activeLibraryContext: ActiveLibraryContext
    ) -> NSFetchRequest<Souvenir>

    func tripFetchRequest(
        tripID: UUID,
        activeLibraryContext: ActiveLibraryContext
    ) -> NSFetchRequest<Trip>
}
