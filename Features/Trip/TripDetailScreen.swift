import CoreData
import SwiftUI
import UIKit

struct TripDetailScreen: View {
    @Environment(\.dismiss) private var dismiss

    private let tripID: UUID
    private let activeLibraryContext: ActiveLibraryContext
    private let dependencies: AppDependencies
    private let onOpenRoute: (AppRoute) -> Void
    private let onViewOnMap: () -> Void

    @FetchRequest private var trips: FetchedResults<Trip>
    @FetchRequest private var souvenirs: FetchedResults<Souvenir>
    @State private var canEdit = false
    @State private var isShowingEditSheet = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    init(
        tripID: UUID,
        activeLibraryContext: ActiveLibraryContext,
        dependencies: AppDependencies,
        onOpenRoute: @escaping (AppRoute) -> Void,
        onViewOnMap: @escaping () -> Void
    ) {
        self.tripID = tripID
        self.activeLibraryContext = activeLibraryContext
        self.dependencies = dependencies
        self.onOpenRoute = onOpenRoute
        self.onViewOnMap = onViewOnMap
        self._trips = FetchRequest(
            fetchRequest: TripDetailFetchRequestFactory.trip(
                tripID: tripID,
                activeLibraryContext: activeLibraryContext,
                persistenceController: dependencies.persistenceController
            ),
            animation: .default
        )
        self._souvenirs = FetchRequest(
            fetchRequest: TripDetailFetchRequestFactory.souvenirs(
                tripID: tripID,
                activeLibraryContext: activeLibraryContext,
                persistenceController: dependencies.persistenceController
            ),
            animation: .default
        )
    }

    private var trip: Trip? {
        trips.first
    }

    private var tripSnapshot: TripEditSnapshot? {
        trip.flatMap(TripEditSnapshot.init)
    }

    private var coverPhotoData: Data? {
        souvenirs.lazy.compactMap(\.tripHeroImageData).first
    }

    var body: some View {
        Group {
            if let trip {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        if let coverPhotoData {
                            TripCoverPreview(photoData: coverPhotoData)
                        }

                        TripSummaryCard(
                            trip: trip,
                            souvenirCount: souvenirs.count,
                            onViewOnMap: onViewOnMap
                        )

                        TripSouvenirsCard(
                            souvenirs: Array(souvenirs),
                            onOpenRoute: onOpenRoute
                        )

                        if canEdit {
                            Button(role: .destructive) {
                                isShowingDeleteConfirmation = true
                            } label: {
                                if isDeleting {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Delete Trip")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isDeleting)
                        }
                    }
                    .padding(AppSpacing.large)
                }
            } else {
                ScrollView {
                    StateMessageView(
                        icon: "suitcase.rolling",
                        title: "Trip Unavailable",
                        message: "This trip may have been deleted or is still syncing in the active library."
                    )
                    .padding(AppSpacing.large)
                }
            }
        }
        .navigationTitle(trip.map { TripPresentationLogic.displayTitle(from: $0.title) } ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, trip != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        isShowingEditSheet = true
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .task(id: editabilityTaskKey) {
            canEdit = await dependencies.tripRepository.canEditTrip(
                id: tripID,
                libraryContext: activeLibraryContext
            )
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if let snapshot = tripSnapshot {
                EditTripSheet(
                    snapshot: snapshot,
                    activeLibraryContext: activeLibraryContext,
                    tripRepository: dependencies.tripRepository
                )
            }
        }
        .confirmationDialog(
            "Delete this trip?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Trip", role: .destructive) {
                Task {
                    await softDelete()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Souvenirs linked to this trip stay in the Library, but the trip moves to Recently Deleted and stops showing as an active trip until you restore it.")
        }
        .alert("Couldn't complete that action", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var editabilityTaskKey: String {
        [
            tripID.uuidString,
            activeLibraryContext.libraryID.uuidString,
            activeLibraryContext.storeScope.rawValue
        ].joined(separator: "|")
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

    private func softDelete() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await dependencies.tripRepository.softDeleteTrip(
                id: tripID,
                libraryContext: activeLibraryContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EditTripSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: EditTripViewModel

    init(
        snapshot: TripEditSnapshot,
        activeLibraryContext: ActiveLibraryContext,
        tripRepository: any TripRepository
    ) {
        self._viewModel = StateObject(
            wrappedValue: EditTripViewModel(
                snapshot: snapshot,
                activeLibraryContext: activeLibraryContext,
                tripRepository: tripRepository
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $viewModel.title)
                        .disabled(viewModel.isSaving)

                    TextField("Destination summary", text: $viewModel.destinationSummary, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .disabled(viewModel.isSaving)
                }
                .appGroupedRowChrome()

                Section("Dates") {
                    Toggle("Start date", isOn: $viewModel.hasStartDate.animation())
                        .disabled(viewModel.isSaving)

                    if viewModel.hasStartDate {
                        DatePicker(
                            "Start date",
                            selection: $viewModel.startDate,
                            displayedComponents: .date
                        )
                        .disabled(viewModel.isSaving)
                    }

                    Toggle("End date", isOn: $viewModel.hasEndDate.animation())
                        .disabled(viewModel.isSaving)

                    if viewModel.hasEndDate {
                        DatePicker(
                            "End date",
                            selection: $viewModel.endDate,
                            displayedComponents: .date
                        )
                        .disabled(viewModel.isSaving)
                    }
                }
                .appGroupedRowChrome()

                if let validationMessage = viewModel.validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                    .appGroupedRowChrome()
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    .appGroupedRowChrome()
                }
            }
            .appGroupedScreenChrome()
            .navigationTitle("Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
        .appScreenBackground()
        .appNavigationChrome()
        .interactiveDismissDisabled(viewModel.isSaving)
    }
}

@MainActor
final class EditTripViewModel: ObservableObject {
    @Published var title: String
    @Published var destinationSummary: String
    @Published var hasStartDate: Bool
    @Published var startDate: Date
    @Published var hasEndDate: Bool
    @Published var endDate: Date
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let activeLibraryContext: ActiveLibraryContext
    private let tripID: UUID
    private let tripRepository: any TripRepository

    init(
        snapshot: TripEditSnapshot,
        activeLibraryContext: ActiveLibraryContext,
        tripRepository: any TripRepository
    ) {
        self.activeLibraryContext = activeLibraryContext
        self.tripID = snapshot.tripID
        self.tripRepository = tripRepository
        self.title = snapshot.title
        self.destinationSummary = snapshot.destinationSummary
        self.hasStartDate = snapshot.startDate != nil
        self.startDate = snapshot.startDate ?? snapshot.endDate ?? .now
        self.hasEndDate = snapshot.endDate != nil
        self.endDate = snapshot.endDate ?? snapshot.startDate ?? .now
    }

    var validationMessage: String? {
        TripFormLogic.validationMessage(
            title: title,
            hasStartDate: hasStartDate,
            startDate: startDate,
            hasEndDate: hasEndDate,
            endDate: endDate
        )
    }

    var canSave: Bool {
        TripFormLogic.canSave(
            title: title,
            hasStartDate: hasStartDate,
            startDate: startDate,
            hasEndDate: hasEndDate,
            endDate: endDate,
            isSaving: isSaving
        )
    }

    func save() async -> Bool {
        errorMessage = nil

        if let validationMessage {
            errorMessage = validationMessage
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await tripRepository.updateTrip(
                UpdateTripInput(
                    libraryContext: activeLibraryContext,
                    tripID: tripID,
                    title: title,
                    destinationSummary: destinationSummary,
                    startDate: hasStartDate ? startDate : nil,
                    endDate: hasEndDate ? endDate : nil
                )
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct TripEditSnapshot: Equatable, Sendable {
    let tripID: UUID
    let title: String
    let destinationSummary: String
    let startDate: Date?
    let endDate: Date?

    init?(trip: Trip) {
        guard let tripID = trip.id else {
            return nil
        }

        self.tripID = tripID
        self.title = TripPresentationLogic.normalizedText(trip.title) ?? ""
        self.destinationSummary = TripPresentationLogic.destinationSummary(from: trip.destinationSummary) ?? ""
        self.startDate = trip.startDate
        self.endDate = trip.endDate
    }
}

enum TripPresentationLogic {
    static func normalizedText(_ value: String?) -> String? {
        let collapsed = value?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard let collapsed,
              !collapsed.isEmpty else {
            return nil
        }

        return collapsed
    }

    static func displayTitle(from title: String?) -> String {
        normalizedText(title) ?? "Untitled trip"
    }

    static func destinationSummary(from value: String?) -> String? {
        normalizedText(value)
    }

    static func dateRangeSummary(
        startDate: Date?,
        endDate: Date?,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        switch (startDate, endDate) {
        case let (startDate?, endDate?):
            if calendar.isDate(startDate, inSameDayAs: endDate) {
                return formattedDate(
                    startDate,
                    calendar: calendar,
                    locale: locale,
                    timeZone: timeZone
                )
            }

            return [
                formattedDate(startDate, calendar: calendar, locale: locale, timeZone: timeZone),
                formattedDate(endDate, calendar: calendar, locale: locale, timeZone: timeZone)
            ]
            .joined(separator: " - ")
        case let (startDate?, nil):
            return "Starts \(formattedDate(startDate, calendar: calendar, locale: locale, timeZone: timeZone))"
        case let (nil, endDate?):
            return "Ends \(formattedDate(endDate, calendar: calendar, locale: locale, timeZone: timeZone))"
        case (nil, nil):
            return nil
        }
    }

    static func souvenirCountText(_ souvenirCount: Int) -> String {
        "\(souvenirCount) \(souvenirCount == 1 ? "souvenir" : "souvenirs")"
    }

    private static func formattedDate(
        _ date: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private enum TripDetailFetchRequestFactory {
    static func trip(
        tripID: UUID,
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
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
        applyStoreScope(
            to: request,
            activeLibraryContext: activeLibraryContext,
            persistenceController: persistenceController
        )
        return request
    }

    static func souvenirs(
        tripID: UUID,
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) -> NSFetchRequest<Souvenir> {
        let request = Souvenir.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.relationshipKeyPathsForPrefetching = ["photos", "trip"]
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "trip.id == %@", tripID as CVarArg),
                NSPredicate(format: "trip.deletedAt == NIL"),
                NSPredicate(format: "library.id == %@", activeLibraryContext.libraryID as CVarArg),
                NSPredicate(format: "deletedAt == NIL")
            ]
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

private struct TripSummaryCard: View {
    let trip: Trip
    let souvenirCount: Int
    let onViewOnMap: () -> Void

    var body: some View {
        SurfaceCard {
            Text(TripPresentationLogic.displayTitle(from: trip.title))
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                if let dateRangeSummary = TripPresentationLogic.dateRangeSummary(
                    startDate: trip.startDate,
                    endDate: trip.endDate
                ) {
                    TripMetadataLabel(
                        systemImage: "calendar",
                        text: dateRangeSummary
                    )
                }

                if let destinationSummary = TripPresentationLogic.destinationSummary(from: trip.destinationSummary) {
                    TripMetadataLabel(
                        systemImage: "mappin.and.ellipse",
                        text: destinationSummary
                    )
                }

                TripMetadataLabel(
                    systemImage: "shippingbox.fill",
                    text: TripPresentationLogic.souvenirCountText(souvenirCount)
                )
            }

            Button(action: onViewOnMap) {
                Label("View on Map", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("View \(TripPresentationLogic.displayTitle(from: trip.title)) on Map")
        }
        .accessibilityElement(children: .contain)
    }
}

private struct TripSouvenirsCard: View {
    let souvenirs: [Souvenir]
    let onOpenRoute: (AppRoute) -> Void

    var body: some View {
        SurfaceCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Souvenirs")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text(TripPresentationLogic.souvenirCountText(souvenirs.count))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if souvenirs.isEmpty {
                Text("No active souvenirs are linked to this trip yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(spacing: AppSpacing.medium) {
                    ForEach(Array(souvenirs.enumerated()), id: \.element.objectID) { index, souvenir in
                        if let souvenirID = souvenir.id {
                            Button {
                                onOpenRoute(.souvenir(souvenirID))
                            } label: {
                                TripSouvenirRow(souvenir: souvenir)
                            }
                            .buttonStyle(.plain)
                        } else {
                            TripSouvenirRow(souvenir: souvenir)
                        }

                        if index < souvenirs.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct TripSouvenirRow: View {
    let souvenir: Souvenir

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            TripSouvenirThumbnail(
                data: souvenir.tripThumbnailData,
                placeholderSystemImage: "shippingbox.fill"
            )

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(souvenir.tripDisplayTitle)
                    .foregroundStyle(AppTheme.textPrimary)

                if let placeSummary = souvenir.tripPlaceSummary {
                    TripMetadataLabel(
                        systemImage: "mappin.and.ellipse",
                        text: placeSummary
                    )
                }

                if let acquiredSummary = souvenir.tripAcquiredSummary {
                    TripMetadataLabel(
                        systemImage: "calendar",
                        text: acquiredSummary
                    )
                }
            }

            Spacer(minLength: AppSpacing.small)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textMuted)
                .padding(.top, AppSpacing.xSmall)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TripSouvenirThumbnail: View {
    let data: Data?
    let placeholderSystemImage: String

    var body: some View {
        Group {
            if let data,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSystemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.placeholderSurface)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TripCoverPreview: View {
    let photoData: Data

    var body: some View {
        Group {
            if let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 260)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.placeholderSurface)
                    .frame(height: 220)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
            }
        }
    }
}

private struct TripMetadataLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .labelStyle(.titleAndIcon)
    }
}

private extension Souvenir {
    var tripDisplayTitle: String {
        TripPresentationLogic.normalizedText(title) ?? "Untitled souvenir"
    }

    var tripPlaceSummary: String? {
        PlacePresentationLogic.displayTitle(
            name: gotItInName,
            city: gotItInCity,
            country: gotItInCountryCode
        )
    }

    var tripAcquiredSummary: String? {
        if let acquiredDate {
            return "Got it \(acquiredDate.formatted(date: .abbreviated, time: .omitted))"
        }

        if let updatedAt {
            return "Updated \(updatedAt.formatted(date: .abbreviated, time: .omitted))"
        }

        return nil
    }

    var tripThumbnailData: Data? {
        sortedTripPhotos.first(where: { $0.thumbnailData != nil })?.thumbnailData
            ?? sortedTripPhotos.first(where: { $0.displayImageData != nil })?.displayImageData
    }

    var tripHeroImageData: Data? {
        sortedTripPhotos.first(where: { $0.displayImageData != nil })?.displayImageData
            ?? sortedTripPhotos.first(where: { $0.thumbnailData != nil })?.thumbnailData
    }

    private var sortedTripPhotos: [PhotoAsset] {
        ((photos as? Set<PhotoAsset>) ?? [])
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary {
                    return lhs.isPrimary && !rhs.isPrimary
                }

                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }

                return (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
            }
    }
}
