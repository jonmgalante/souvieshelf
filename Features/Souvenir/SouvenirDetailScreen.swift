import CoreData
import PhotosUI
import SwiftUI
import UIKit

struct SouvenirDetailScreen: View {
    @Environment(\.dismiss) private var dismiss

    private let souvenirID: UUID
    private let activeLibraryContext: ActiveLibraryContext
    private let dependencies: AppDependencies
    private let onOpenRoute: (AppRoute) -> Void

    @FetchRequest private var souvenirs: FetchedResults<Souvenir>
    @State private var canEdit = false
    @State private var isShowingEditSheet = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    init(
        souvenirID: UUID,
        activeLibraryContext: ActiveLibraryContext,
        dependencies: AppDependencies,
        onOpenRoute: @escaping (AppRoute) -> Void
    ) {
        self.souvenirID = souvenirID
        self.activeLibraryContext = activeLibraryContext
        self.dependencies = dependencies
        self.onOpenRoute = onOpenRoute
        self._souvenirs = FetchRequest(
            fetchRequest: SouvenirDetailFetchRequestFactory.make(
                souvenirID: souvenirID,
                activeLibraryContext: activeLibraryContext,
                persistenceController: dependencies.persistenceController
            ),
            animation: .default
        )
    }

    private var souvenir: Souvenir? {
        souvenirs.first
    }

    var body: some View {
        Group {
            if let souvenir {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        SouvenirPhotoPager(photos: souvenir.detailSortedPhotos)

                        SurfaceCard {
                            Text(souvenir.detailScreenTitle)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)

                            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                                if let tripRow = souvenir.detailTripRow {
                                    if let tripID = tripRow.id {
                                        Button {
                                            onOpenRoute(.trip(tripID))
                                        } label: {
                                            DetailMetadataRow(
                                                label: "Trip",
                                                title: tripRow.title,
                                                subtitle: tripRow.subtitle,
                                                showsChevron: true
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Opens the trip.")
                                    } else {
                                        DetailMetadataRow(
                                            label: "Trip",
                                            title: tripRow.title,
                                            subtitle: tripRow.subtitle,
                                            showsChevron: false
                                        )
                                    }
                                }

                                if let gotItInPlace = souvenir.detailGotItInPlace {
                                    DetailMetadataRow(
                                        label: "Got it in",
                                        title: gotItInPlace.displayTitle,
                                        subtitle: gotItInPlace.displaySubtitle,
                                        showsChevron: false
                                    )
                                }

                                if let fromPlace = souvenir.detailFromPlace {
                                    DetailMetadataRow(
                                        label: "From",
                                        title: fromPlace.displayTitle,
                                        subtitle: fromPlace.displaySubtitle,
                                        showsChevron: false
                                    )
                                }

                                if let acquiredDate = souvenir.acquiredDate {
                                    DetailMetadataRow(
                                        label: "Date",
                                        title: acquiredDate.formatted(date: .long, time: .omitted),
                                        subtitle: nil,
                                        showsChevron: false
                                    )
                                }
                            }
                        }

                        if let story = souvenir.detailStory {
                            SurfaceCard {
                                Text("Story")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text(story)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                        }

                        if canEdit {
                            Button(role: .destructive) {
                                isShowingDeleteConfirmation = true
                            } label: {
                                if isDeleting {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Delete Souvenir")
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
                        icon: "shippingbox",
                        title: "Souvenir Unavailable",
                        message: "This souvenir may have been deleted or is still syncing in the active library."
                    )
                    .padding(AppSpacing.large)
                }
            }
        }
        .navigationTitle(souvenir?.detailScreenTitle ?? "Souvenir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, souvenir != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        isShowingEditSheet = true
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .task(id: editabilityTaskKey) {
            canEdit = await dependencies.souvenirRepository.canEditSouvenir(
                id: souvenirID,
                libraryContext: activeLibraryContext
            )
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if let snapshot = souvenir.flatMap(SouvenirEditSnapshot.init) {
                EditSouvenirSheet(
                    snapshot: snapshot,
                    activeLibraryContext: activeLibraryContext,
                    dependencies: dependencies
                )
            }
        }
        .confirmationDialog(
            "Delete this souvenir?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Souvenir", role: .destructive) {
                Task {
                    await softDelete()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will move to Recently Deleted and disappear from the Library, Map, and trip views until you restore it.")
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
            souvenirID.uuidString,
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
            try await dependencies.souvenirRepository.softDeleteSouvenir(
                id: souvenirID,
                libraryContext: activeLibraryContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EditSouvenirSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: EditSouvenirViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var activePlaceField: AddSouvenirPlaceField?
    @State private var isShowingTripPicker = false

    private let persistenceController: PersistenceController
    private let tripRepository: any TripRepository
    private let permissionCoordinator: any PermissionCoordinating
    private let locationSuggester: any LocationSuggesting

    init(
        snapshot: SouvenirEditSnapshot,
        activeLibraryContext: ActiveLibraryContext,
        dependencies: AppDependencies
    ) {
        self.persistenceController = dependencies.persistenceController
        self.tripRepository = dependencies.tripRepository
        self.permissionCoordinator = dependencies.permissionCoordinator
        self.locationSuggester = dependencies.locationSuggester
        self._viewModel = StateObject(
            wrappedValue: EditSouvenirViewModel(
                snapshot: snapshot,
                activeLibraryContext: activeLibraryContext,
                souvenirRepository: dependencies.souvenirRepository,
                permissionCoordinator: dependencies.permissionCoordinator,
                photoImporter: dependencies.photoImporter
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: AppSpacing.medium) {
                            ForEach(viewModel.photos) { photo in
                                EditablePhotoTile(
                                    photo: photo,
                                    onRemove: {
                                        viewModel.removePhoto(id: photo.id)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, AppSpacing.xSmall)
                    }

                    Button {
                        Task {
                            await viewModel.beginPhotoLibraryImport()
                        }
                    } label: {
                        Label("Add Photo", systemImage: "plus")
                    }
                    .disabled(viewModel.isBusy)

                    Text("Keep at least one photo. If the current cover photo is removed, the next remaining photo becomes primary.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)

                    if viewModel.isImporting {
                        HStack(spacing: AppSpacing.small) {
                            ProgressView()
                            Text("Importing photo...")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .appGroupedRowChrome()

                Section("Details") {
                    TextField("Title", text: $viewModel.title)
                        .disabled(viewModel.isSaving)

                    Button {
                        isShowingTripPicker = true
                    } label: {
                        EditFormValueRow(
                            label: "Trip",
                            value: viewModel.selectedTrip?.title,
                            placeholder: "Optional"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSaving)

                    Button {
                        activePlaceField = .gotItIn
                    } label: {
                        EditFormValueRow(
                            label: "Got it in",
                            value: viewModel.gotItInPlace?.displayTitle,
                            placeholder: "Optional"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSaving)

                    Button {
                        activePlaceField = .from
                    } label: {
                        EditFormValueRow(
                            label: "From",
                            value: viewModel.fromPlace?.displayTitle,
                            placeholder: "Optional"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSaving)
                }
                .appGroupedRowChrome()

                Section("Date") {
                    if viewModel.acquiredDate == nil {
                        Button("Add Date") {
                            viewModel.acquiredDate = .now
                        }
                        .disabled(viewModel.isSaving)
                    } else {
                        DatePicker(
                            "Acquired on",
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

                Section("Story") {
                    TextField("Story", text: $viewModel.story, axis: .vertical)
                        .lineLimit(5, reservesSpace: true)
                        .disabled(viewModel.isSaving)
                }
                .appGroupedRowChrome()
            }
            .appGroupedScreenChrome()
            .navigationTitle("Edit Souvenir")
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
        .sheet(isPresented: $isShowingTripPicker) {
            TripPickerSheet(
                activeLibraryContext: viewModel.activeLibraryContext,
                persistenceController: persistenceController,
                tripRepository: tripRepository,
                selectedTrip: viewModel.selectedTrip,
                onSelect: { selection in
                    viewModel.selectedTrip = selection
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
                onSelect: { place in
                    switch field {
                    case .gotItIn:
                        viewModel.gotItInPlace = place
                    case .from:
                        viewModel.fromPlace = place
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

    private var acquiredDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.acquiredDate ?? .now },
            set: { viewModel.acquiredDate = $0 }
        )
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
}

@MainActor
final class EditSouvenirViewModel: ObservableObject {
    let activeLibraryContext: ActiveLibraryContext

    @Published var title: String
    @Published var story: String
    @Published var acquiredDate: Date?
    @Published var selectedTrip: TripSelection?
    @Published var gotItInPlace: PlaceDraft?
    @Published var fromPlace: PlaceDraft?
    @Published var photos: [EditableSouvenirPhoto]
    @Published var isShowingPhotoLibraryPicker = false
    @Published var isImporting = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let souvenirID: UUID
    private let souvenirRepository: any SouvenirRepository
    private let permissionCoordinator: any PermissionCoordinating
    private let photoImporter: any PhotoImporting

    init(
        snapshot: SouvenirEditSnapshot,
        activeLibraryContext: ActiveLibraryContext,
        souvenirRepository: any SouvenirRepository,
        permissionCoordinator: any PermissionCoordinating,
        photoImporter: any PhotoImporting
    ) {
        self.activeLibraryContext = activeLibraryContext
        self.souvenirID = snapshot.souvenirID
        self.souvenirRepository = souvenirRepository
        self.permissionCoordinator = permissionCoordinator
        self.photoImporter = photoImporter
        self.title = snapshot.title
        self.story = snapshot.story
        self.acquiredDate = snapshot.acquiredDate
        self.selectedTrip = snapshot.selectedTrip
        self.gotItInPlace = snapshot.gotItInPlace
        self.fromPlace = snapshot.fromPlace
        self.photos = SouvenirPhotoEditLogic.normalized(snapshot.photos)
    }

    var isBusy: Bool {
        isImporting || isSaving
    }

    var canSave: Bool {
        !photos.isEmpty && !isBusy
    }

    func beginPhotoLibraryImport() async {
        errorMessage = nil
        let permissionStatus = await permissionCoordinator.requestAccess(for: .photoLibrary)
        guard permissionStatus == .authorized else {
            errorMessage = "Allow Photo Library access in Settings to add souvenir photos."
            return
        }

        isShowingPhotoLibraryPicker = true
    }

    func importPhotoLibraryItem(_ item: PhotosPickerItem) async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let importedPhoto = try await photoImporter.importPhotoLibraryItem(item)
            photos = SouvenirPhotoEditLogic.appending(importedPhoto, to: photos)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePhoto(id: UUID) {
        do {
            photos = try SouvenirPhotoEditLogic.removingPhoto(withID: id, from: photos)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async -> Bool {
        guard let primaryPhotoID = photos.first(where: \.isPrimary)?.id ?? photos.first?.id else {
            errorMessage = "Keep at least one photo on this souvenir."
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await souvenirRepository.updateSouvenir(
                UpdateSouvenirInput(
                    libraryContext: activeLibraryContext,
                    souvenirID: souvenirID,
                    tripID: selectedTrip?.id,
                    title: title,
                    story: story,
                    acquiredOn: acquiredDate,
                    gotItInPlace: gotItInPlace,
                    fromPlace: fromPlace,
                    photoOrder: photos.map(\.id),
                    addedPhotos: photos.compactMap(\.importedPhoto),
                    primaryPhotoID: primaryPhotoID
                )
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct SouvenirEditSnapshot: Equatable, Sendable {
    var souvenirID: UUID
    var title: String
    var story: String
    var acquiredDate: Date?
    var selectedTrip: TripSelection?
    var gotItInPlace: PlaceDraft?
    var fromPlace: PlaceDraft?
    var photos: [EditableSouvenirPhoto]

    init?(souvenir: Souvenir) {
        guard let souvenirID = souvenir.id else {
            return nil
        }

        self.souvenirID = souvenirID
        self.title = souvenir.title ?? ""
        self.story = souvenir.story ?? ""
        self.acquiredDate = souvenir.acquiredDate
        self.selectedTrip = souvenir.detailTripSelection
        self.gotItInPlace = souvenir.detailGotItInPlace
        self.fromPlace = souvenir.detailFromPlace
        self.photos = souvenir.detailSortedPhotos.compactMap(EditableSouvenirPhoto.init)

        guard !photos.isEmpty else {
            return nil
        }
    }
}

struct EditableSouvenirPhoto: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case existing
        case imported(ImportedPhoto)
    }

    let id: UUID
    let displayImageData: Data
    let thumbnailData: Data
    var isPrimary: Bool
    let source: Source

    init?(photoAsset: PhotoAsset) {
        guard let id = photoAsset.id else {
            return nil
        }

        self.id = id
        self.displayImageData = photoAsset.displayImageData ?? Data()
        self.thumbnailData = photoAsset.thumbnailData ?? Data()
        self.isPrimary = photoAsset.isPrimary
        self.source = .existing
    }

    init(importedPhoto: ImportedPhoto, isPrimary: Bool) {
        self.id = importedPhoto.id
        self.displayImageData = importedPhoto.displayImageData
        self.thumbnailData = importedPhoto.thumbnailData
        self.isPrimary = isPrimary
        self.source = .imported(importedPhoto)
    }

    var importedPhoto: ImportedPhoto? {
        guard case .imported(let photo) = source else {
            return nil
        }

        return photo
    }
}

enum SouvenirPhotoEditLogic {
    static func normalized(_ photos: [EditableSouvenirPhoto]) -> [EditableSouvenirPhoto] {
        guard !photos.isEmpty else {
            return []
        }

        let primaryID = photos.first(where: \.isPrimary)?.id ?? photos.first?.id
        return photos.map { photo in
            var photo = photo
            photo.isPrimary = photo.id == primaryID
            return photo
        }
    }

    static func appending(
        _ importedPhoto: ImportedPhoto,
        to photos: [EditableSouvenirPhoto]
    ) -> [EditableSouvenirPhoto] {
        normalized(
            photos + [
                EditableSouvenirPhoto(
                    importedPhoto: importedPhoto,
                    isPrimary: photos.isEmpty
                )
            ]
        )
    }

    static func removingPhoto(
        withID id: UUID,
        from photos: [EditableSouvenirPhoto]
    ) throws -> [EditableSouvenirPhoto] {
        let remainingPhotos = photos.filter { $0.id != id }
        guard !remainingPhotos.isEmpty else {
            throw SouvenirPhotoEditError.lastPhotoRequired
        }

        return normalized(remainingPhotos)
    }
}

enum SouvenirPhotoEditError: LocalizedError, Equatable {
    case lastPhotoRequired

    var errorDescription: String? {
        switch self {
        case .lastPhotoRequired:
            "Keep at least one photo on every souvenir."
        }
    }
}

private enum SouvenirDetailFetchRequestFactory {
    static func make(
        souvenirID: UUID,
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) -> NSFetchRequest<Souvenir> {
        let request = Souvenir.fetchRequest()
        request.fetchLimit = 1
        request.relationshipKeyPathsForPrefetching = ["photos", "trip"]
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", souvenirID as CVarArg),
                NSPredicate(format: "library.id == %@", activeLibraryContext.libraryID as CVarArg),
                NSPredicate(format: "deletedAt == NIL")
            ]
        )

        guard let store = try? persistenceController.persistentStore(for: activeLibraryContext.storeScope) else {
            request.predicate = NSCompoundPredicate(
                andPredicateWithSubpredicates: [
                    request.predicate ?? NSPredicate(value: true),
                    NSPredicate(value: false)
                ]
            )
            return request
        }

        request.affectedStores = [store]
        return request
    }
}

private struct DetailMetadataRow: View {
    let label: String
    let title: String
    let subtitle: String?
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                Text(title)
                    .foregroundStyle(AppTheme.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: AppSpacing.small)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textMuted)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct EditFormValueRow: View {
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

private struct SouvenirPhotoPager: View {
    let photos: [PhotoAsset]

    var body: some View {
        if photos.isEmpty {
            StateMessageView(
                icon: "photo",
                title: "Photo unavailable",
                message: "This souvenir doesn't have a renderable photo right now."
            )
        } else if photos.count == 1, let photo = photos.first {
            DetailPhotoPage(photoData: photo.displayImageData)
        } else {
            TabView {
                ForEach(photos, id: \.objectID) { photo in
                    DetailPhotoPage(photoData: photo.displayImageData)
                }
            }
            .frame(height: 320)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
    }
}

private struct DetailPhotoPage: View {
    let photoData: Data?

    var body: some View {
        Group {
            if let photoData,
               let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 320)
                    .padding(AppSpacing.medium)
                    .background(AppTheme.placeholderSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.placeholderSurface)
                    .frame(height: 260)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
            }
        }
    }
}

private struct EditablePhotoTile: View {
    let photo: EditableSouvenirPhoto
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            ZStack(alignment: .topTrailing) {
                EditablePhotoThumbnail(photoData: photo.thumbnailData.isEmpty ? photo.displayImageData : photo.thumbnailData)
                    .frame(width: 120, height: 120)

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            AppTheme.textOnEmphasis,
                            AppTheme.surfaceEmphasis.opacity(0.88)
                        )
                }
                .padding(AppSpacing.xSmall)
                .accessibilityLabel("Remove photo")
                .accessibilityHint("Removes this photo from the souvenir.")
            }

            Text(photo.isPrimary ? "Primary photo" : "Additional photo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(photo.isPrimary ? AppTheme.accentPrimary : AppTheme.textSecondary)
        }
    }
}

private struct EditablePhotoThumbnail: View {
    let photoData: Data

    var body: some View {
        Group {
            if let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.placeholderSurface)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private extension Souvenir {
    var detailScreenTitle: String {
        Self.normalizedDisplayValue(title) ?? "Untitled souvenir"
    }

    var detailStory: String? {
        Self.normalizedDisplayValue(story)
    }

    var detailTripSelection: TripSelection? {
        guard let trip,
              trip.deletedAt == nil else {
            return nil
        }

        return TripSelection(trip: trip)
    }

    var detailTripRow: DetailTripRow? {
        guard let tripSelection = detailTripSelection else {
            return nil
        }

        return DetailTripRow(
            id: tripSelection.id,
            title: tripSelection.title,
            subtitle: tripSelection.subtitle
        )
    }

    var detailGotItInPlace: PlaceDraft? {
        Self.placeDraft(
            title: gotItInName,
            locality: gotItInCity,
            country: gotItInCountryCode,
            latitude: gotItInLatitude,
            longitude: gotItInLongitude
        )
    }

    var detailFromPlace: PlaceDraft? {
        Self.placeDraft(
            title: fromName,
            locality: fromCity,
            country: fromCountryCode,
            latitude: fromLatitude,
            longitude: fromLongitude
        )
    }

    var detailSortedPhotos: [PhotoAsset] {
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

    private static func normalizedDisplayValue(_ value: String?) -> String? {
        let collapsed = value?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed?.isEmpty == false ? collapsed : nil
    }

    private static func placeDraft(
        title: String?,
        locality: String?,
        country: String?,
        latitude: Double,
        longitude: Double
    ) -> PlaceDraft? {
        let resolvedTitle = normalizedDisplayValue(title)
        let resolvedLocality = normalizedDisplayValue(locality)
        let resolvedCountry = normalizedDisplayValue(country)
        let hasCoordinate = latitude != 0 || longitude != 0

        guard resolvedTitle != nil || resolvedLocality != nil || resolvedCountry != nil || hasCoordinate else {
            return nil
        }

        return PlaceDraft(
            title: resolvedTitle ?? resolvedLocality ?? resolvedCountry ?? "Unnamed place",
            locality: resolvedLocality,
            country: resolvedCountry,
            latitude: hasCoordinate ? latitude : nil,
            longitude: hasCoordinate ? longitude : nil
        )
    }
}

private struct DetailTripRow {
    let id: UUID?
    let title: String
    let subtitle: String?
}
