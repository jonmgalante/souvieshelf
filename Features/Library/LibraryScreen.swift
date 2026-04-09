import CoreData
import SwiftUI
import UIKit

struct LibraryScreen: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var store: AppStore
    @State private var selectedSegment: LibrarySegment = .items

    var body: some View {
        Group {
            if let activeLibraryContext = store.activeLibraryContext {
                LibraryHomeContent(
                    activeLibraryContext: activeLibraryContext,
                    persistenceController: environment.dependencies.persistenceController,
                    selectedSegment: $selectedSegment,
                    shareSummary: activeLibraryContext.shareSummary,
                    onPartnerSettingsTapped: {
                        store.open(.settings)
                    },
                    onOpen: { route in
                        store.open(route)
                    }
                )
            } else {
                ScrollView {
                    StateMessageView(
                        icon: "books.vertical.fill",
                        title: "Our Library Is Loading",
                        message: "SouvieShelf is still resolving the active library before showing your saved items, trips, and places."
                    )
                    .padding(AppSpacing.large)
                }
            }
        }
        .navigationTitle(store.activeLibraryContext?.libraryTitle ?? "Our Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.open(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }
}

private struct LibraryHomeContent: View {
    let activeLibraryContext: ActiveLibraryContext
    let shareSummary: ShareSummary?
    let onPartnerSettingsTapped: () -> Void
    let onOpen: (AppRoute) -> Void

    @Binding private var selectedSegment: LibrarySegment
    @FetchRequest private var souvenirs: FetchedResults<Souvenir>
    @FetchRequest private var trips: FetchedResults<Trip>

    init(
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController,
        selectedSegment: Binding<LibrarySegment>,
        shareSummary: ShareSummary?,
        onPartnerSettingsTapped: @escaping () -> Void,
        onOpen: @escaping (AppRoute) -> Void
    ) {
        self.activeLibraryContext = activeLibraryContext
        self.shareSummary = shareSummary
        self.onPartnerSettingsTapped = onPartnerSettingsTapped
        self.onOpen = onOpen
        self._selectedSegment = selectedSegment
        self._souvenirs = FetchRequest(
            fetchRequest: LibraryFetchRequestFactory.souvenirs(
                for: activeLibraryContext,
                persistenceController: persistenceController
            ),
            animation: .default
        )
        self._trips = FetchRequest(
            fetchRequest: LibraryFetchRequestFactory.trips(
                for: activeLibraryContext,
                persistenceController: persistenceController
            ),
            animation: .default
        )
    }

    private var ownerShareBannerState: LibraryOwnerShareBannerState? {
        guard activeLibraryContext.isOwner else {
            return nil
        }

        let partnerState = shareSummary?.partnerState ?? activeLibraryContext.partnerState
        switch partnerState {
        case .none:
            return .invitePartner
        case .inviteSent:
            return .invitePending
        case .connected:
            return nil
        }
    }

    private var activeSouvenirs: [Souvenir] {
        Array(souvenirs)
    }

    private var activeTrips: [Trip] {
        Array(trips)
    }

    private var tripMetricsByID: [UUID: LibraryTripMetrics] {
        var metrics: [UUID: LibraryTripMetrics] = [:]

        for souvenir in activeSouvenirs {
            guard let trip = souvenir.trip,
                  trip.deletedAt == nil,
                  let tripID = trip.id else {
                continue
            }

            var summary = metrics[tripID] ?? LibraryTripMetrics(
                souvenirCount: 0,
                coverThumbnailData: nil
            )
            summary.souvenirCount += 1

            if summary.coverThumbnailData == nil {
                summary.coverThumbnailData = souvenir.primaryThumbnailData
            }

            metrics[tripID] = summary
        }

        return metrics
    }

    private var placeGroups: [PlaceGroup] {
        PlacePresentationLogic.groups(
            from: activeSouvenirs.compactMap(\.placeCandidate)
        )
    }

    private func tripMetrics(for trip: Trip) -> LibraryTripMetrics {
        guard let tripID = trip.id else {
            return .empty
        }

        return tripMetricsByID[tripID] ?? .empty
    }

    private var isLibraryEmpty: Bool {
        activeSouvenirs.isEmpty && activeTrips.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                LibrarySummaryCard(
                    activeLibraryContext: activeLibraryContext,
                    shareSummary: shareSummary
                )

                if let ownerShareBannerState {
                    LibraryInviteBanner(
                        state: ownerShareBannerState,
                        action: onPartnerSettingsTapped
                    )
                }

                Picker("Library Segment", selection: $selectedSegment) {
                    ForEach(LibrarySegment.allCases, id: \.self) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(AppSpacing.xSmall)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.surfacePrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.borderSubtle, lineWidth: 1)
                )
                .tint(AppTheme.accentPrimary)
                .accessibilityLabel("Library sections")

                content
            }
            .padding(AppSpacing.large)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLibraryEmpty {
            LibraryEmptyStateView(
                icon: "shippingbox.circle.fill",
                title: "Your library starts here",
                message: "Use Add in the center of the tab bar when you're ready to save your first souvenir or trip together."
            )
        } else {
            switch selectedSegment {
            case .items:
                itemsContent
            case .trips:
                tripsContent
            case .places:
                placesContent
            }
        }
    }

    @ViewBuilder
    private var itemsContent: some View {
        if activeSouvenirs.isEmpty {
            LibraryEmptyStateView(
                icon: "shippingbox.fill",
                title: "No items yet",
                message: "Souvenirs will land here as soon as you start adding keepsakes to Our Library."
            )
        } else {
            LazyVStack(spacing: AppSpacing.medium) {
                ForEach(activeSouvenirs, id: \.objectID) { souvenir in
                    if let souvenirID = souvenir.id {
                        Button {
                            onOpen(.souvenir(souvenirID))
                        } label: {
                            SouvenirRowCard(souvenir: souvenir)
                        }
                        .buttonStyle(.plain)
                    } else {
                        SouvenirRowCard(souvenir: souvenir)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tripsContent: some View {
        if activeTrips.isEmpty {
            LibraryEmptyStateView(
                icon: "suitcase.rolling.fill",
                title: "No trips yet",
                message: "Create a trip to keep souvenirs from the same journey together."
            )
        } else {
            LazyVStack(spacing: AppSpacing.medium) {
                ForEach(activeTrips, id: \.objectID) { trip in
                    if let tripID = trip.id {
                        Button {
                            onOpen(.trip(tripID))
                        } label: {
                            TripRowCard(
                                trip: trip,
                                souvenirCount: tripMetrics(for: trip).souvenirCount,
                                coverThumbnailData: tripMetrics(for: trip).coverThumbnailData
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        TripRowCard(
                            trip: trip,
                            souvenirCount: tripMetrics(for: trip).souvenirCount,
                            coverThumbnailData: tripMetrics(for: trip).coverThumbnailData
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var placesContent: some View {
        if placeGroups.isEmpty {
            LibraryEmptyStateView(
                icon: "mappin.and.ellipse",
                title: "No places yet",
                message: "Places appear automatically from each souvenir's \"Got it in\" location."
            )
        } else {
            LazyVStack(spacing: AppSpacing.medium) {
                ForEach(placeGroups) { placeGroup in
                    Button {
                        onOpen(.place(placeGroup.key))
                    } label: {
                        PlaceRowCard(placeGroup: placeGroup)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PlaceDetailScreen: View {
    private let placeKey: PlaceKey
    private let onOpenRoute: (AppRoute) -> Void
    private let onViewOnMap: () -> Void

    @FetchRequest private var souvenirs: FetchedResults<Souvenir>

    init(
        placeKey: PlaceKey,
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController,
        onOpenRoute: @escaping (AppRoute) -> Void,
        onViewOnMap: @escaping () -> Void
    ) {
        self.placeKey = placeKey
        self.onOpenRoute = onOpenRoute
        self.onViewOnMap = onViewOnMap
        self._souvenirs = FetchRequest(
            fetchRequest: PlaceDetailFetchRequestFactory.souvenirs(
                for: activeLibraryContext,
                persistenceController: persistenceController
            ),
            animation: .default
        )
    }

    private var matchingSouvenirs: [Souvenir] {
        souvenirs.filter { $0.matches(placeKey: placeKey) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                PlaceDetailSummaryCard(
                    placeKey: placeKey,
                    souvenirCount: matchingSouvenirs.count,
                    onViewOnMap: onViewOnMap
                )

                PlaceDetailSouvenirsCard(
                    souvenirs: matchingSouvenirs,
                    onOpenRoute: onOpenRoute
                )
            }
            .padding(AppSpacing.large)
        }
        .navigationTitle(placeKey.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LibrarySummaryCard: View {
    let activeLibraryContext: ActiveLibraryContext
    let shareSummary: ShareSummary?

    private var partnerState: PartnerConnectionState {
        shareSummary?.partnerState ?? activeLibraryContext.partnerState
    }

    private var title: String {
        switch partnerState {
        case .none:
            return "Private for now"
        case .inviteSent:
            return "Invite pending"
        case .connected(let displayName):
            if activeLibraryContext.isOwner {
                if let displayName {
                    return "Shared with \(displayName)"
                }

                return "Shared with your partner"
            }

            if let ownerDisplayName = shareSummary?.ownerDisplayName ?? displayName {
                return "Shared by \(ownerDisplayName)"
            }

            return "Shared with you"
        }
    }

    private var message: String {
        switch partnerState {
        case .none:
            return "Only you can see this library until you send an invite."
        case .inviteSent:
            return "Your partner can accept from Apple's native share invite on their iPhone."
        case .connected:
            return activeLibraryContext.isOwner
                ? "Everything you save here stays in your shared couple library."
                : "You're looking at the active shared library from your partner's invite."
        }
    }

    var body: some View {
        SurfaceCard {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryInviteBanner: View {
    let state: LibraryOwnerShareBannerState
    let action: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                Image(systemName: state.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.backgroundPrimary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.borderSubtle, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(state.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(state.message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: AppSpacing.small)

                Button(action: action) {
                    Text(state.actionTitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentPrimary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SouvenirRowCard: View {
    let souvenir: Souvenir

    var body: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                LibraryThumbnail(
                    data: souvenir.primaryThumbnailData,
                    placeholderSystemImage: "shippingbox.fill"
                )

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(souvenir.displayTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    if let tripTitle = souvenir.visibleTripTitle {
                        LibraryMetadataLabel(
                            systemImage: "suitcase.rolling.fill",
                            text: tripTitle
                        )
                    }

                    if let placeSummary = souvenir.gotItInSummary {
                        LibraryMetadataLabel(
                            systemImage: "mappin.and.ellipse",
                            text: placeSummary
                        )
                    }

                    if let dateSummary = souvenir.acquiredOrUpdatedSummary {
                        LibraryMetadataLabel(
                            systemImage: "calendar",
                            text: dateSummary
                        )
                    }
                }

                Spacer(minLength: AppSpacing.small)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textMuted)
                    .padding(.top, AppSpacing.xSmall)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TripRowCard: View {
    let trip: Trip
    let souvenirCount: Int
    let coverThumbnailData: Data?

    var body: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                LibraryThumbnail(
                    data: coverThumbnailData,
                    placeholderSystemImage: "suitcase.rolling.fill"
                )

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(trip.displayTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    if let dateRangeSummary = trip.dateRangeSummary {
                        LibraryMetadataLabel(
                            systemImage: "calendar",
                            text: dateRangeSummary
                        )
                    }

                    LibraryMetadataLabel(
                        systemImage: "shippingbox.fill",
                        text: "\(souvenirCount) \(souvenirCount == 1 ? "souvenir" : "souvenirs")"
                    )
                }

                Spacer(minLength: AppSpacing.small)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textMuted)
                    .padding(.top, AppSpacing.xSmall)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlaceRowCard: View {
    let placeGroup: PlaceGroup

    var body: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                LibraryThumbnail(
                    data: placeGroup.thumbnailData,
                    placeholderSystemImage: "mappin.and.ellipse"
                )

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(placeGroup.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    LibraryMetadataLabel(
                        systemImage: "shippingbox.fill",
                        text: "\(placeGroup.souvenirCount) \(placeGroup.souvenirCount == 1 ? "souvenir" : "souvenirs")"
                    )
                }

                Spacer(minLength: AppSpacing.small)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textMuted)
                    .padding(.top, AppSpacing.xSmall)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlaceDetailSummaryCard: View {
    let placeKey: PlaceKey
    let souvenirCount: Int
    let onViewOnMap: () -> Void

    var body: some View {
        SurfaceCard {
            Text(placeKey.label)
                .font(.title2.weight(.semibold))

            LibraryMetadataLabel(
                systemImage: "shippingbox.fill",
                text: "\(souvenirCount) \(souvenirCount == 1 ? "souvenir" : "souvenirs")"
            )

            Button(action: onViewOnMap) {
                Label("View on Map", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(souvenirCount == 0)
            .accessibilityLabel("View \(placeKey.label) on Map")
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PlaceDetailSouvenirsCard: View {
    let souvenirs: [Souvenir]
    let onOpenRoute: (AppRoute) -> Void

    var body: some View {
        SurfaceCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Souvenirs")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text("\(souvenirs.count) \(souvenirs.count == 1 ? "souvenir" : "souvenirs")")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if souvenirs.isEmpty {
                Text("This place doesn't have any active souvenirs in the current library right now.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(spacing: AppSpacing.medium) {
                    ForEach(Array(souvenirs.enumerated()), id: \.element.objectID) { index, souvenir in
                        if let souvenirID = souvenir.id {
                            Button {
                                onOpenRoute(.souvenir(souvenirID))
                            } label: {
                                PlaceDetailSouvenirRow(
                                    souvenir: souvenir,
                                    showsChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            PlaceDetailSouvenirRow(
                                souvenir: souvenir,
                                showsChevron: false
                            )
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

private struct PlaceDetailSouvenirRow: View {
    let souvenir: Souvenir
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            LibraryThumbnail(
                data: souvenir.primaryThumbnailData,
                placeholderSystemImage: "shippingbox.fill"
            )

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(souvenir.displayTitle)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                if let tripTitle = souvenir.visibleTripTitle {
                    LibraryMetadataLabel(
                        systemImage: "suitcase.rolling.fill",
                        text: tripTitle
                    )
                }

                if let dateSummary = souvenir.acquiredOrUpdatedSummary {
                    LibraryMetadataLabel(
                        systemImage: "calendar",
                        text: dateSummary
                    )
                }
            }

            Spacer(minLength: AppSpacing.small)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textMuted)
                    .padding(.top, AppSpacing.xSmall)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryThumbnail: View {
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
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LibraryMetadataLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .labelStyle(.titleAndIcon)
    }
}

private struct LibraryEmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        StateMessageView(
            icon: icon,
            title: title,
            message: message
        )
    }
}

private enum LibraryOwnerShareBannerState {
    case invitePartner
    case invitePending

    var title: String {
        switch self {
        case .invitePartner:
            return "Invite your partner"
        case .invitePending:
            return "Invite still pending"
        }
    }

    var message: String {
        switch self {
        case .invitePartner:
            return "Open Settings to invite your partner with Apple's native sharing flow."
        case .invitePending:
            return "Open Settings to resend or manage the existing partner invite."
        }
    }

    var actionTitle: String {
        switch self {
        case .invitePartner:
            return "Invite Partner"
        case .invitePending:
            return "Manage Partner"
        }
    }

    var symbolName: String {
        switch self {
        case .invitePartner:
            return "person.badge.plus"
        case .invitePending:
            return "paperplane"
        }
    }
}

private struct LibraryTripMetrics {
    var souvenirCount: Int
    var coverThumbnailData: Data?

    static let empty = LibraryTripMetrics(souvenirCount: 0, coverThumbnailData: nil)
}

private enum LibraryFetchRequestFactory {
    static func souvenirs(
        for activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) -> NSFetchRequest<Souvenir> {
        let request = Souvenir.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.predicate = NSPredicate(
            format: "library.id == %@ AND deletedAt == NIL",
            activeLibraryContext.libraryID as CVarArg
        )
        applyStoreScope(
            to: request,
            activeLibraryContext: activeLibraryContext,
            persistenceController: persistenceController
        )
        return request
    }

    static func trips(
        for activeLibraryContext: ActiveLibraryContext,
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
            // Fail closed if the store cannot be resolved so the Library never mixes private and shared data.
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

private enum PlaceDetailFetchRequestFactory {
    static func souvenirs(
        for activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController
    ) -> NSFetchRequest<Souvenir> {
        let request = LibraryFetchRequestFactory.souvenirs(
            for: activeLibraryContext,
            persistenceController: persistenceController
        )
        request.relationshipKeyPathsForPrefetching = ["photos", "trip"]
        return request
    }
}

private extension Souvenir {
    var displayTitle: String {
        title.normalizedDisplayValue ?? "Untitled souvenir"
    }

    var visibleTripTitle: String? {
        guard let trip,
              trip.deletedAt == nil else {
            return nil
        }

        return trip.title.normalizedDisplayValue
    }

    var gotItInSummary: String? {
        PlacePresentationLogic.displayTitle(
            name: gotItInName,
            city: gotItInCity,
            country: gotItInCountryCode
        )
    }

    var acquiredOrUpdatedSummary: String? {
        if let acquiredDate {
            return "Got it \(acquiredDate.formatted(date: .abbreviated, time: .omitted))"
        }

        if let updatedAt {
            return "Updated \(updatedAt.formatted(date: .abbreviated, time: .omitted))"
        }

        return nil
    }

    var primaryThumbnailData: Data? {
        sortedPhotoAssets.first(where: { $0.thumbnailData != nil })?.thumbnailData
            ?? sortedPhotoAssets.first(where: { $0.displayImageData != nil })?.displayImageData
    }

    var placeCandidate: PlaceCandidate? {
        let coordinate = resolvedCoordinate(latitude: gotItInLatitude, longitude: gotItInLongitude)
        guard PlacePresentationLogic.placeKey(
            name: gotItInName,
            city: gotItInCity,
            country: gotItInCountryCode,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude
        ) != nil else {
            return nil
        }

        return PlaceCandidate(
            name: gotItInName.normalizedDisplayValue,
            city: gotItInCity.normalizedDisplayValue,
            country: gotItInCountryCode.normalizedDisplayValue,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            thumbnailData: primaryThumbnailData
        )
    }

    func matches(placeKey: PlaceKey) -> Bool {
        PlacePresentationLogic.matches(
            placeKey: placeKey,
            name: gotItInName,
            city: gotItInCity,
            country: gotItInCountryCode
        )
    }

    private var sortedPhotoAssets: [PhotoAsset] {
        let photoAssets = (photos as? Set<PhotoAsset>) ?? []
        return photoAssets.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary && !rhs.isPrimary
            }

            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
        }
    }

    private func resolvedCoordinate(
        latitude: Double,
        longitude: Double
    ) -> (latitude: Double, longitude: Double)? {
        guard latitude != 0 || longitude != 0 else {
            return nil
        }

        return (latitude, longitude)
    }
}

private extension Trip {
    var displayTitle: String {
        TripPresentationLogic.displayTitle(from: title)
    }

    var dateRangeSummary: String? {
        TripPresentationLogic.dateRangeSummary(
            startDate: startDate,
            endDate: endDate
        )
    }
}

private extension String {
    var normalizedForDisplay: String? {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

private extension Optional where Wrapped == String {
    var normalizedDisplayValue: String? {
        self?.normalizedForDisplay
    }
}

struct LibraryScreen_Previews: PreviewProvider {
    static var previews: some View {
        let environment = AppEnvironment.preview(.ready)
        return LibraryScreen(store: environment.appStore)
            .environmentObject(environment)
    }
}
