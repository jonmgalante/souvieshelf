import CoreData
import SwiftUI
import UIKit

struct LibraryScreen: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Group {
            if store.activeLibraryContext != nil {
                LibraryMockupHomeScreen(
                    onAddTapped: {
                        store.presentAddSheet()
                    },
                    onAvatarTapped: {
                        store.open(.settings)
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
        .appScreenBackground(AppTheme.libraryParchmentBackground)
    }
}

private struct LibraryHomeContent: View {
    let activeLibraryContext: ActiveLibraryContext
    let onAddTapped: () -> Void
    let onPartnerSettingsTapped: () -> Void
    let onOpen: (AppRoute) -> Void

    @Binding private var selectedQuickAccess: LibraryQuickAccessSelection
    @FetchRequest private var souvenirs: FetchedResults<Souvenir>
    @FetchRequest private var trips: FetchedResults<Trip>

    init(
        activeLibraryContext: ActiveLibraryContext,
        persistenceController: PersistenceController,
        selectedQuickAccess: Binding<LibraryQuickAccessSelection>,
        onAddTapped: @escaping () -> Void,
        onPartnerSettingsTapped: @escaping () -> Void,
        onOpen: @escaping (AppRoute) -> Void
    ) {
        self.activeLibraryContext = activeLibraryContext
        self.onAddTapped = onAddTapped
        self.onPartnerSettingsTapped = onPartnerSettingsTapped
        self.onOpen = onOpen
        self._selectedQuickAccess = selectedQuickAccess
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

    private var contentState: LibraryContentState {
        LibraryContentState.resolve(
            souvenirCount: activeSouvenirs.count,
            tripCount: activeTrips.count
        )
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
        contentState == .empty
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

    private var itemGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                LibraryHeader(
                    onAddTapped: onAddTapped,
                    onPartnerSettingsTapped: onPartnerSettingsTapped
                )

                LibraryContextIndicator(storeScope: activeLibraryContext.storeScope)

                if isLibraryEmpty {
                    LibraryFirstSouvenirCard(
                        onAddTapped: onAddTapped,
                        onOpenSettings: onPartnerSettingsTapped
                    )
                } else {
                    LibrarySearchChrome()

                    LibraryQuickAccessBand(
                        selectedQuickAccess: $selectedQuickAccess,
                        recentTripTitle: recentTrip?.displayTitle ?? "No trips yet",
                        recentTripThumbnailData: recentTrip.flatMap { tripMetrics(for: $0).coverThumbnailData },
                        onOpenRecentTrip: recentTrip?.id == nil ? nil : {
                            guard let tripID = recentTrip?.id else {
                                return
                            }

                            onOpen(.trip(tripID))
                        },
                        tripCount: activeTrips.count,
                        collectionCount: placeGroups.count,
                        needsInfoCount: needsInfoCount
                    )

                    content
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, AppSpacing.large)
        }
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
        if activeSouvenirs.isEmpty {
            switch selectedQuickAccess {
            case .allItems, .trips, .collections:
                LibraryEmptyStateView(
                    icon: "shippingbox.fill",
                    title: "No items yet",
                    message: "Souvenirs will land here as soon as you start adding keepsakes to this library."
                )
            }
        } else {
            LazyVGrid(columns: itemGridColumns, spacing: 10) {
                ForEach(activeSouvenirs, id: \.objectID) { souvenir in
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
        }
    }

    @ViewBuilder
    private var tripsContent: some View {
        if activeTrips.isEmpty {
            LibraryEmptyStateView(
                icon: "suitcase.rolling.fill",
                title: "No trips yet",
                message: "Create a trip to group souvenirs from the same journey."
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

private struct LibraryHeader: View {
    let onAddTapped: () -> Void
    let onPartnerSettingsTapped: () -> Void

    var body: some View {
        ZStack {
            Text("SouvieShelf")
                .font(AppFont.display(size: 32, relativeTo: .largeTitle))
                .foregroundStyle(AppTheme.libraryTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 100)

            HStack {
                Button(action: onPartnerSettingsTapped) {
                    LibraryHeaderAvatarArt()
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("library.header.settings")

                Spacer()

                Button(action: onAddTapped) {
                    HStack(spacing: AppSpacing.small) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))

                        Text("Add")
                            .font(AppFont.ui(size: 15, weight: .semibold, relativeTo: .body))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.libraryTerracotta)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Souvenir")
                .accessibilityHint("Import a photo to start a new souvenir.")
                .accessibilityIdentifier("library.header.add")
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
}

private struct LibraryHeaderAvatarArt: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.libraryRaisedFill)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.libraryTerracotta.opacity(0.34),
                            AppTheme.libraryAmber.opacity(0.18),
                            AppTheme.libraryTeal.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(1)

            Circle()
                .fill(Color.white.opacity(0.26))
                .frame(width: 16, height: 16)
                .offset(x: -8, y: -8)
                .blur(radius: 2)

            Circle()
                .fill(AppTheme.libraryTeal.opacity(0.18))
                .frame(width: 20, height: 20)
                .offset(x: 9, y: 8)

            Circle()
                .stroke(Color.white.opacity(0.45), lineWidth: 0.8)
                .padding(1)
        }
        .overlay(
            Circle()
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        )
    }
}

private struct LibraryContextIndicator: View {
    let storeScope: StoreScope

    private var isPersonalSelected: Bool {
        storeScope == .privateLibrary
    }

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            LibraryContextPill(
                title: "Personal",
                isSelected: isPersonalSelected
            )

            LibraryContextPill(
                title: "Shared",
                isSelected: !isPersonalSelected
            )
        }
        .padding(4)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.libraryFieldFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Library context")
        .accessibilityValue(isPersonalSelected ? "Personal" : "Shared")
        .accessibilityIdentifier("library.context")
    }
}

private struct LibraryContextPill: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(AppFont.ui(size: 16, weight: .semibold, relativeTo: .body))
            .foregroundStyle(isSelected ? AppTheme.libraryTextPrimary : AppTheme.libraryTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AppTheme.libraryRaisedFill : Color.clear)
            )
    }
}

private struct LibrarySearchChrome: View {
    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppTheme.libraryTextMuted)

            Text("Search souvenirs, places, trips, tags...")
                .font(AppFont.ui(size: 17, relativeTo: .body))
                .foregroundStyle(AppTheme.libraryTextMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()
        }
        .padding(.horizontal, AppSpacing.medium)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(AppTheme.libraryFieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LibraryQuickAccessBand: View {
    @Binding var selectedQuickAccess: LibraryQuickAccessSelection
    let recentTripTitle: String?
    let recentTripThumbnailData: Data?
    let onOpenRecentTrip: (() -> Void)?
    let tripCount: Int
    let collectionCount: Int
    let needsInfoCount: Int

    var body: some View {
        HStack(spacing: 2) {
            LibraryQuickAccessButton(
                title: "Recent Trip",
                subtitle: recentTripTitle,
                symbolName: "photo",
                tint: AppTheme.libraryTeal,
                isSelected: false,
                thumbnailData: recentTripThumbnailData,
                action: onOpenRecentTrip
            )

            LibraryQuickAccessButton(
                title: "On This Day",
                subtitle: Date.now.formatted(.dateTime.month(.abbreviated).day()),
                symbolName: "calendar",
                tint: AppTheme.libraryTeal,
                isSelected: false,
                action: nil
            )

            LibraryQuickAccessButton(
                title: "Trips",
                subtitle: "\(tripCount)",
                symbolName: "suitcase",
                tint: AppTheme.libraryTeal,
                isSelected: selectedQuickAccess == .trips,
                action: {
                    selectedQuickAccess = selectedQuickAccess == .trips ? .allItems : .trips
                }
            )

            LibraryQuickAccessButton(
                title: "Collections",
                subtitle: "\(collectionCount)",
                symbolName: "rectangle.stack",
                tint: AppTheme.libraryTeal,
                isSelected: selectedQuickAccess == .collections,
                action: {
                    selectedQuickAccess = selectedQuickAccess == .collections ? .allItems : .collections
                }
            )

            LibraryQuickAccessButton(
                title: "Tags",
                subtitle: nil,
                symbolName: "tag",
                tint: AppTheme.libraryTeal,
                isSelected: false,
                action: nil
            )

            LibraryQuickAccessButton(
                title: "Needs Info",
                subtitle: "\(needsInfoCount)",
                symbolName: "exclamationmark.circle",
                tint: AppTheme.libraryTeal,
                isSelected: false,
                action: nil
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.libraryRaisedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        )
        .shadow(color: AppTheme.libraryShadow, radius: 10, y: 4)
        .accessibilityLabel("Library sections")
        .accessibilityIdentifier("library.quick_access")
    }
}

private struct LibraryQuickAccessButton: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let tint: Color
    let isSelected: Bool
    let thumbnailData: Data?
    let action: (() -> Void)?

    init(
        title: String,
        subtitle: String?,
        symbolName: String,
        tint: Color,
        isSelected: Bool,
        thumbnailData: Data? = nil,
        action: (() -> Void)?
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.tint = tint
        self.isSelected = isSelected
        self.thumbnailData = thumbnailData
        self.action = action
    }

    private var accessibilityLabel: String {
        if let subtitle,
           !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(title), \(subtitle)"
        }

        return title
    }

    private var content: some View {
        VStack(spacing: 8) {
            LibraryQuickAccessIcon(
                symbolName: symbolName,
                tint: tint,
                thumbnailData: thumbnailData
            )

            Text(title)
                .font(AppFont.ui(size: 11.5, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(AppTheme.libraryTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)

            Text(subtitle ?? " ")
                .font(AppFont.ui(size: 10.5, weight: .medium, relativeTo: .caption2))
                .foregroundStyle(AppTheme.libraryTextMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? AppTheme.libraryFieldFill : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? AppTheme.librarySelectionOutline.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .frame(minHeight: 104)
    }

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
        }
    }
}

private struct LibraryQuickAccessIcon: View {
    let symbolName: String
    let tint: Color
    let thumbnailData: Data?

    var body: some View {
        Group {
            if let thumbnailData,
               let image = UIImage(data: thumbnailData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(AppTheme.libraryRaisedFill)

                    Image(systemName: symbolName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
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

    private var showsMetadata: Bool {
        souvenir.gotItInSummary != nil || souvenir.acquiredOrUpdatedSummary != nil
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

            VStack(spacing: 0) {
                Spacer()

                HStack(alignment: .center, spacing: AppSpacing.small) {
                    if isSharedLibrary {
                        LibraryTileBadge(
                            symbolName: "person.2.fill",
                            title: "Shared",
                            fill: AppTheme.librarySharedBadgeFill,
                            foreground: AppTheme.libraryTeal
                        )
                    }

                    Spacer()

                    if souvenir.needsAttention {
                        LibraryTileBadge(
                            symbolName: "exclamationmark.circle.fill",
                            title: "Needs Info",
                            fill: AppTheme.libraryNeedsInfoBadgeFill,
                            foreground: AppTheme.libraryAmber
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.small)
                .padding(.bottom, showsMetadata ? 8 : AppSpacing.small)

                if showsMetadata {
                    VStack(alignment: .leading, spacing: 1) {
                        if let placeSummary = souvenir.gotItInSummary {
                            Text(placeSummary)
                                .font(AppFont.ui(size: 12, weight: .medium, relativeTo: .caption))
                                .foregroundStyle(AppTheme.libraryTextPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        if let dateSummary = souvenir.shortAcquiredSummary {
                            Text(dateSummary)
                                .font(AppFont.ui(size: 11, weight: .medium, relativeTo: .caption2))
                                .foregroundStyle(AppTheme.libraryTextSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 11)
                    .background(
                        LinearGradient(
                            colors: [
                                AppTheme.libraryRaisedFill.opacity(0),
                                AppTheme.libraryRaisedFill.opacity(0.88),
                                AppTheme.libraryRaisedFill.opacity(0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.libraryFieldFill)

                    Image(systemName: placeholderSystemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppTheme.libraryTextMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.88, contentMode: .fit)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.libraryBorder.opacity(0.4), lineWidth: 0.6)
        )
    }
}

private struct LibraryTileBadge: View {
    let symbolName: String
    let title: String
    let fill: Color
    let foreground: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))

            Text(title)
                .font(AppFont.ui(size: 12, weight: .semibold, relativeTo: .caption))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            Capsule(style: .continuous)
                .fill(fill)
        )
        .accessibilityHidden(true)
    }
}

private struct LibraryGridTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        configuration.isPressed ? AppTheme.librarySelectionOutline : Color.clear,
                        lineWidth: 0.9
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

private enum LibraryQuickAccessSelection: Equatable {
    case allItems
    case trips
    case collections
}

private enum LibraryPrimarySurface {
    case items
    case trips
    case places
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
