import CoreData
import PhotosUI
import SwiftUI
import UIKit

struct AddSouvenirSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: AddSouvenirViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var activePlaceField: AddSouvenirPlaceField?
    @State private var isShowingTripPicker = false

    private let persistenceController: PersistenceController
    private let tripRepository: any TripRepository
    private let permissionCoordinator: any PermissionCoordinating
    private let locationSuggester: any LocationSuggesting
    private let onSaved: () -> Void

    init(
        activeLibraryContext: ActiveLibraryContext,
        dependencies: AppDependencies,
        onSaved: @escaping () -> Void
    ) {
        self.persistenceController = dependencies.persistenceController
        self.tripRepository = dependencies.tripRepository
        self.permissionCoordinator = dependencies.permissionCoordinator
        self.locationSuggester = dependencies.locationSuggester
        self.onSaved = onSaved
        self._viewModel = StateObject(
            wrappedValue: AddSouvenirViewModel(
                activeLibraryContext: activeLibraryContext,
                souvenirRepository: dependencies.souvenirRepository,
                permissionCoordinator: dependencies.permissionCoordinator,
                photoImporter: dependencies.photoImporter,
                locationSuggester: dependencies.locationSuggester
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.importedPhoto == nil {
                    sourceChoiceContent
                } else {
                    editingContent
                }
            }
            .navigationTitle(viewModel.importedPhoto == nil ? "Add Souvenir" : "New Souvenir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if viewModel.importedPhoto != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                await saveAndDismissIfNeeded()
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
        }
        .appScreenBackground()
        .appNavigationChrome()
        .photosPicker(
            isPresented: $viewModel.isShowingPhotoLibraryPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else {
                return
            }

            Task {
                await viewModel.importPhotoLibraryItem(newValue)
                selectedPhotoItem = nil
            }
        }
        .sheet(isPresented: $viewModel.isShowingCameraPicker) {
            CameraCaptureSheet(
                onCancel: {
                    viewModel.isShowingCameraPicker = false
                },
                onCapture: { capture in
                    viewModel.isShowingCameraPicker = false
                    Task {
                        await viewModel.importCameraCapture(capture)
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingTripPicker) {
            TripPickerSheet(
                activeLibraryContext: viewModel.activeLibraryContext,
                persistenceController: persistenceController,
                tripRepository: tripRepository,
                selectedTrip: viewModel.selectedTrip,
                onSelect: { trip in
                    viewModel.selectedTrip = trip
                    isShowingTripPicker = false
                }
            )
        }
        .sheet(item: $activePlaceField) { field in
            PlaceSearchSheet(
                field: field,
                currentSelection: field == .gotItIn ? viewModel.gotItInPlace : viewModel.fromPlace,
                permissionCoordinator: permissionCoordinator,
                locationSuggester: locationSuggester,
                onSelect: { selectedPlace in
                    switch field {
                    case .gotItIn:
                        viewModel.gotItInPlace = selectedPlace
                    case .from:
                        viewModel.fromPlace = selectedPlace
                    }
                    activePlaceField = nil
                }
            )
        }
        .alert("Couldn't complete that action", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { shouldPresent in
                if !shouldPresent {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private var sourceChoiceContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                StateMessageView(
                    icon: "shippingbox.circle.fill",
                    title: "Start With One Photo",
                    message: "Pick a photo from your library or take one now. SouvieShelf will suggest the date and place when that metadata is available."
                )

                SurfaceCard {
                    Button {
                        Task {
                            await viewModel.beginPhotoLibraryImport()
                        }
                    } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isBusy)

                    Button {
                        Task {
                            await viewModel.beginCameraCapture()
                        }
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isBusy || !viewModel.isCameraAvailable)

                    if !viewModel.isCameraAvailable {
                        Text("Camera capture is available on iPhone hardware, not the simulator.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    if viewModel.isImporting {
                        HStack(spacing: AppSpacing.small) {
                            ProgressView()
                            Text("Preparing your photo...")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
            .padding(AppSpacing.large)
        }
        .appScreenBackground()
    }

    private var editingContent: some View {
        Form {
            if let importedPhoto = viewModel.importedPhoto {
                Section {
                    ImportedPhotoPreview(imageData: importedPhoto.displayImageData)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                .appGroupedRowChrome(Color.clear)
            }

            Section {
                Button {
                    isShowingTripPicker = true
                } label: {
                    FormValueRow(
                        label: "Trip",
                        value: viewModel.selectedTrip?.title,
                        placeholder: "Optional"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    activePlaceField = .gotItIn
                } label: {
                    FormValueRow(
                        label: "Got it in",
                        value: viewModel.gotItInPlace?.displayTitle,
                        placeholder: viewModel.isResolvingSuggestedPlace ? "Looking up place..." : "Optional"
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSaving)

                Button {
                    activePlaceField = .from
                } label: {
                    FormValueRow(
                        label: "From",
                        value: viewModel.fromPlace?.displayTitle,
                        placeholder: "Optional"
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSaving)
            }
            .appGroupedRowChrome()

            Section {
                if viewModel.acquiredDate == nil {
                    Button("Add Date") {
                        viewModel.acquiredDate = viewModel.defaultAcquiredDate
                    }
                    .disabled(viewModel.isSaving)
                } else {
                    DatePicker(
                        "Date",
                        selection: acquiredDateBinding,
                        displayedComponents: .date
                    )
                    .disabled(viewModel.isSaving)

                    Button("Clear Date", role: .destructive) {
                        viewModel.acquiredDate = nil
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .appGroupedRowChrome()

            Section {
                TextField("Title", text: $viewModel.title)
                    .disabled(viewModel.isSaving)

                TextField("Story", text: $viewModel.story, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
                    .disabled(viewModel.isSaving)
            }
            .appGroupedRowChrome()
        }
        .appGroupedScreenChrome()
        .overlay {
            if viewModel.isImporting {
                ProgressView("Importing photo...")
                    .padding(AppSpacing.large)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.surfaceOverlay)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.borderSubtle, lineWidth: 1)
                    )
            }
        }
    }

    private var acquiredDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.acquiredDate ?? viewModel.defaultAcquiredDate },
            set: { viewModel.acquiredDate = $0 }
        )
    }

    private func saveAndDismissIfNeeded() async {
        let didSave = await viewModel.save()
        guard didSave else {
            return
        }

        onSaved()
        dismiss()
    }
}

struct TripPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let activeLibraryContext: ActiveLibraryContext
    let tripRepository: any TripRepository
    let selectedTrip: TripSelection?
    let onSelect: (TripSelection?) -> Void

    @FetchRequest private var trips: FetchedResults<Trip>
    @State private var isShowingCreateTrip = false

    init(
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController,
        tripRepository: any TripRepository,
        selectedTrip: TripSelection?,
        onSelect: @escaping (TripSelection?) -> Void
    ) {
        self.activeLibraryContext = activeLibraryContext
        self.tripRepository = tripRepository
        self.selectedTrip = selectedTrip
        self.onSelect = onSelect
        self._trips = FetchRequest(
            fetchRequest: Self.makeFetchRequest(
                activeLibraryContext: activeLibraryContext,
                persistenceController: persistenceController
            ),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        selectionRow(
                            title: "No Trip",
                            subtitle: "Save this souvenir without assigning a trip yet.",
                            isSelected: selectedTrip == nil
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingCreateTrip = true
                    } label: {
                        Label("Create Trip", systemImage: "plus")
                    }
                }
                .appGroupedRowChrome()

                Section("Trips") {
                    if trips.isEmpty {
                        Text("Create a trip to group souvenirs from the same journey together.")
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(trips, id: \.objectID) { trip in
                            if let selection = TripSelection(trip: trip) {
                                Button {
                                    onSelect(selection)
                                    dismiss()
                                } label: {
                                    selectionRow(
                                        title: selection.title,
                                        subtitle: selection.subtitle,
                                        isSelected: selectedTrip?.id == selection.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .appGroupedRowChrome()
            }
            .appGroupedScreenChrome()
            .navigationTitle("Select Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .appScreenBackground()
        .appNavigationChrome()
        .sheet(isPresented: $isShowingCreateTrip) {
            CreateTripSheet(
                activeLibraryContext: activeLibraryContext,
                tripRepository: tripRepository,
                onCreated: { selection in
                    onSelect(selection)
                    isShowingCreateTrip = false
                    dismiss()
                }
            )
        }
    }

    private static func makeFetchRequest(
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) -> NSFetchRequest<Trip> {
        let request = Trip.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.predicate = NSPredicate(
            format: "library.id == %@ AND deletedAt == NIL",
            activeLibraryContext.libraryID as CVarArg
        )

        if let store = try? persistenceController.persistentStore(for: activeLibraryContext.storeScope) {
            request.affectedStores = [store]
        } else {
            request.predicate = NSCompoundPredicate(
                andPredicateWithSubpredicates: [
                    request.predicate ?? NSPredicate(value: true),
                    NSPredicate(value: false)
                ]
            )
        }

        return request
    }

    private func selectionRow(
        title: String,
        subtitle: String?,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .foregroundStyle(AppTheme.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .padding(.vertical, AppSpacing.small)
        .padding(.horizontal, AppSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? AppTheme.chipSelectedFill : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? AppTheme.accentPrimary.opacity(0.35) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

struct CreateTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CreateTripViewModel

    private let onCreated: (TripSelection) -> Void

    init(
        activeLibraryContext: ActiveLibraryContext,
        tripRepository: any TripRepository,
        onCreated: @escaping (TripSelection) -> Void
    ) {
        self._viewModel = StateObject(
            wrappedValue: CreateTripViewModel(
                activeLibraryContext: activeLibraryContext,
                tripRepository: tripRepository
            )
        )
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $viewModel.title)
                        .disabled(viewModel.isSaving)

                    TextField("Destination summary", text: $viewModel.destinationSummary, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .disabled(viewModel.isSaving)
                }
                .appGroupedRowChrome()

                Section {
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

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    .appGroupedRowChrome()
                }
            }
            .appGroupedScreenChrome()
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let selection = await viewModel.save() {
                                onCreated(selection)
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
    }
}

struct PlaceSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlaceSearchViewModel

    let field: AddSouvenirPlaceField
    let currentSelection: PlaceDraft?
    let onSelect: (PlaceDraft?) -> Void

    init(
        field: AddSouvenirPlaceField,
        currentSelection: PlaceDraft?,
        permissionCoordinator: any PermissionCoordinating,
        locationSuggester: any LocationSuggesting,
        onSelect: @escaping (PlaceDraft?) -> Void
    ) {
        self.field = field
        self.currentSelection = currentSelection
        self.onSelect = onSelect
        self._viewModel = StateObject(
            wrappedValue: PlaceSearchViewModel(
                field: field,
                permissionCoordinator: permissionCoordinator,
                locationSuggester: locationSuggester
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if let currentSelection {
                    Section {
                        Button("Clear \(field.label)") {
                            onSelect(nil)
                            dismiss()
                        }
                    }
                    .appGroupedRowChrome()

                    Section("Current") {
                        placeRow(for: currentSelection)
                    }
                    .appGroupedRowChrome()
                }

                if field.supportsCurrentLocation {
                    Section {
                        Button {
                            Task {
                                if let currentLocationPlace = await viewModel.useCurrentLocation() {
                                    onSelect(currentLocationPlace)
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: AppSpacing.medium) {
                                Label("Use Current Location", systemImage: "location.fill")
                                Spacer()
                                if viewModel.isResolvingCurrentLocation {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(viewModel.isResolvingCurrentLocation)
                    }
                    .appGroupedRowChrome()
                }

                Section("Results") {
                    if viewModel.isSearching {
                        HStack(spacing: AppSpacing.small) {
                            ProgressView()
                            Text("Searching...")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    } else if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Search for a place.")
                            .foregroundStyle(AppTheme.textSecondary)
                    } else if viewModel.results.isEmpty {
                        Text("No places matched that search.")
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(viewModel.results) { result in
                            Button {
                                onSelect(result.place)
                                dismiss()
                            } label: {
                                placeRow(for: result.place)
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
            .searchable(text: $viewModel.query, prompt: "Search places")
            .navigationTitle(field.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .appScreenBackground()
        .appNavigationChrome()
        .task(id: viewModel.query) {
            await viewModel.search()
        }
    }

    private func placeRow(for place: PlaceDraft) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(place.displayTitle)
                .foregroundStyle(AppTheme.textPrimary)

            if let subtitle = place.displaySubtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

@MainActor
final class AddSouvenirViewModel: ObservableObject {
    let activeLibraryContext: ActiveLibraryContext

    @Published var importedPhoto: ImportedPhoto?
    @Published var selectedTrip: TripSelection?
    @Published var gotItInPlace: PlaceDraft?
    @Published var fromPlace: PlaceDraft?
    @Published var acquiredDate: Date?
    @Published var title = ""
    @Published var story = ""
    @Published var isImporting = false
    @Published var isSaving = false
    @Published var isResolvingSuggestedPlace = false
    @Published var isShowingPhotoLibraryPicker = false
    @Published var isShowingCameraPicker = false
    @Published var errorMessage: String?

    private let souvenirRepository: any SouvenirRepository
    private let permissionCoordinator: any PermissionCoordinating
    private let photoImporter: any PhotoImporting
    private let locationSuggester: any LocationSuggesting

    init(
        activeLibraryContext: ActiveLibraryContext,
        souvenirRepository: any SouvenirRepository,
        permissionCoordinator: any PermissionCoordinating,
        photoImporter: any PhotoImporting,
        locationSuggester: any LocationSuggesting
    ) {
        self.activeLibraryContext = activeLibraryContext
        self.souvenirRepository = souvenirRepository
        self.permissionCoordinator = permissionCoordinator
        self.photoImporter = photoImporter
        self.locationSuggester = locationSuggester
    }

    var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var isBusy: Bool {
        isImporting || isSaving
    }

    var canSave: Bool {
        AddSouvenirFormLogic.canSave(hasImportedPhoto: importedPhoto != nil, isBusy: isBusy)
    }

    var defaultAcquiredDate: Date {
        acquiredDate ?? importedPhoto?.capturedAt ?? .now
    }

    func beginPhotoLibraryImport() async {
        errorMessage = nil
        let permissionStatus = await permissionCoordinator.requestAccess(for: .photoLibrary)
        guard permissionStatus == .authorized else {
            errorMessage = "Allow Photo Library access in Settings to import a souvenir photo."
            return
        }

        isShowingPhotoLibraryPicker = true
    }

    func beginCameraCapture() async {
        errorMessage = nil

        guard isCameraAvailable else {
            errorMessage = "Camera capture is only available on an iPhone with a camera."
            return
        }

        let permissionStatus = await permissionCoordinator.requestAccess(for: .camera)
        guard permissionStatus == .authorized else {
            errorMessage = "Allow Camera access in Settings to take a souvenir photo."
            return
        }

        isShowingCameraPicker = true
    }

    func importPhotoLibraryItem(_ item: PhotosPickerItem) async {
        await importPhoto {
            try await photoImporter.importPhotoLibraryItem(item)
        }
    }

    func importCameraCapture(_ capture: CameraCapture) async {
        await importPhoto {
            try await photoImporter.importCameraCapture(capture)
        }
    }

    func save() async -> Bool {
        guard let importedPhoto else {
            errorMessage = "Import one photo before saving."
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await souvenirRepository.createSouvenir(
                CreateSouvenirInput(
                    libraryContext: activeLibraryContext,
                    id: UUID(),
                    tripID: selectedTrip?.id,
                    title: title,
                    story: story,
                    acquiredOn: acquiredDate,
                    gotItInPlace: gotItInPlace,
                    fromPlace: fromPlace,
                    photos: [importedPhoto]
                )
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func importPhoto(
        _ operation: () async throws -> ImportedPhoto
    ) async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let photo = try await operation()
            importedPhoto = photo
            acquiredDate = photo.capturedAt
            await resolveSuggestedPlaceIfNeeded(for: photo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveSuggestedPlaceIfNeeded(for photo: ImportedPhoto) async {
        guard let location = photo.suggestedLocation else {
            return
        }

        isResolvingSuggestedPlace = true
        defer { isResolvingSuggestedPlace = false }
        gotItInPlace = await locationSuggester.suggestedPlace(for: location)
    }
}

@MainActor
final class CreateTripViewModel: ObservableObject {
    @Published var title = ""
    @Published var destinationSummary = ""
    @Published var hasStartDate = false
    @Published var startDate = Date()
    @Published var hasEndDate = false
    @Published var endDate = Date()
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let activeLibraryContext: ActiveLibraryContext
    private let tripRepository: any TripRepository

    init(
        activeLibraryContext: ActiveLibraryContext,
        tripRepository: any TripRepository
    ) {
        self.activeLibraryContext = activeLibraryContext
        self.tripRepository = tripRepository
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

    func save() async -> TripSelection? {
        errorMessage = nil
        if let validationMessage = TripFormLogic.validationMessage(
            title: title,
            hasStartDate: hasStartDate,
            startDate: startDate,
            hasEndDate: hasEndDate,
            endDate: endDate
        ) {
            errorMessage = validationMessage
            return nil
        }

        guard let normalizedTitle = TripPresentationLogic.normalizedText(title) else {
            errorMessage = "Trip title is required."
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let tripID = try await tripRepository.createTrip(
                CreateTripInput(
                    libraryContext: activeLibraryContext,
                    id: UUID(),
                    title: normalizedTitle,
                    destinationSummary: destinationSummary,
                    startDate: hasStartDate ? startDate : nil,
                    endDate: hasEndDate ? endDate : nil
                )
            )

            return TripSelection(
                id: tripID,
                title: normalizedTitle,
                subtitle: TripSelection.subtitle(
                    startDate: hasStartDate ? startDate : nil,
                    endDate: hasEndDate ? endDate : nil,
                    destinationSummary: TripPresentationLogic.destinationSummary(from: destinationSummary)
                )
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

@MainActor
final class PlaceSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [PlaceSearchResult] = []
    @Published var isSearching = false
    @Published var isResolvingCurrentLocation = false
    @Published var errorMessage: String?

    private let field: AddSouvenirPlaceField
    private let permissionCoordinator: any PermissionCoordinating
    private let locationSuggester: any LocationSuggesting

    init(
        field: AddSouvenirPlaceField,
        permissionCoordinator: any PermissionCoordinating,
        locationSuggester: any LocationSuggesting
    ) {
        self.field = field
        self.permissionCoordinator = permissionCoordinator
        self.locationSuggester = locationSuggester
    }

    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            guard trimmedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }

            let places = try await locationSuggester.searchPlaces(matching: trimmedQuery)
            results = places.map(PlaceSearchResult.init)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't search places right now."
            results = []
        }
    }

    func useCurrentLocation() async -> PlaceDraft? {
        guard field.supportsCurrentLocation else {
            return nil
        }

        errorMessage = nil
        let permissionStatus = await permissionCoordinator.requestAccess(for: .locationWhenInUse)
        guard permissionStatus == .authorized else {
            errorMessage = "Allow location access in Settings to use your current location."
            return nil
        }

        isResolvingCurrentLocation = true
        defer { isResolvingCurrentLocation = false }

        do {
            return try await locationSuggester.currentLocationPlace()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

enum AddSouvenirFormLogic {
    static func canSave(
        hasImportedPhoto: Bool,
        isBusy: Bool
    ) -> Bool {
        hasImportedPhoto && !isBusy
    }
}

enum TripFormLogic {
    static func validationMessage(
        title: String,
        hasStartDate: Bool,
        startDate: Date,
        hasEndDate: Bool,
        endDate: Date
    ) -> String? {
        guard TripPresentationLogic.normalizedText(title) != nil else {
            return "Trip title is required."
        }

        if hasStartDate,
           hasEndDate,
           endDate < startDate {
            return "End date can't be before the start date."
        }

        return nil
    }

    static func canSave(
        title: String,
        hasStartDate: Bool,
        startDate: Date,
        hasEndDate: Bool,
        endDate: Date,
        isSaving: Bool
    ) -> Bool {
        !isSaving && validationMessage(
            title: title,
            hasStartDate: hasStartDate,
            startDate: startDate,
            hasEndDate: hasEndDate,
            endDate: endDate
        ) == nil
    }
}

struct TripSelection: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?

    init(
        id: UUID,
        title: String,
        subtitle: String?
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }

    init?(trip: Trip) {
        guard let id = trip.id,
              let title = TripPresentationLogic.normalizedText(trip.title) else {
            return nil
        }

        self.id = id
        self.title = title
        self.subtitle = Self.subtitle(
            startDate: trip.startDate,
            endDate: trip.endDate,
            destinationSummary: TripPresentationLogic.destinationSummary(from: trip.destinationSummary)
        )
    }

    static func subtitle(
        startDate: Date?,
        endDate: Date?,
        destinationSummary: String?
    ) -> String? {
        if let dateRangeSummary = TripPresentationLogic.dateRangeSummary(
            startDate: startDate,
            endDate: endDate
        ) {
            return dateRangeSummary
        }

        return destinationSummary
    }
}

enum AddSouvenirPlaceField: String, Identifiable {
    case gotItIn
    case from

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gotItIn:
            "Got it in"
        case .from:
            "From"
        }
    }

    var supportsCurrentLocation: Bool {
        self == .gotItIn
    }
}

struct PlaceSearchResult: Identifiable, Equatable {
    let id: String
    let place: PlaceDraft

    init(_ place: PlaceDraft) {
        let latitude = place.latitude.map { String(format: "%.5f", $0) } ?? ""
        let longitude = place.longitude.map { String(format: "%.5f", $0) } ?? ""
        self.id = [place.displayTitle, place.displaySubtitle ?? "", latitude, longitude].joined(separator: "|")
        self.place = place
    }
}

private struct ImportedPhotoPreview: View {
    let imageData: Data

    var body: some View {
        Group {
            if let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.medium)
                    .background(AppTheme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                StateMessageView(
                    icon: "photo",
                    title: "Preview unavailable",
                    message: "The photo imported successfully, but the preview couldn't be rendered."
                )
            }
        }
    }
}

private struct FormValueRow: View {
    let label: String
    let value: String?
    let placeholder: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text(value ?? placeholder)
                .foregroundStyle(value == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .contentShape(Rectangle())
    }
}

private struct CameraCaptureSheet: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onCapture: (CameraCapture) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onCapture: onCapture)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCancel: () -> Void
        private let onCapture: (CameraCapture) -> Void

        init(
            onCancel: @escaping () -> Void,
            onCapture: @escaping (CameraCapture) -> Void
        ) {
            self.onCancel = onCancel
            self.onCapture = onCapture
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }

            let metadata = info[.mediaMetadata] as? [String: Any]
            onCapture(CameraCapture(image: image, metadata: metadata))
        }
    }
}
