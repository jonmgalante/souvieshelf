import CoreData
import SwiftUI

struct RecentlyDeletedScreen: View {
    private let activeLibraryContext: ActiveLibraryContext
    private let deletedRepository: any DeletedRepository
    private let storeResolutionMessage: String?

    @FetchRequest private var deletedSouvenirs: FetchedResults<Souvenir>
    @FetchRequest private var deletedTrips: FetchedResults<Trip>
    @State private var restoringTarget: RestoreTarget?
    @State private var errorMessage: String?

    init(
        activeLibraryContext: ActiveLibraryContext,
        dependencies: AppDependencies
    ) {
        self.activeLibraryContext = activeLibraryContext
        self.deletedRepository = dependencies.deletedRepository
        self.storeResolutionMessage = RecentlyDeletedFetchRequestFactory.storeResolutionMessage(
            for: activeLibraryContext,
            persistenceController: dependencies.persistenceController
        )
        self._deletedSouvenirs = FetchRequest(
            fetchRequest: RecentlyDeletedFetchRequestFactory.deletedSouvenirs(
                for: activeLibraryContext,
                persistenceController: dependencies.persistenceController
            ),
            animation: .default
        )
        self._deletedTrips = FetchRequest(
            fetchRequest: RecentlyDeletedFetchRequestFactory.deletedTrips(
                for: activeLibraryContext,
                persistenceController: dependencies.persistenceController
            ),
            animation: .default
        )
    }

    private var isEmpty: Bool {
        deletedSouvenirs.isEmpty && deletedTrips.isEmpty
    }

    var body: some View {
        Group {
            if let storeResolutionMessage {
                ScrollView {
                    StateMessageView(
                        icon: "trash",
                        title: "Recently Deleted Unavailable",
                        message: storeResolutionMessage
                    )
                    .padding(AppSpacing.large)
                }
                .appScreenBackground()
            } else if isEmpty {
                ScrollView {
                    StateMessageView(
                        icon: "trash",
                        title: "Recently Deleted is empty",
                        message: "Souvenirs and trips you delete from Our Library will appear here."
                    )
                    .padding(AppSpacing.large)
                }
                .appScreenBackground()
            } else {
                List {
                    if !deletedSouvenirs.isEmpty {
                        Section("Souvenirs") {
                            ForEach(deletedSouvenirs, id: \.objectID) { souvenir in
                                RecentlyDeletedSouvenirRow(
                                    souvenir: souvenir,
                                    isRestoring: restoringTarget == souvenir.id.map(RestoreTarget.souvenir),
                                    restoreState: souvenir.id == nil ? .unavailable : .ready,
                                    isRestoreEnabled: restoringTarget == nil,
                                    onRestore: {
                                        guard let souvenirID = souvenir.id else {
                                            errorMessage = "This souvenir is missing the data needed to restore it."
                                            return
                                        }

                                        Task {
                                            await restoreSouvenir(id: souvenirID)
                                        }
                                    }
                                )
                            }
                        }
                    }

                    if !deletedTrips.isEmpty {
                        Section("Trips") {
                            ForEach(deletedTrips, id: \.objectID) { trip in
                                RecentlyDeletedTripRow(
                                    trip: trip,
                                    isRestoring: restoringTarget == trip.id.map(RestoreTarget.trip),
                                    restoreState: trip.id == nil ? .unavailable : .ready,
                                    isRestoreEnabled: restoringTarget == nil,
                                    onRestore: {
                                        guard let tripID = trip.id else {
                                            errorMessage = "This trip is missing the data needed to restore it."
                                            return
                                        }

                                        Task {
                                            await restoreTrip(id: tripID)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .appGroupedScreenChrome()
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't restore item", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { shouldPresent in
                if !shouldPresent {
                    errorMessage = nil
                }
            }
        )
    }

    @MainActor
    private func restoreSouvenir(id: UUID) async {
        restoringTarget = .souvenir(id)
        defer { restoringTarget = nil }

        do {
            try await deletedRepository.restoreSouvenir(
                id: id,
                libraryContext: activeLibraryContext
            )
        } catch {
            errorMessage = Self.restoreErrorMessage(for: error)
        }
    }

    @MainActor
    private func restoreTrip(id: UUID) async {
        restoringTarget = .trip(id)
        defer { restoringTarget = nil }

        do {
            try await deletedRepository.restoreTrip(
                id: id,
                libraryContext: activeLibraryContext
            )
        } catch {
            errorMessage = Self.restoreErrorMessage(for: error)
        }
    }

    private static func restoreErrorMessage(for error: Error) -> String {
        switch error {
        case SharingRepositoryError.missingSouvenir(_, _, _):
            return "This souvenir is no longer available to restore."
        case SharingRepositoryError.missingTrip(_, _, _):
            return "This trip is no longer available to restore."
        case PersistenceController.PersistenceError.missingPersistentStore(_):
            return "SouvieShelf couldn't reach the current library store right now."
        default:
            return error.localizedDescription
        }
    }
}

private enum RestoreTarget: Hashable {
    case souvenir(UUID)
    case trip(UUID)
}

private enum RestoreActionState {
    case ready
    case unavailable
}

private struct RecentlyDeletedSouvenirRow: View {
    let souvenir: Souvenir
    let isRestoring: Bool
    let restoreState: RestoreActionState
    let isRestoreEnabled: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(souvenir.recentlyDeletedTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if let tripTitle = souvenir.recentlyDeletedTripTitle {
                    RecentlyDeletedMetadataLabel(
                        systemImage: "suitcase.rolling.fill",
                        text: tripTitle
                    )
                }

                if let placeSummary = souvenir.recentlyDeletedPlaceSummary {
                    RecentlyDeletedMetadataLabel(
                        systemImage: "mappin.and.ellipse",
                        text: placeSummary
                    )
                }

                if let deletedSummary = souvenir.deletedAtSummary {
                    RecentlyDeletedMetadataLabel(
                        systemImage: "calendar",
                        text: deletedSummary
                    )
                }
            }

            Spacer(minLength: AppSpacing.small)

            if isRestoring {
                ProgressView()
            } else {
                restoreAction
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
        .appGroupedRowChrome()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var restoreAction: some View {
        switch restoreState {
        case .ready:
            Button("Restore", action: onRestore)
                .buttonStyle(.borderless)
                .disabled(!isRestoreEnabled)
                .accessibilityLabel("Restore \(souvenir.recentlyDeletedTitle)")
                .accessibilityHint("Moves it back into the Library.")
        case .unavailable:
            Text("Unavailable")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

private struct RecentlyDeletedTripRow: View {
    let trip: Trip
    let isRestoring: Bool
    let restoreState: RestoreActionState
    let isRestoreEnabled: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(trip.recentlyDeletedTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if let dateRangeSummary = trip.recentlyDeletedDateRangeSummary {
                    RecentlyDeletedMetadataLabel(
                        systemImage: "calendar",
                        text: dateRangeSummary
                    )
                }

                if let deletedSummary = trip.deletedAtSummary {
                    RecentlyDeletedMetadataLabel(
                        systemImage: "trash",
                        text: deletedSummary
                    )
                }
            }

            Spacer(minLength: AppSpacing.small)

            if isRestoring {
                ProgressView()
            } else {
                restoreAction
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
        .appGroupedRowChrome()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var restoreAction: some View {
        switch restoreState {
        case .ready:
            Button("Restore", action: onRestore)
                .buttonStyle(.borderless)
                .disabled(!isRestoreEnabled)
                .accessibilityLabel("Restore \(trip.recentlyDeletedTitle)")
                .accessibilityHint("Moves it back into the Library.")
        case .unavailable:
            Text("Unavailable")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

private struct RecentlyDeletedMetadataLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .labelStyle(.titleAndIcon)
    }
}

private enum RecentlyDeletedFetchRequestFactory {
    static func storeResolutionMessage(
        for activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) -> String? {
        guard (try? persistenceController.persistentStore(for: activeLibraryContext.storeScope)) != nil else {
            return "SouvieShelf couldn't load deleted items for the active library right now."
        }

        return nil
    }

    static func deletedSouvenirs(
        for activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) -> NSFetchRequest<Souvenir> {
        let request = Souvenir.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "deletedAt", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.relationshipKeyPathsForPrefetching = ["trip"]
        request.predicate = NSPredicate(
            format: "library.id == %@ AND deletedAt != NIL",
            activeLibraryContext.libraryID as CVarArg
        )
        applyStoreScope(
            to: request,
            activeLibraryContext: activeLibraryContext,
            persistenceController: persistenceController
        )
        return request
    }

    static func deletedTrips(
        for activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) -> NSFetchRequest<Trip> {
        let request = Trip.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "deletedAt", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.predicate = NSPredicate(
            format: "library.id == %@ AND deletedAt != NIL",
            activeLibraryContext.libraryID as CVarArg
        )
        applyStoreScope(
            to: request,
            activeLibraryContext: activeLibraryContext,
            persistenceController: persistenceController
        )
        return request
    }

    private static func applyStoreScope<ResultType: NSManagedObject>(
        to request: NSFetchRequest<ResultType>,
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) {
        guard let store = try? persistenceController.persistentStore(for: activeLibraryContext.storeScope) else {
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
}

private extension Souvenir {
    var recentlyDeletedTitle: String {
        title.recentlyDeletedNormalizedValue ?? "Untitled souvenir"
    }

    var recentlyDeletedTripTitle: String? {
        guard let trip,
              trip.deletedAt == nil else {
            return nil
        }

        return TripPresentationLogic.normalizedText(trip.title)
    }

    var recentlyDeletedPlaceSummary: String? {
        PlacePresentationLogic.displayTitle(
            name: gotItInName.recentlyDeletedNormalizedValue,
            city: gotItInCity.recentlyDeletedNormalizedValue,
            country: gotItInCountryCode.recentlyDeletedNormalizedValue
        )
    }

    var deletedAtSummary: String? {
        guard let deletedAt else {
            return nil
        }

        return "Deleted \(deletedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

private extension Trip {
    var recentlyDeletedTitle: String {
        TripPresentationLogic.displayTitle(from: title)
    }

    var recentlyDeletedDateRangeSummary: String? {
        TripPresentationLogic.dateRangeSummary(
            startDate: startDate,
            endDate: endDate
        )
    }

    var deletedAtSummary: String? {
        guard let deletedAt else {
            return nil
        }

        return "Deleted \(deletedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

private extension String {
    var recentlyDeletedNormalizedValue: String? {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsed.isEmpty ? nil : collapsed
    }
}

private extension Optional where Wrapped == String {
    var recentlyDeletedNormalizedValue: String? {
        guard let self else {
            return nil
        }

        let collapsed = self.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsed.isEmpty ? nil : collapsed
    }
}
