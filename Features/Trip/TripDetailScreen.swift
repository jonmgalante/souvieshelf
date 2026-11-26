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

    var body: some View {
        Group {
            if let trip {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        TripHeader(trip: trip, cover: souvenirs.first { $0.galleryPhoto != nil },
                                   souvenirCount: souvenirs.count, mappedCount: souvenirs.filter {
                                       MapPresentationLogic.coordinate(latitude: $0.gotItInLatitude, longitude: $0.gotItInLongitude) != nil
                                   }.count, onViewOnMap: onViewOnMap)

                        TripSouvenirList(souvenirs: Array(souvenirs)) { id in
                            onOpenRoute(.tripSouvenir(tripID: tripID, souvenirID: id))
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
        .foregroundStyle(GalleryTheme.ink)
        .tint(GalleryTheme.accent)
        .background { GalleryTheme.canvas.ignoresSafeArea() }
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, trip != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Edit") {
                        isShowingEditSheet = true
                    }
                    .disabled(isDeleting)
                    Menu {
                        Button("Delete Trip", systemImage: "trash", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More trip actions")
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

enum TripDetailFetchRequestFactory {
    static func trip(
        tripID: UUID,
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) -> NSFetchRequest<Trip> {
        let request = Trip.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
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
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "id", ascending: true)
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

private struct TripHeader: View {
    @ObservedObject var trip: Trip
    let cover: Souvenir?
    let souvenirCount: Int
    let mappedCount: Int
    let onViewOnMap: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var title: String { TripPresentationLogic.displayTitle(from: trip.title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let cover, let photo = cover.galleryPhoto {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                                                        : AnyLayout(HStackLayout(spacing: 18))
                layout {
                    GalleryTheme.surface
                        .aspectRatio(typeSize.isAccessibilitySize ? 1.6 : 0.95, contentMode: .fit)
                        .overlay { GalleryPhoto(photo: photo, featured: true) }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Trip cover, \(cover.tripDisplayTitle)")
                    heading.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "suitcase")
                        .font(.title2).foregroundStyle(GalleryTheme.secondary)
                        .frame(width: 58, height: 58)
                        .background(GalleryTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    heading
                }
            }

            Button(action: onViewOnMap) {
                HStack {
                    Label("View on Map", systemImage: "map").font(.subheadline.weight(.semibold))
                    Spacer()
                    if souvenirCount > 0 {
                        Text("\(mappedCount) of \(souvenirCount) mapped")
                            .font(.footnote).foregroundStyle(GalleryTheme.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .foregroundStyle(GalleryTheme.accent)
                .padding(.horizontal, 14).frame(minHeight: 46)
                .background(GalleryTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(title) on Map")
            .accessibilityValue(souvenirCount > 0 ? "\(mappedCount) of \(souvenirCount) souvenirs mapped" : "No souvenirs")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(.largeTitle, design: .serif, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let destination = TripPresentationLogic.destinationSummary(from: trip.destinationSummary) {
                Text(destination).font(.subheadline)
            }
            if let dates = TripPresentationLogic.dateRangeSummary(startDate: trip.startDate, endDate: trip.endDate) {
                Text(dates).font(.footnote).foregroundStyle(GalleryTheme.secondary)
            }
        }
    }
}

private struct TripSouvenirList: View {
    let souvenirs: [Souvenir]
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Souvenirs").font(.system(.title2, design: .serif, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(souvenirs.count.formatted()).font(.subheadline.monospacedDigit())
                    .foregroundStyle(GalleryTheme.secondary)
                    .accessibilityLabel(TripPresentationLogic.souvenirCountText(souvenirs.count))
            }
            .padding(.bottom, 8)
            Divider()
            if souvenirs.isEmpty {
                Text("Souvenirs you add to this trip will appear here.")
                    .font(.body).foregroundStyle(GalleryTheme.secondary)
                    .padding(.vertical, 20)
            }
            ForEach(souvenirs, id: \.objectID) { souvenir in
                Button {
                    if let id = souvenir.id { onOpen(id) }
                } label: {
                    TripSouvenirRow(souvenir: souvenir)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trip.souvenir")
                .disabled(souvenir.id == nil)
                Divider()
            }
        }
    }
}

private struct TripSouvenirRow: View {
    @ObservedObject var souvenir: Souvenir

    var body: some View {
        HStack(spacing: 14) {
            GalleryTheme.surface
                .frame(width: 62, height: 62)
                .overlay {
                    if let photo = souvenir.galleryPhoto {
                        GalleryPhoto(photo: photo, featured: false)
                    } else {
                        Image(systemName: "photo").foregroundStyle(GalleryTheme.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(souvenir.tripDisplayTitle).font(.headline)
                if let place = PlacePresentationLogic.displayTitle(name: souvenir.gotItInName,
                        city: souvenir.gotItInCity, country: souvenir.gotItInCountryCode) {
                    Text(place).font(.subheadline).foregroundStyle(GalleryTheme.secondary)
                }
                if let date = souvenir.acquiredDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote).foregroundStyle(GalleryTheme.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(GalleryTheme.secondary).accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private extension Souvenir {
    var tripDisplayTitle: String { TripPresentationLogic.normalizedText(title) ?? "Untitled souvenir" }
}

struct TripSouvenirBrowser: View {
    let library: ActiveLibraryContext
    let dependencies: AppDependencies
    let onOpenRoute: (AppRoute) -> Void
    @FetchRequest private var souvenirs: FetchedResults<Souvenir>
    @State private var selectedID: UUID
    @Environment(\.dynamicTypeSize) private var typeSize

    init(tripID: UUID, souvenirID: UUID, library: ActiveLibraryContext, dependencies: AppDependencies,
         onOpenRoute: @escaping (AppRoute) -> Void) {
        self.library = library
        self.dependencies = dependencies
        self.onOpenRoute = onOpenRoute
        _selectedID = State(initialValue: souvenirID)
        _souvenirs = FetchRequest(fetchRequest: TripDetailFetchRequestFactory.souvenirs(tripID: tripID,
            activeLibraryContext: library, persistenceController: dependencies.persistenceController))
    }

    var body: some View {
        let ids = souvenirs.compactMap(\.id)
        if let index = ids.firstIndex(of: selectedID) {
            SouvenirDetailScreen(souvenirID: selectedID, activeLibraryContext: library,
                                 dependencies: dependencies, onOpenRoute: onOpenRoute)
                .id(selectedID)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if ids.count > 1 {
                        VStack(spacing: 0) {
                            Divider()
                            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0))
                                                                     : AnyLayout(HStackLayout(spacing: 8))
                            layout {
                                Button { move(-1, from: index, in: ids) } label: {
                                    Label("Previous", systemImage: "arrow.left")
                                        .frame(minHeight: 44)
                                }
                                .accessibilityLabel("Previous souvenir")
                                .disabled(index == 0)
                                Text("Souvenir \(index + 1) of \(ids.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(GalleryTheme.ink)
                                    .frame(maxWidth: .infinity)
                                Button { move(1, from: index, in: ids) } label: {
                                    HStack { Text("Next"); Image(systemName: "arrow.right") }
                                        .frame(minHeight: 44)
                                }
                                .accessibilityLabel("Next souvenir")
                                .disabled(index == ids.count - 1)
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.borderless)
                            .controlSize(.large)
                            .frame(minHeight: 52)
                            .padding(.horizontal, 18)
                            .contentShape(Rectangle())
                            .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { drag in
                                let delta = drag.translation
                                guard abs(delta.width) > abs(delta.height) else { return }
                                move(delta.width < 0 ? 1 : -1, from: index, in: ids)
                            })
                        }
                        .tint(GalleryTheme.accent)
                        .background(GalleryTheme.canvas)
                    }
                }
        } else {
            ContentUnavailableView("Souvenir no longer in this trip", systemImage: "suitcase")
                .navigationTitle("Trip souvenir")
        }
    }

    private func move(_ step: Int, from index: Int, in ids: [UUID]) {
        let destination = index + step
        guard ids.indices.contains(destination) else { return }
        selectedID = ids[destination]
    }
}
