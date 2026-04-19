import CoreData
import SwiftUI
import UIKit

struct LibraryScreen: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var store: AppStore
    @State private var selectedQuickAccess: LibraryQuickAccessSelection = .allItems
    @State private var selectedItemFilter: LibraryItemFilter = .none
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        Group {
            if let activeLibraryContext = store.activeLibraryContext {
                LibraryHomeContent(
                    activeLibraryContext: activeLibraryContext,
                    persistenceController: environment.dependencies.persistenceController,
                    selectedQuickAccess: $selectedQuickAccess,
                    selectedItemFilter: $selectedItemFilter,
                    searchText: $searchText,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    onAddTapped: {
                        store.presentAddSheet()
                    },
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
        .toolbar(.hidden, for: .navigationBar)
        .background {
            LibraryHomeDesign.Colors.phoneSurface
                .ignoresSafeArea()
        }
        .onChange(of: activeLibraryIdentity) { _, _ in
            resetChromeState()
        }
    }

    private var activeLibraryIdentity: String {
        guard let activeLibraryContext = store.activeLibraryContext else {
            return "none"
        }

        return "\(activeLibraryContext.libraryID.uuidString)|\(activeLibraryContext.storeScope.rawValue)"
    }

    private func resetChromeState() {
        selectedQuickAccess = .allItems
        selectedItemFilter = .none
        searchText = ""
        isSearchFieldFocused = false
    }
}

private struct LibraryHomeContent: View {
    let activeLibraryContext: ActiveLibraryContext
    let onAddTapped: () -> Void
    let onPartnerSettingsTapped: () -> Void
    let onOpen: (AppRoute) -> Void

    @Binding private var selectedQuickAccess: LibraryQuickAccessSelection
    @Binding private var selectedItemFilter: LibraryItemFilter
    @Binding private var searchText: String
    @FocusState.Binding private var isSearchFieldFocused: Bool
    @FetchRequest private var souvenirs: FetchedResults<Souvenir>
    @FetchRequest private var trips: FetchedResults<Trip>

    init(
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController,
        selectedQuickAccess: Binding<LibraryQuickAccessSelection>,
        selectedItemFilter: Binding<LibraryItemFilter>,
        searchText: Binding<String>,
        isSearchFieldFocused: FocusState<Bool>.Binding,
        onAddTapped: @escaping () -> Void,
        onPartnerSettingsTapped: @escaping () -> Void,
        onOpen: @escaping (AppRoute) -> Void
    ) {
        self.activeLibraryContext = activeLibraryContext
        self.onAddTapped = onAddTapped
        self.onPartnerSettingsTapped = onPartnerSettingsTapped
        self.onOpen = onOpen
        self._selectedQuickAccess = selectedQuickAccess
        self._selectedItemFilter = selectedItemFilter
        self._searchText = searchText
        self._isSearchFieldFocused = isSearchFieldFocused
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

    private var recentTrip: Trip? {
        activeTrips.first
    }

    private var primarySurface: LibraryPrimarySurface {
        switch selectedQuickAccess {
        case .trips:
            return .trips
        case .collections:
            return .places
        case .allItems:
            return .items
        }
    }

    private var needsInfoCount: Int {
        activeSouvenirs.filter(\.needsAttention).count
    }

    private var normalizedSearchQuery: String? {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return nil
        }

        return query.localizedLowercase
    }

    private var filteredSouvenirs: [Souvenir] {
        activeSouvenirs
            .filter { selectedItemFilter.matches($0) }
            .filter { souvenir in
                guard let normalizedSearchQuery else {
                    return true
                }

                return souvenir.matchesLibrarySearch(query: normalizedSearchQuery)
            }
    }

    private var filteredTrips: [Trip] {
        activeTrips.filter { trip in
            guard let normalizedSearchQuery else {
                return true
            }

            return trip.matchesLibrarySearch(query: normalizedSearchQuery)
        }
    }

    private var filteredPlaceGroups: [PlaceGroup] {
        placeGroups.filter { placeGroup in
            guard let normalizedSearchQuery else {
                return true
            }

            return placeGroup.matchesLibrarySearch(query: normalizedSearchQuery)
        }
    }

    private var hasVisibleSearchOrFilter: Bool {
        normalizedSearchQuery != nil || selectedItemFilter != .none
    }

    private var itemGridColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(),
                spacing: LibraryHomeDesign.Spacing.gridGap
            ),
            count: LibraryHomeDesign.Layout.gridColumnCount
        )
    }

    private var filteredItemsEmptyState: LibraryEmptyPresentation {
        if normalizedSearchQuery != nil {
            return LibraryEmptyPresentation(
                icon: "magnifyingglass",
                title: "No results",
                message: "Try a different search or clear the current filter."
            )
        }

        switch selectedItemFilter {
        case .onThisDay:
            let dateLabel = Date.now.formatted(.dateTime.month(.abbreviated).day())
            return LibraryEmptyPresentation(
                icon: "calendar",
                title: "Nothing from \(dateLabel)",
                message: "No souvenirs in this library were saved on this date."
            )
        case .needsInfo:
            return LibraryEmptyPresentation(
                icon: "checkmark.circle",
                title: "Everything looks filled in",
                message: "No souvenirs in this library are missing their key details right now."
            )
        case .none:
            return LibraryEmptyPresentation(
                icon: "shippingbox.fill",
                title: "No items yet",
                message: "Souvenirs will land here as soon as you start adding keepsakes to this library."
            )
        }
    }

    private func openRecentTrip() {
        selectedItemFilter = .none
        isSearchFieldFocused = false

        if let tripID = recentTrip?.id {
            onOpen(.trip(tripID))
        } else {
            selectedQuickAccess = .trips
        }
    }

    private func toggleTrips() {
        selectedItemFilter = .none
        isSearchFieldFocused = false
        selectedQuickAccess = selectedQuickAccess == .trips ? .allItems : .trips
    }

    private func toggleCollections() {
        selectedItemFilter = .none
        isSearchFieldFocused = false
        selectedQuickAccess = selectedQuickAccess == .collections ? .allItems : .collections
    }

    private func toggleItemFilter(_ filter: LibraryItemFilter) {
        selectedQuickAccess = .allItems
        isSearchFieldFocused = false
        selectedItemFilter = selectedItemFilter == filter ? .none : filter
    }

    private func focusSearch() {
        selectedQuickAccess = .allItems
        selectedItemFilter = .none
        isSearchFieldFocused = true
    }

    private func handleMicrophoneFallback() {
        // The screen shows a microphone affordance, but the app does not support voice search.
        // Focusing the real search field is the smallest honest fallback and still enables
        // system keyboard dictation when available.
        isSearchFieldFocused = true
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                LibraryHeader(
                    onAddTapped: onAddTapped,
                    onPartnerSettingsTapped: onPartnerSettingsTapped
                )
                .padding(.bottom, LibraryHomeDesign.Spacing.headerToSearch)

                LibrarySearchChrome(
                    placeholder: LibraryHomePreviewFixture.extractedDemo.searchPlaceholder,
                    searchText: $searchText,
                    isSearchFieldFocused: _isSearchFieldFocused,
                    onMicrophoneTapped: {
                        handleMicrophoneFallback()
                    }
                )
                .padding(.bottom, LibraryHomeDesign.Spacing.searchToRibbon)

                LibraryQuickAccessBand(
                    recentTripTitle: recentTrip?.displayTitle,
                    onOpenRecentTrip: {
                        openRecentTrip()
                    },
                    onOpenOnThisDay: {
                        toggleItemFilter(.onThisDay)
                    },
                    onOpenTrips: {
                        toggleTrips()
                    },
                    onOpenCollections: {
                        toggleCollections()
                    },
                    onOpenTags: {
                        focusSearch()
                    },
                    onOpenNeedsInfo: {
                        toggleItemFilter(.needsInfo)
                    },
                    isOnThisDaySelected: selectedItemFilter == .onThisDay,
                    isTripsSelected: selectedQuickAccess == .trips,
                    isCollectionsSelected: selectedQuickAccess == .collections,
                    isTagsSelected: isSearchFieldFocused || normalizedSearchQuery != nil,
                    isNeedsInfoSelected: selectedItemFilter == .needsInfo,
                    onThisDaySubtitle: Date.now.formatted(.dateTime.month(.abbreviated).day()),
                    tripCount: activeTrips.count,
                    collectionCount: placeGroups.count,
                    tagsSubtitle: normalizedSearchQuery == nil ? "Search" : "Active",
                    needsInfoCount: needsInfoCount
                )
                .padding(.bottom, LibraryHomeDesign.Spacing.ribbonToGrid)

                content
            }
            .padding(.horizontal, LibraryHomeDesign.Spacing.contentInsetX)
            .padding(.top, LibraryHomeDesign.Spacing.statusToHeader)
            .padding(.bottom, LibraryHomeDesign.Spacing.scrollContentBottomReserve)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var content: some View {
        switch primarySurface {
        case .items:
            itemsContent
        case .trips:
            tripsContent
        case .places:
            placesContent
        }
    }

    @ViewBuilder
    private var itemsContent: some View {
        if filteredSouvenirs.isEmpty {
            if hasVisibleSearchOrFilter {
                LibraryEmptyStateView(
                    icon: filteredItemsEmptyState.icon,
                    title: filteredItemsEmptyState.title,
                    message: filteredItemsEmptyState.message
                )
            } else {
                LibraryEmptyStateView(
                    icon: "shippingbox.fill",
                    title: "No items yet",
                    message: "Souvenirs will land here as soon as you start adding keepsakes to this library."
                )
            }
        } else {
            LazyVGrid(columns: itemGridColumns, spacing: LibraryHomeDesign.Spacing.gridGap) {
                ForEach(filteredSouvenirs, id: \.objectID) { souvenir in
                    if let souvenirID = souvenir.id {
                        Button {
                            onOpen(.souvenir(souvenirID))
                        } label: {
                            LibraryGridTile(
                                souvenir: souvenir,
                                isSharedLibrary: activeLibraryContext.storeScope == .sharedLibrary
                            )
                        }
                        .buttonStyle(LibraryGridTileButtonStyle())
                    } else {
                        LibraryGridTile(
                            souvenir: souvenir,
                            isSharedLibrary: activeLibraryContext.storeScope == .sharedLibrary
                        )
                    }
                }
            }
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var tripsContent: some View {
        if filteredTrips.isEmpty {
            if normalizedSearchQuery != nil {
                LibraryEmptyStateView(
                    icon: "magnifyingglass",
                    title: "No trips found",
                    message: "Try another search for a trip title or date."
                )
            } else {
                LibraryEmptyStateView(
                    icon: "suitcase.rolling.fill",
                    title: "No trips yet",
                    message: "Create a trip to group souvenirs from the same journey."
                )
            }
        } else {
            LazyVStack(spacing: AppSpacing.medium) {
                ForEach(filteredTrips, id: \.objectID) { trip in
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
        if filteredPlaceGroups.isEmpty {
            if normalizedSearchQuery != nil {
                LibraryEmptyStateView(
                    icon: "magnifyingglass",
                    title: "No collections found",
                    message: "Try another search for a place or country."
                )
            } else {
                LibraryEmptyStateView(
                    icon: "mappin.and.ellipse",
                    title: "No places yet",
                    message: "Places appear automatically from each souvenir's \"Got it in\" location."
                )
            }
        } else {
            LazyVStack(spacing: AppSpacing.medium) {
                ForEach(filteredPlaceGroups) { placeGroup in
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

private struct LibraryHeader: View {
    private enum Layout {
        static let centeredWordmarkInset: CGFloat = 96
        static let headerHitTarget: CGFloat = 44
    }

    let onAddTapped: () -> Void
    let onPartnerSettingsTapped: () -> Void

    var body: some View {
        ZStack {
            Text(LibraryHomePreviewFixture.extractedDemo.wordmarkText)
                .font(LibraryHomeDesign.Typography.wordmarkFont(relativeTo: .title3))
                .tracking(LibraryHomeDesign.Typography.wordmarkTracking)
                .foregroundStyle(LibraryHomeDesign.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, Layout.centeredWordmarkInset)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isStaticText)

            HStack(spacing: 0) {
                Button(action: onPartnerSettingsTapped) {
                    LibraryHeaderAvatarArt()
                        .frame(
                            width: LibraryHomeDesign.Layout.avatarSize,
                            height: LibraryHomeDesign.Layout.avatarSize
                        )
                }
                .buttonStyle(.plain)
                .frame(
                    width: Layout.headerHitTarget,
                    height: Layout.headerHitTarget,
                    alignment: .leading
                )
                .contentShape(Rectangle())
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("library.header.settings")

                Spacer(minLength: 0)

                Button(action: onAddTapped) {
                    HStack(spacing: LibraryHomeDesign.Layout.addButtonInnerGap) {
                        Image(systemName: LibraryHomeIcon.addPlus.systemName)
                            .font(.system(size: LibraryHomeIcon.addPlus.pointSize, weight: .semibold))

                        Text(LibraryHomePreviewFixture.extractedDemo.addButtonLabel)
                            .font(
                                AppFont.ui(
                                    size: LibraryHomeDesign.Typography.buttonLabelSize,
                                    weight: .semibold,
                                    relativeTo: .body
                                )
                            )
                    }
                    .foregroundStyle(LibraryHomeDesign.Colors.textInverse)
                    .padding(.leading, LibraryHomeDesign.Layout.addButtonLeadingPadding)
                    .padding(.trailing, LibraryHomeDesign.Layout.addButtonTrailingPadding)
                    .frame(height: LibraryHomeDesign.Layout.addButtonHeight)
                    .background(
                        Capsule(style: .continuous)
                            .fill(LibraryHomeDesign.Colors.terracotta)
                    )
                    .shadow(
                        color: LibraryHomeDesign.Colors.ribbonShadow,
                        radius: LibraryHomeDesign.Shadow.ribbonRadius,
                        y: LibraryHomeDesign.Shadow.ribbonYOffset
                    )
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3.5)
                .contentShape(Rectangle())
                .accessibilityLabel("Add Souvenir")
                .accessibilityHint("Import a photo to start a new souvenir.")
                .accessibilityIdentifier("library.header.add")
            }
        }
        .frame(height: LibraryHomeDesign.Layout.headerHeight)
    }
}

private struct LibraryHeaderAvatarArt: View {
    var body: some View {
        LibraryHomeAsset.avatarProfile.image
            .resizable()
            .scaledToFill()
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.78), lineWidth: 1)
            )
            .overlay(
                Circle()
                    .stroke(LibraryHomeDesign.Colors.subtleBorder, lineWidth: LibraryHomeDesign.Border.subtleWidth)
            )
            .shadow(
                color: LibraryHomeDesign.Colors.ribbonShadow,
                radius: LibraryHomeDesign.Shadow.ribbonRadius,
                y: LibraryHomeDesign.Shadow.ribbonYOffset
            )
    }
}

private struct LibrarySearchChrome: View {
    let placeholder: String
    @Binding var searchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    let onMicrophoneTapped: () -> Void

    var body: some View {
        HStack(spacing: LibraryHomeDesign.Spacing.searchInnerGap) {
            Image(systemName: LibraryHomeIcon.search.systemName)
                .font(.system(size: LibraryHomeIcon.search.pointSize, weight: .regular))
                .foregroundStyle(LibraryHomeDesign.Colors.textMuted)

            TextField(
                "",
                text: $searchText,
                prompt: Text(placeholder)
                    .foregroundStyle(LibraryHomeDesign.Colors.textMuted)
            )
            .font(
                AppFont.ui(
                    size: LibraryHomeDesign.Typography.searchPlaceholderSize,
                    relativeTo: .body
                )
            )
            .foregroundStyle(LibraryHomeDesign.Colors.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isSearchFieldFocused)
            .accessibilityLabel("Search library")

            Button(action: onMicrophoneTapped) {
                Image(systemName: LibraryHomeIcon.mic.systemName)
                    .font(.system(size: LibraryHomeIcon.mic.pointSize, weight: .regular))
                    .foregroundStyle(LibraryHomeDesign.Colors.textMuted.opacity(0.7))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Search options")
            .accessibilityHint("Focuses the search field. Use keyboard dictation if available.")
        }
        .padding(.horizontal, LibraryHomeDesign.Spacing.searchPaddingX)
        .frame(height: LibraryHomeDesign.Layout.searchFieldHeight)
        .background(
            Capsule(style: .continuous)
                .fill(LibraryHomeDesign.Colors.searchFieldFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(LibraryHomeDesign.Colors.subtleBorder, lineWidth: LibraryHomeDesign.Border.subtleWidth)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            isSearchFieldFocused = true
        }
        .accessibilityIdentifier("library.search")
    }
}

private struct LibraryQuickAccessBand: View {
    let recentTripTitle: String?
    let onOpenRecentTrip: () -> Void
    let onOpenOnThisDay: () -> Void
    let onOpenTrips: () -> Void
    let onOpenCollections: () -> Void
    let onOpenTags: () -> Void
    let onOpenNeedsInfo: () -> Void
    let isOnThisDaySelected: Bool
    let isTripsSelected: Bool
    let isCollectionsSelected: Bool
    let isTagsSelected: Bool
    let isNeedsInfoSelected: Bool
    let onThisDaySubtitle: String
    let tripCount: Int
    let collectionCount: Int
    let tagsSubtitle: String
    let needsInfoCount: Int

    var body: some View {
        HStack(spacing: 0) {
            LibraryQuickAccessButton(
                title: "Recent Trip",
                subtitle: recentTripTitle ?? "No trips yet",
                artwork: .asset(.featureRecentTripAmalfiCoast),
                accent: nil,
                isSelected: false,
                action: onOpenRecentTrip
            )

            LibraryQuickAccessButton(
                title: "On This Day",
                subtitle: onThisDaySubtitle,
                artwork: .icon(.onThisDay),
                accent: .teal,
                isSelected: isOnThisDaySelected,
                action: onOpenOnThisDay
            )

            LibraryQuickAccessButton(
                title: "Trips",
                subtitle: "\(tripCount)",
                artwork: .icon(.trips),
                accent: .teal,
                isSelected: isTripsSelected,
                action: onOpenTrips
            )

            LibraryQuickAccessButton(
                title: "Collections",
                subtitle: "\(collectionCount)",
                artwork: .icon(.collections),
                accent: .teal,
                isSelected: isCollectionsSelected,
                action: onOpenCollections
            )

            LibraryQuickAccessButton(
                title: "Tags",
                subtitle: tagsSubtitle,
                artwork: .icon(.tags),
                accent: .teal,
                isSelected: isTagsSelected,
                action: onOpenTags
            )

            LibraryQuickAccessButton(
                title: "Needs Info",
                subtitle: "\(needsInfoCount)",
                artwork: .icon(.needsInfo),
                accent: .amber,
                isSelected: isNeedsInfoSelected,
                action: onOpenNeedsInfo
            )
        }
        .padding(.horizontal, LibraryHomeDesign.Spacing.ribbonPaddingX)
        .padding(.top, LibraryHomeDesign.Spacing.ribbonPaddingTop)
        .padding(.bottom, LibraryHomeDesign.Spacing.ribbonPaddingBottom)
        .background(
            RoundedRectangle(
                cornerRadius: LibraryHomeDesign.CornerRadius.featureRibbon,
                style: .continuous
            )
            .fill(LibraryHomeDesign.Colors.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: LibraryHomeDesign.CornerRadius.featureRibbon,
                style: .continuous
            )
            .stroke(LibraryHomeDesign.Colors.subtleBorder, lineWidth: LibraryHomeDesign.Border.subtleWidth)
        )
        .shadow(
            color: LibraryHomeDesign.Colors.ribbonShadow,
            radius: LibraryHomeDesign.Shadow.ribbonRadius,
            y: LibraryHomeDesign.Shadow.ribbonYOffset
        )
        .accessibilityLabel("Library sections")
        .accessibilityIdentifier("library.quick_access")
    }
}

private struct LibraryQuickAccessButton: View {
    let title: String
    let subtitle: String
    let artwork: LibraryHomeFeatureItem.Artwork
    let accent: LibraryHomeAccent?
    let isSelected: Bool
    let action: () -> Void

    private var accentColor: Color {
        switch accent {
        case .amber:
            LibraryHomeDesign.Colors.amber
        case .teal:
            LibraryHomeDesign.Colors.teal
        case nil:
            LibraryHomeDesign.Colors.textPrimary
        }
    }

    private var accessibilityLabel: String {
        "\(title), \(subtitle)"
    }

    private var content: some View {
        VStack(spacing: LibraryHomeDesign.Spacing.featureItemGap) {
            LibraryQuickAccessIcon(
                artwork: artwork,
                accentColor: accentColor
            )

            Text(title)
                .font(
                    AppFont.ui(
                        size: LibraryHomeDesign.Typography.featureTitleSize,
                        weight: .semibold,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(LibraryHomeDesign.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)

            Text(subtitle)
                .font(
                    AppFont.ui(
                        size: LibraryHomeDesign.Typography.featureSecondarySize,
                        weight: accent == .amber ? .semibold : .medium,
                        relativeTo: .caption2
                    )
                )
                .foregroundStyle(accent == .amber ? LibraryHomeDesign.Colors.amber : LibraryHomeDesign.Colors.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? accentColor.opacity(0.18) : Color.clear, lineWidth: 1)
        )
        .frame(minHeight: LibraryHomeDesign.Layout.ribbonItemHeight, alignment: .top)
    }

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct LibraryQuickAccessIcon: View {
    let artwork: LibraryHomeFeatureItem.Artwork
    let accentColor: Color

    var body: some View {
        Group {
            switch artwork {
            case .asset(let asset):
                asset.image
                    .resizable()
                    .scaledToFill()
            case .icon(let icon):
                ZStack {
                    Circle()
                        .fill(LibraryHomeDesign.Colors.outerCanvas)

                    Image(systemName: icon.systemName)
                        .font(.system(size: icon.pointSize, weight: .medium))
                        .foregroundStyle(accentColor)
                }
            }
        }
        .frame(
            width: LibraryHomeDesign.Layout.ribbonCircleSize,
            height: LibraryHomeDesign.Layout.ribbonCircleSize
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(LibraryHomeDesign.Colors.subtleBorder, lineWidth: LibraryHomeDesign.Border.subtleWidth)
        )
    }
}

private struct LibraryPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.libraryPanelFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        }
        .shadow(color: AppTheme.libraryShadow, radius: 10, y: 4)
    }
}

private struct LibraryGridTile: View {
    let souvenir: Souvenir
    let isSharedLibrary: Bool

    private var overlayTitle: String? {
        souvenir.gotItInSummary
    }

    private var overlaySubtitle: String? {
        souvenir.shortAcquiredSummary
    }

    private var showsMetadata: Bool {
        overlayTitle != nil || overlaySubtitle != nil
    }

    private var metadataGradientStart: Color {
        let searchableText = [
            overlayTitle?.localizedLowercase,
            overlaySubtitle?.localizedLowercase
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        if searchableText.contains("marrakech") || searchableText.contains("morocco") {
            return LibraryHomeDesign.Colors.marrakechGradientStart
        }

        return LibraryHomeDesign.Colors.positanoGradientStart
    }

    private var accessibilityLabel: String {
        var parts = [souvenir.displayTitle]

        if let tripTitle = souvenir.visibleTripTitle {
            parts.append(tripTitle)
        }

        if let placeSummary = souvenir.gotItInSummary {
            parts.append(placeSummary)
        }

        if let dateSummary = souvenir.acquiredOrUpdatedSummary {
            parts.append(dateSummary)
        }

        if isSharedLibrary {
            parts.append("Shared library")
        }

        if souvenir.needsAttention {
            parts.append("Needs info")
        }

        return parts.joined(separator: ", ")
    }

    var body: some View {
        ZStack {
            LibraryTileImage(
                data: souvenir.primaryThumbnailData,
                placeholderSystemImage: "shippingbox.fill"
            )
        }
        .overlay(alignment: .bottomLeading) {
            if showsMetadata {
                LibraryGridMetadataOverlay(
                    title: overlayTitle,
                    subtitle: overlaySubtitle,
                    gradientStart: metadataGradientStart
                )
            }
        }
        .overlay(alignment: .bottom) {
            if isSharedLibrary {
                LibraryTileBadge(style: .shared)
                    .padding(.bottom, LibraryHomeDesign.Spacing.overlayInset)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if souvenir.needsAttention {
                LibraryTileBadge(style: .needsInfo)
                    .padding(.trailing, LibraryHomeDesign.Spacing.overlayInset)
                    .padding(.bottom, LibraryHomeDesign.Spacing.overlayInset)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LibraryHomeDesign.CornerRadius.gridCard, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: LibraryHomeDesign.CornerRadius.gridCard, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct LibraryGridMetadataOverlay: View {
    let title: String?
    let subtitle: String?
    let gradientStart: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    LibraryHomeDesign.Colors.overlayGradientEnd,
                    LibraryHomeDesign.Colors.overlayGradientEnd,
                    gradientStart
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 1) {
                if let title {
                    Text(title)
                        .font(
                            AppFont.ui(
                                size: LibraryHomeDesign.Typography.overlayTitleSize,
                                weight: .medium,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(LibraryHomeDesign.Colors.textInverse)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(
                            AppFont.ui(
                                size: LibraryHomeDesign.Typography.overlaySubtitleSize,
                                weight: .medium,
                                relativeTo: .caption2
                            )
                        )
                        .foregroundStyle(LibraryHomeDesign.Colors.textInverseSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(LibraryHomeDesign.Spacing.overlayInset)
            .shadow(
                color: LibraryHomeDesign.Colors.overlayTextShadow,
                radius: LibraryHomeDesign.Shadow.overlayTextRadius,
                y: LibraryHomeDesign.Shadow.overlayTextYOffset
            )
        }
        .allowsHitTesting(false)
    }
}

private struct LibraryTileImage: View {
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
                ZStack {
                    RoundedRectangle(
                        cornerRadius: LibraryHomeDesign.CornerRadius.gridCard,
                        style: .continuous
                    )
                    .fill(LibraryHomeDesign.Colors.outerCanvas)

                    Image(systemName: placeholderSystemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(LibraryHomeDesign.Colors.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(LibraryHomeDesign.Layout.gridCardAspectRatio, contentMode: .fit)
        .clipped()
        .overlay(
            RoundedRectangle(
                cornerRadius: LibraryHomeDesign.CornerRadius.gridCard,
                style: .continuous
            )
            .stroke(LibraryHomeDesign.Colors.subtleBorder.opacity(0.5), lineWidth: 0.6)
        )
    }
}

private struct LibraryTileBadge: View {
    enum Style: Equatable {
        case shared
        case needsInfo
    }

    let style: Style

    private var symbolName: String {
        switch style {
        case .shared:
            return LibraryHomeIcon.sharedBadge.systemName
        case .needsInfo:
            return LibraryHomeIcon.needsInfoBadge.systemName
        }
    }

    private var title: String {
        switch style {
        case .shared:
            return "Shared"
        case .needsInfo:
            return "Needs Info"
        }
    }

    private var fill: Color {
        switch style {
        case .shared:
            return LibraryHomeDesign.Colors.teal
        case .needsInfo:
            return LibraryHomeDesign.Colors.amber
        }
    }

    private var foreground: Color {
        LibraryHomeDesign.Colors.textInverse
    }

    private var height: CGFloat {
        switch style {
        case .shared:
            return LibraryHomeDesign.Layout.sharedBadgeHeight
        case .needsInfo:
            return LibraryHomeDesign.Layout.needsInfoBadgeHeight
        }
    }

    private var horizontalPadding: (leading: CGFloat, trailing: CGFloat) {
        switch style {
        case .shared:
            return (
                leading: LibraryHomeDesign.Layout.sharedBadgeLeadingPadding,
                trailing: LibraryHomeDesign.Layout.sharedBadgeTrailingPadding
            )
        case .needsInfo:
            return (
                leading: LibraryHomeDesign.Layout.needsInfoBadgeLeadingPadding,
                trailing: LibraryHomeDesign.Layout.needsInfoBadgeTrailingPadding
            )
        }
    }

    var body: some View {
        HStack(spacing: LibraryHomeDesign.Spacing.badgeGap) {
            Image(systemName: symbolName)
                .font(.system(size: style == .shared ? LibraryHomeIcon.sharedBadge.pointSize : LibraryHomeIcon.needsInfoBadge.pointSize, weight: .semibold))

            Text(title)
                .font(
                    AppFont.ui(
                        size: LibraryHomeDesign.Typography.badgeLabelSize,
                        weight: .semibold,
                        relativeTo: .caption2
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(foreground)
        .padding(.leading, horizontalPadding.leading)
        .padding(.trailing, horizontalPadding.trailing)
        .frame(height: height)
        .background(
            Capsule(style: .continuous)
                .fill(fill)
        )
        .overlay {
            if style == .needsInfo {
                Capsule(style: .continuous)
                    .stroke(
                        LibraryHomeDesign.Colors.amber,
                        lineWidth: LibraryHomeDesign.Border.needsInfoBadgeWidth
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LibraryGridTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(
                    cornerRadius: LibraryHomeDesign.CornerRadius.gridCard,
                    style: .continuous
                )
                    .stroke(
                        configuration.isPressed ? LibraryHomeDesign.Colors.terracotta : Color.clear,
                        lineWidth: LibraryHomeDesign.Border.selectedCardOutlineWidth
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

private enum LibraryQuickAccessSelection: Equatable {
    case allItems
    case trips
    case collections
}

private enum LibraryItemFilter: Equatable {
    case none
    case onThisDay
    case needsInfo

    func matches(_ souvenir: Souvenir) -> Bool {
        switch self {
        case .none:
            return true
        case .onThisDay:
            return souvenir.isOnThisDayMatch
        case .needsInfo:
            return souvenir.needsAttention
        }
    }
}

private enum LibraryPrimarySurface {
    case items
    case trips
    case places
}

private struct LibraryEmptyPresentation {
    let icon: String
    let title: String
    let message: String
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
            return "You're using this library on your own for now."
        case .inviteSent:
            return "Your partner invite is still pending while you keep using the library."
        case .connected:
            return activeLibraryContext.isOwner
                ? "Everything you save here stays in your shared library."
                : "You're looking at the shared library from your partner's invite."
        }
    }

    private var badgeTitle: String {
        switch partnerState {
        case .none:
            return "Personal"
        case .inviteSent:
            return "Invite Pending"
        case .connected:
            return "Shared"
        }
    }

    private var badgeTint: Color {
        switch partnerState {
        case .connected:
            return AppTheme.libraryTeal
        case .inviteSent:
            return AppTheme.libraryAmber
        case .none:
            return AppTheme.libraryTextSecondary
        }
    }

    var body: some View {
        LibraryPanel {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(title)
                        .font(AppFont.ui(size: 18, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(AppTheme.libraryTextPrimary)

                    Text(message)
                        .font(AppFont.ui(size: 14, relativeTo: .subheadline))
                        .foregroundStyle(AppTheme.libraryTextSecondary)
                }

                Spacer(minLength: AppSpacing.small)

                Text(badgeTitle)
                    .font(AppFont.ui(size: 12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(badgeTint)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(badgeTint.opacity(0.14))
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryInviteBanner: View {
    let state: LibraryOwnerShareBannerState
    let action: () -> Void

    var body: some View {
        LibraryPanel {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                Image(systemName: state.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.libraryTeal)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.libraryRaisedFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.libraryBorder, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(state.title)
                        .font(AppFont.ui(size: 16, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(AppTheme.libraryTextPrimary)

                    Text(state.message)
                        .font(AppFont.ui(size: 13, relativeTo: .subheadline))
                        .foregroundStyle(AppTheme.libraryTextSecondary)
                }

                Spacer(minLength: AppSpacing.small)

                Button(action: action) {
                    Text(state.actionTitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.libraryTerracotta)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SouvenirRowCard: View {
    let souvenir: Souvenir

    var body: some View {
        LibraryPanel {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                LibraryThumbnail(
                    data: souvenir.primaryThumbnailData,
                    placeholderSystemImage: "shippingbox.fill"
                )

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(souvenir.displayTitle)
                        .font(AppFont.ui(size: 16, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(AppTheme.libraryTextPrimary)

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
                    .foregroundStyle(AppTheme.libraryTextMuted)
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
        LibraryPanel {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                LibraryThumbnail(
                    data: coverThumbnailData,
                    placeholderSystemImage: "suitcase.rolling.fill"
                )

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(trip.displayTitle)
                        .font(AppFont.ui(size: 16, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(AppTheme.libraryTextPrimary)

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
                    .foregroundStyle(AppTheme.libraryTextMuted)
                    .padding(.top, AppSpacing.xSmall)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlaceRowCard: View {
    let placeGroup: PlaceGroup

    var body: some View {
        LibraryPanel {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                LibraryThumbnail(
                    data: placeGroup.thumbnailData,
                    placeholderSystemImage: "mappin.and.ellipse"
                )

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(placeGroup.title)
                        .font(AppFont.ui(size: 16, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(AppTheme.libraryTextPrimary)

                    LibraryMetadataLabel(
                        systemImage: "shippingbox.fill",
                        text: "\(placeGroup.souvenirCount) \(placeGroup.souvenirCount == 1 ? "souvenir" : "souvenirs")"
                    )
                }

                Spacer(minLength: AppSpacing.small)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.libraryTextMuted)
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
                    .foregroundStyle(AppTheme.libraryTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.libraryRaisedFill)
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        )
    }
}

private struct LibraryMetadataLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(AppFont.metadata(size: 12, relativeTo: .subheadline))
            .foregroundStyle(AppTheme.libraryTextSecondary)
            .labelStyle(.titleAndIcon)
    }
}

private struct LibraryEmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        LibraryPanel {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.libraryTextPrimary)

            Text(title)
                .font(AppFont.ui(size: 18, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(AppTheme.libraryTextPrimary)

            Text(message)
                .font(AppFont.ui(size: 14, relativeTo: .subheadline))
                .foregroundStyle(AppTheme.libraryTextSecondary)
        }
    }
}

private struct LibraryFirstSouvenirCard: View {
    let onAddTapped: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        LibraryPanel {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.libraryRaisedFill)

                    Image("SouvieShelfMark")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                }
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.libraryBorder, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Your library starts here")
                        .font(AppFont.display(size: 28, relativeTo: .title2))
                        .foregroundStyle(AppTheme.libraryTextPrimary)

                    Text("Save your first souvenir to begin your collection.")
                        .font(AppFont.ui(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AppTheme.libraryTextSecondary)
                }
            }

            Button(action: onAddTapped) {
                Text("Add first souvenir")
                    .font(AppFont.ui(size: 16, weight: .semibold, relativeTo: .body))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.libraryTerracotta)
            .accessibilityHint("Opens the Add Souvenir flow.")

            Button(action: onOpenSettings) {
                Text("Invite Partner later in Settings")
                    .font(AppFont.ui(size: 13, weight: .medium, relativeTo: .footnote))
                    .foregroundStyle(AppTheme.libraryTextSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
    }
}

enum LibraryContentState: Equatable {
    case empty
    case populated

    static func resolve(
        souvenirCount: Int,
        tripCount: Int
    ) -> LibraryContentState {
        souvenirCount == 0 && tripCount == 0 ? .empty : .populated
    }
}

enum LibraryOwnerShareBannerState: Equatable {
    case invitePartner
    case invitePending

    static func resolve(
        isOwner: Bool,
        partnerState: PartnerConnectionState
    ) -> LibraryOwnerShareBannerState? {
        guard isOwner else {
            return nil
        }

        switch partnerState {
        case .none:
            return .invitePartner
        case .inviteSent:
            return .invitePending
        case .connected:
            return nil
        }
    }

    var title: String {
        switch self {
        case .invitePartner:
            return "Invite Partner later"
        case .invitePending:
            return "Invite still pending"
        }
    }

    var message: String {
        switch self {
        case .invitePartner:
            return "Optional: open Settings whenever you want to share this library with your partner."
        case .invitePending:
            return "You can keep using the app while your partner accepts. Open Settings to resend or manage the invite."
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

    var shortAcquiredSummary: String? {
        if let acquiredDate {
            return acquiredDate.formatted(date: .abbreviated, time: .omitted)
        }

        return nil
    }

    var needsAttention: Bool {
        title.normalizedDisplayValue == nil || visibleTripTitle == nil || gotItInSummary == nil
    }

    var isOnThisDayMatch: Bool {
        guard let acquiredDate else {
            return false
        }

        let calendar = Calendar.autoupdatingCurrent
        let acquiredComponents = calendar.dateComponents([.month, .day], from: acquiredDate)
        let currentComponents = calendar.dateComponents([.month, .day], from: .now)
        return acquiredComponents.month == currentComponents.month && acquiredComponents.day == currentComponents.day
    }

    var librarySearchableText: String {
        [
            displayTitle,
            visibleTripTitle,
            gotItInSummary,
            story.normalizedDisplayValue,
            acquiredOrUpdatedSummary,
            needsAttention ? "needs info" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    func matchesLibrarySearch(query: String) -> Bool {
        librarySearchableText.localizedLowercase.contains(query)
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

    var librarySearchableText: String {
        [
            displayTitle,
            dateRangeSummary,
            TripPresentationLogic.destinationSummary(from: destinationSummary)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    func matchesLibrarySearch(query: String) -> Bool {
        librarySearchableText.localizedLowercase.contains(query)
    }
}

private extension PlaceGroup {
    var librarySearchableText: String {
        [title]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    func matchesLibrarySearch(query: String) -> Bool {
        librarySearchableText.localizedLowercase.contains(query)
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

/// Preview/demo only. Renders the exact extracted Library Home sample content without touching
/// the live Core Data-backed Library screen or production app state.
private struct LibraryHomeExtractedDemoPreview: View {
    private let fixture = LibraryHomePreviewFixture.extractedDemo
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    private var itemGridColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(),
                spacing: LibraryHomeDesign.Spacing.gridGap
            ),
            count: LibraryHomeDesign.Layout.gridColumnCount
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    LibraryHeader(
                        onAddTapped: {},
                        onPartnerSettingsTapped: {}
                    )
                    .padding(.bottom, LibraryHomeDesign.Spacing.headerToSearch)

                    LibrarySearchChrome(
                        placeholder: fixture.searchPlaceholder,
                        searchText: $searchText,
                        isSearchFieldFocused: $isSearchFieldFocused,
                        onMicrophoneTapped: {
                            isSearchFieldFocused = true
                        }
                    )
                    .padding(.bottom, LibraryHomeDesign.Spacing.searchToRibbon)

                    LibraryHomeExtractedDemoRibbon(
                        items: fixture.featureRibbonItems
                    )
                    .padding(.bottom, LibraryHomeDesign.Spacing.ribbonToGrid)

                    LazyVGrid(columns: itemGridColumns, spacing: LibraryHomeDesign.Spacing.gridGap) {
                        ForEach(fixture.gridCards) { card in
                            LibraryHomeExtractedDemoGridTile(card: card)
                        }
                    }
                }
                .padding(.horizontal, LibraryHomeDesign.Spacing.contentInsetX)
                .padding(.top, LibraryHomeDesign.Spacing.statusToHeader)
                .padding(.bottom, LibraryHomeDesign.Spacing.scrollContentBottomReserve)
            }

            LibraryHomeExtractedDemoBottomBar(
                tabs: fixture.bottomTabs
            )
        }
        .frame(
            width: LibraryHomeDesign.Layout.frameWidth,
            height: LibraryHomeDesign.Layout.frameHeight
        )
        .background(LibraryHomeDesign.Colors.phoneSurface)
    }
}

private struct LibraryHomeExtractedDemoRibbon: View {
    let items: [LibraryHomeFeatureItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                LibraryQuickAccessButton(
                    title: item.title,
                    subtitle: item.secondaryText,
                    artwork: item.artwork,
                    accent: item.accent,
                    isSelected: false,
                    action: {}
                )
            }
        }
        .padding(.horizontal, LibraryHomeDesign.Spacing.ribbonPaddingX)
        .padding(.top, LibraryHomeDesign.Spacing.ribbonPaddingTop)
        .padding(.bottom, LibraryHomeDesign.Spacing.ribbonPaddingBottom)
        .background(
            RoundedRectangle(
                cornerRadius: LibraryHomeDesign.CornerRadius.featureRibbon,
                style: .continuous
            )
            .fill(LibraryHomeDesign.Colors.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: LibraryHomeDesign.CornerRadius.featureRibbon,
                style: .continuous
            )
            .stroke(LibraryHomeDesign.Colors.subtleBorder, lineWidth: LibraryHomeDesign.Border.subtleWidth)
        )
        .shadow(
            color: LibraryHomeDesign.Colors.ribbonShadow,
            radius: LibraryHomeDesign.Shadow.ribbonRadius,
            y: LibraryHomeDesign.Shadow.ribbonYOffset
        )
    }
}

private struct LibraryHomeExtractedDemoGridTile: View {
    let card: LibraryHomeGridCard

    private var gradientStartColor: Color {
        let searchableText = [
            card.overlay?.title.localizedLowercase,
            card.overlay?.subtitle.localizedLowercase
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        if searchableText.contains("marrakech") || searchableText.contains("morocco") {
            return LibraryHomeDesign.Colors.marrakechGradientStart
        }

        return LibraryHomeDesign.Colors.positanoGradientStart
    }

    var body: some View {
        ZStack {
            card.asset.image
                .resizable()
                .scaledToFill()
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(LibraryHomeDesign.Layout.gridCardAspectRatio, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
            if let overlay = card.overlay {
                LibraryGridMetadataOverlay(
                    title: overlay.title,
                    subtitle: overlay.subtitle,
                    gradientStart: gradientStartColor
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let badge = card.badge,
               badge.placement == .bottomCenter {
                badgeView(for: badge)
                    .padding(.bottom, LibraryHomeDesign.Spacing.overlayInset)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge = card.badge,
               badge.placement == .bottomRight {
                badgeView(for: badge)
                    .padding(.trailing, LibraryHomeDesign.Spacing.overlayInset)
                    .padding(.bottom, LibraryHomeDesign.Spacing.overlayInset)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LibraryHomeDesign.CornerRadius.gridCard, style: .continuous))
        .overlay(
            RoundedRectangle(
                cornerRadius: LibraryHomeDesign.CornerRadius.gridCard,
                style: .continuous
            )
            .stroke(LibraryHomeDesign.Colors.subtleBorder.opacity(0.5), lineWidth: 0.6)
        )
        .overlay {
            if card.isSelected {
                RoundedRectangle(
                    cornerRadius: LibraryHomeDesign.CornerRadius.gridCard,
                    style: .continuous
                )
                .stroke(
                    LibraryHomeDesign.Colors.terracotta,
                    lineWidth: LibraryHomeDesign.Border.selectedCardOutlineWidth
                )
                .padding(LibraryHomeDesign.Border.selectedCardOutlineInsetOffset)
            }
        }
        .accessibilityLabel(card.sourceAnnotation)
    }

    @ViewBuilder
    private func badgeView(for badge: LibraryHomeGridCard.Badge) -> some View {
        switch badge.style {
        case .shared:
            LibraryTileBadge(style: .shared)
        case .needsInfo:
            LibraryTileBadge(style: .needsInfo)
        }
    }
}

private struct LibraryHomeExtractedDemoBottomBar: View {
    private enum Layout {
        static let height: CGFloat = 79.5
        static let borderWidth: CGFloat = 1
    }

    let tabs: [LibraryHomeBottomTab]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                VStack(spacing: LibraryHomeDesign.Spacing.bottomBarItemGap) {
                    Image(systemName: tab.icon.systemName)
                        .font(
                            .system(
                                size: tab.icon.pointSize,
                                weight: tab.isSelected ? .medium : .regular
                            )
                        )

                    Text(tab.title)
                        .font(
                            AppFont.ui(
                                size: LibraryHomeDesign.Typography.tabLabelSize,
                                weight: tab.isSelected ? .medium : .regular,
                                relativeTo: .caption2
                            )
                        )
                }
                .foregroundStyle(
                    tab.isSelected
                        ? LibraryHomeDesign.Colors.terracotta
                        : LibraryHomeDesign.Colors.inactiveIcon
                )
                .frame(maxWidth: .infinity)
                .padding(.top, LibraryHomeDesign.Spacing.bottomBarTopPadding)
                .padding(.bottom, LibraryHomeDesign.Spacing.bottomBarBottomPadding)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.height, alignment: .top)
        .background(LibraryHomeDesign.Colors.phoneSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LibraryHomeDesign.Colors.subtleBorder)
                .frame(height: Layout.borderWidth)
        }
    }
}

struct LibraryScreen_Previews: PreviewProvider {
    static var previews: some View {
        let environment = AppEnvironment.preview(.ready)
        return Group {
            LibraryScreen(store: environment.appStore)
                .environmentObject(environment)
                .previewDisplayName("Library Live")

            LibraryHomeExtractedDemoPreview()
                .previewDisplayName("Library Extracted Demo")
        }
    }
}
