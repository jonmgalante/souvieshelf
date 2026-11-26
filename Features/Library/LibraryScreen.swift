import CoreData
import SwiftUI
import UIKit

struct LibraryScreen: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var store: AppStore

    var body: some View {
        Group {
            if let library = store.activeLibraryContext {
                LibraryHomeContent(
                    library: library,
                    persistence: environment.dependencies.persistenceController,
                    shareAcceptanceStartedAt: store.shareAcceptanceStartedAt,
                    onAdd: store.presentAddSheet,
                    onOpen: store.open
                )
                .id("\(library.storeScope.rawValue)/\(library.libraryID)")
            } else {
                ProgressView("Opening Our Library…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(GalleryTheme.ink)
        .tint(GalleryTheme.accent)
        .background { GalleryTheme.canvas.ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct LibraryHomeContent: View {
    let library: ActiveLibraryContext
    let persistence: PersistenceController
    let shareAcceptanceStartedAt: Date?
    let onAdd: () -> Void
    let onOpen: (AppRoute) -> Void
    @FetchRequest private var souvenirs: FetchedResults<Souvenir>
    @FetchRequest private var trips: FetchedResults<Trip>
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var segment: LibrarySegment = .items
    @State private var filter: LibraryItemFilter = .none
    @State private var searchText = ""
    @State private var searchPresented = false
    @FocusState private var searchFocused: Bool
    @State private var sharedImportFinished = false
    @State private var importRevision = 0

    init(library: ActiveLibraryContext, persistence: PersistenceController, shareAcceptanceStartedAt: Date?,
         onAdd: @escaping () -> Void, onOpen: @escaping (AppRoute) -> Void) {
        self.library = library
        self.persistence = persistence
        self.shareAcceptanceStartedAt = shareAcceptanceStartedAt
        self.onAdd = onAdd
        self.onOpen = onOpen
        _souvenirs = FetchRequest(fetchRequest: LibraryFetchRequestFactory.souvenirs(for: library, persistenceController: persistence))
        _trips = FetchRequest(fetchRequest: LibraryFetchRequestFactory.trips(for: library, persistenceController: persistence))
    }

    private var state: LibraryContentState {
        .resolve(souvenirCount: souvenirs.count, tripCount: trips.count,
                 awaitingImport: library.storeScope == .sharedLibrary && !sharedImportFinished)
    }

    private var needsImportCheck: Bool {
        library.storeScope == .sharedLibrary && souvenirs.isEmpty && trips.isEmpty
    }

    private var query: String? { searchText.normalizedForDisplay?.localizedLowercase }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                switch state {
                case .loading:
                    ProgressView("Syncing your shared library…")
                        .frame(maxWidth: .infinity).padding(.vertical, 88)
                case .empty:
                    GalleryEmptyShelf(onAdd: onAdd)
                case .populated:
                    browsingControls
                    if searchPresented { searchField }
                    switch segment {
                    case .items: shelf
                    case .trips: tripList
                    case .places: placeList
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification, object: persistence.container)) { note in
            guard needsImportCheck,
                  let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import,
                  event.storeIdentifier == (try? persistence.persistentStore(for: .sharedLibrary).identifier) else { return }
            if event.endDate == nil { sharedImportFinished = false }
            importRevision += 1
        }
        .task(id: needsImportCheck ? importRevision : -1) {
            guard needsImportCheck else { return }
            let finished = await persistence.hasFinishedSharedImport(since: shareAcceptanceStartedAt)
            if !Task.isCancelled { sharedImportFinished = finished }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                libraryTitle
                Spacer(minLength: 4)
                headerActions
            }
            VStack(alignment: .leading, spacing: 10) {
                libraryTitle
                headerActions
            }
        }
        .padding(.bottom, 12)
    }

    private var libraryTitle: some View {
        Text("Our Library")
            .font(.system(.largeTitle, design: .serif, weight: .medium))
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(.isHeader)
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            if state == .populated { GalleryAddButton(title: "Add", action: onAdd) }
            Button { onOpen(.settings) } label: {
                Image(systemName: "gearshape").font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Library settings")
        }
    }

    private var browsingControls: some View {
        HStack(spacing: 4) {
            if typeSize.isAccessibilitySize {
                Menu {
                    Picker("Browse library", selection: $segment) {
                        ForEach(LibrarySegment.allCases, id: \.self) { tab in
                            Text(tab.galleryTitle).tag(tab)
                        }
                    }
                } label: {
                    Label(segment.galleryTitle, systemImage: "chevron.down")
                        .labelStyle(.titleAndIcon)
                }
            } else {
                ForEach(LibrarySegment.allCases, id: \.self) { tab in
                    Button { segment = tab } label: {
                        Text(tab.galleryTitle)
                            .font(.subheadline.weight(segment == tab ? .bold : .medium))
                            .foregroundStyle(segment == tab ? GalleryTheme.accent : GalleryTheme.secondary)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 5)
                            .overlay(alignment: .bottom) {
                                if segment == tab { Capsule().fill(GalleryTheme.accent).frame(height: 2) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(segment == tab ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
            Button {
                searchPresented.toggle()
                if searchPresented { searchFocused = true } else { searchText = "" }
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(searchPresented ? GalleryTheme.accent : GalleryTheme.ink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(searchPresented ? "Close search" : "Search library")
            if segment == .items {
                Menu {
                    Picker("Filter souvenirs", selection: $filter) {
                        ForEach(LibraryItemFilter.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                } label: {
                    Image(systemName: filter == .none ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(filter == .none ? GalleryTheme.ink : GalleryTheme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Filter souvenirs")
                .accessibilityValue(filter.title)
            }
        }
        .font(.body)
        .overlay(alignment: .bottom) { Rectangle().fill(GalleryTheme.rule).frame(height: 0.5).accessibilityHidden(true) }
        .onChange(of: segment) { _, _ in searchFocused = false }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(GalleryTheme.secondary).accessibilityHidden(true)
            TextField("Search \(segment.galleryTitle.lowercased())", text: $searchText)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 46)
        .background(GalleryTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 12)
        .onAppear { searchFocused = true }
    }

    @ViewBuilder private var shelf: some View {
        let matches = souvenirs.filter { souvenir in
            filter.matches(souvenir) && (query.map { souvenir.matchesLibrarySearch(query: $0) } ?? true)
        }
        let featured = filter == .none && query == nil ? matches.first : nil
        let remaining = featured == nil ? matches[...] : matches.dropFirst()
        if let featured {
            souvenirButton(featured, featured: true).padding(.top, 20)
        }
        if !remaining.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(filter != .none ? filter.title : query == nil ? "On the shelf" : "Search results")
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(remaining.count.formatted())
                    .font(.subheadline.monospacedDigit()).foregroundStyle(GalleryTheme.secondary)
                    .accessibilityLabel(remaining.count == 1 ? "1 souvenir" : "\(remaining.count) souvenirs")
            }
            .padding(.top, 22).padding(.bottom, 12)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .topLeading),
                                count: typeSize.isAccessibilitySize ? 1 : 2)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 19) {
                ForEach(remaining, id: \.objectID) { souvenir in souvenirButton(souvenir, featured: false) }
            }
        } else if featured == nil {
            if query != nil {
                GalleryNotice("No matching souvenirs", "Try a different name, place, trip, or story.", icon: "magnifyingglass")
            } else if filter == .needsInfo {
                GalleryNotice("Everything is filled in", "Your souvenirs have a name, trip, and place.", icon: "checkmark.circle")
            } else if filter == .onThisDay {
                GalleryNotice("No anniversaries today", "Souvenirs acquired on this date will appear here.", icon: "calendar")
            } else {
                GalleryNotice("No souvenirs yet", "Add a souvenir to start filling your shelf.", icon: "photo")
            }
        }
    }

    private func souvenirButton(_ souvenir: Souvenir, featured: Bool) -> some View {
        Button {
            if let id = souvenir.id { onOpen(.souvenir(id)) }
        } label: {
            GallerySouvenirView(souvenir: souvenir, featured: featured)
        }
        .buttonStyle(.plain)
        .disabled(souvenir.id == nil)
        .accessibilityIdentifier(featured ? "gallery.featured" : "gallery.tile")
    }

    @ViewBuilder private var tripList: some View {
        let visible = trips.filter { trip in query.map { trip.matchesLibrarySearch(query: $0) } ?? true }
        if visible.isEmpty {
            GalleryNotice(query == nil ? "No trips yet" : "No matching trips",
                          query == nil ? "Assign a souvenir to a trip to find it here." : "Try another trip name or date.", icon: "suitcase")
        } else {
            let metrics = tripMetrics
            LazyVStack(spacing: 0) {
                ForEach(visible, id: \.objectID) { trip in
                    let summary = trip.id.flatMap { metrics[$0] } ?? .empty
                    Button {
                        if let id = trip.id { onOpen(.trip(id)) }
                    } label: {
                        GalleryBrowseRow(title: trip.displayTitle, detail: trip.dateRangeSummary, count: summary.souvenirCount,
                                         thumbnail: summary.coverThumbnailData, symbol: "suitcase")
                    }
                    .buttonStyle(.plain).disabled(trip.id == nil)
                }
            }
        }
    }

    private var tripMetrics: [UUID: LibraryTripMetrics] {
        var metrics: [UUID: LibraryTripMetrics] = [:]
        for souvenir in souvenirs {
            guard let trip = souvenir.trip, trip.deletedAt == nil, let id = trip.id else { continue }
            var entry = metrics[id] ?? .empty
            entry.souvenirCount += 1
            if entry.coverThumbnailData == nil { entry.coverThumbnailData = souvenir.primaryThumbnailData }
            metrics[id] = entry
        }
        return metrics
    }

    @ViewBuilder private var placeList: some View {
        let places = PlacePresentationLogic.groups(from: souvenirs.compactMap(\.placeCandidate))
            .filter { place in query.map { place.matchesLibrarySearch(query: $0) } ?? true }
        if places.isEmpty {
            GalleryNotice(query == nil ? "No places yet" : "No matching places",
                          query == nil ? "Places come from where you got each souvenir." : "Try another place or country.", icon: "mappin")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(places) { place in
                    Button { onOpen(.place(place.key)) } label: {
                        GalleryBrowseRow(title: place.title, detail: nil, count: place.souvenirCount,
                                         thumbnail: place.thumbnailData, symbol: "mappin")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private extension LibrarySegment {
    var galleryTitle: String { self == .items ? "Souvenirs" : title }
}

private struct GallerySouvenirView: View {
    @ObservedObject var souvenir: Souvenir
    let featured: Bool

    var body: some View {
        let location = souvenir.galleryLocation ?? souvenir.visibleTripTitle
        let story = souvenir.story.flatMap { $0.galleryStoryExcerpt }
        GalleryObject(title: souvenir.displayTitle, location: location, story: story, featured: featured) {
            if let photo = souvenir.galleryPhoto {
                GalleryPhoto(photo: photo, featured: featured)
            } else {
                GalleryPlaceholder(symbol: "photo")
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

private enum LibraryItemFilter: CaseIterable {
    case none
    case onThisDay
    case needsInfo

    var title: String {
        switch self {
        case .none: "All souvenirs"
        case .needsInfo: "Needs Info"
        case .onThisDay: "On This Day"
        }
    }

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
    case loading
    case empty
    case populated

    static func resolve(
        souvenirCount: Int,
        tripCount: Int,
        awaitingImport: Bool = false
    ) -> LibraryContentState {
        guard souvenirCount == 0 && tripCount == 0 else { return .populated }
        return awaitingImport ? .loading : .empty
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
            galleryLocation,
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

    var galleryLocation: String? {
        let country = gotItInCountryCode.normalizedDisplayValue
        let name = country.flatMap { $0.count == 2 ? Locale.current.localizedString(forRegionCode: $0.uppercased()) : $0 }
        return PlacePresentationLogic.displayTitle(name: gotItInName, city: gotItInCity, country: name ?? country)
    }

    var galleryPhoto: PhotoAsset? {
        sortedPhotoAssets.first { $0.thumbnailData != nil || $0.displayImageData != nil }
    }

    var primaryThumbnailData: Data? {
        let photos = sortedPhotoAssets
        if let thumb = photos.lazy.compactMap(\.thumbnailData).first { return thumb }
        guard let display = photos.lazy.compactMap(\.displayImageData).first else { return nil }
        return GalleryPhoto.downsample(display, maxPixels: 320)?.jpegData(compressionQuality: 0.8)
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
