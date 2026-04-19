import SwiftUI

enum LibraryMockupAssetName: String, CaseIterable, Sendable {
    case avatar = "GoalAvatar"
    case recentTripAmalfi = "GoalRecentTripAmalfi"
    case mug = "GoalMug"
    case plate = "GoalPlate"
    case kyoto = "GoalKyoto"
    case rugs = "GoalRugs"
    case camel = "GoalCamel"
    case lantern = "GoalLantern"
    case bottle = "GoalBottle"
    case bowl = "GoalBowl"
    case pouch = "GoalPouch"

    var image: Image {
        Image(rawValue)
    }

    var name: String {
        rawValue
    }
}

enum LibraryMockupScopeOption: String, CaseIterable, Identifiable, Sendable {
    case personal = "Personal"
    case shared = "Shared"

    var id: String {
        rawValue
    }
}

enum LibraryMockupAccent: Sendable {
    case teal
    case terracotta
    case amber
}

enum LibraryMockupIcon: String, Sendable {
    case search = "magnifyingglass"
    case microphone = "mic"
    case calendar = "calendar"
    case trips = "suitcase"
    case collections = "rectangle.stack"
    case tags = "tag"
    case warning = "exclamationmark.circle"
    case warningFilled = "exclamationmark.circle.fill"
    case libraryTab = "list.bullet.rectangle.portrait.fill"
    case mapTab = "mappin.and.ellipse"
    case add = "plus"
    case sharedBadge = "person.2.fill"

    var systemName: String {
        rawValue
    }
}

struct LibraryMockupTopRibbonItem: Identifiable, Equatable, Sendable {
    enum Artwork: Equatable, Sendable {
        case image(LibraryMockupAssetName)
        case symbol(LibraryMockupIcon, accent: LibraryMockupAccent)
    }

    let id: String
    let title: String
    let subtitle: String
    let artwork: Artwork
}

struct LibraryMockupBadgeSpec: Equatable, Sendable {
    let title: String
    let icon: LibraryMockupIcon?
    let accent: LibraryMockupAccent

    static let shared = LibraryMockupBadgeSpec(
        title: "Shared",
        icon: .sharedBadge,
        accent: .teal
    )

    static let needsInfo = LibraryMockupBadgeSpec(
        title: "Needs Info",
        icon: .warningFilled,
        accent: .amber
    )
}

struct LibraryMockupGridItem: Identifiable, Equatable, Sendable {
    let id: String
    let asset: LibraryMockupAssetName
    let title: String?
    let subtitle: String?
    let badge: LibraryMockupBadgeSpec?
    let isSelected: Bool
}

struct LibraryMockupButtonSpec: Equatable, Sendable {
    let title: String
    let icon: LibraryMockupIcon
}

struct LibraryMockupTabSpec: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let icon: LibraryMockupIcon
    let isSelected: Bool
}

struct LibraryMockupReference: Equatable, Sendable {
    let statusTime: String
    let wordmark: String
    let avatarAsset: LibraryMockupAssetName
    let selectedScope: LibraryMockupScopeOption
    let availableScopes: [LibraryMockupScopeOption]
    let searchPlaceholder: String
    let topRibbonItems: [LibraryMockupTopRibbonItem]
    let gridItems: [LibraryMockupGridItem]
    let addButton: LibraryMockupButtonSpec
    let bottomTabs: [LibraryMockupTabSpec]
}

enum LibraryMockupReferences {
    static let goal = LibraryMockupReference(
        statusTime: "9:41",
        wordmark: "SouvieShelf",
        avatarAsset: .avatar,
        selectedScope: .personal,
        availableScopes: LibraryMockupScopeOption.allCases,
        searchPlaceholder: "Search souvenirs, places, trips, tags...",
        topRibbonItems: [
            LibraryMockupTopRibbonItem(
                id: "recent-trip",
                title: "Recent Trip",
                subtitle: "Amalfi Coast",
                artwork: .image(.recentTripAmalfi)
            ),
            LibraryMockupTopRibbonItem(
                id: "on-this-day",
                title: "On This Day",
                subtitle: "Mar 28",
                artwork: .symbol(.calendar, accent: .teal)
            ),
            LibraryMockupTopRibbonItem(
                id: "trips",
                title: "Trips",
                subtitle: "12",
                artwork: .symbol(.trips, accent: .teal)
            ),
            LibraryMockupTopRibbonItem(
                id: "collections",
                title: "Collections",
                subtitle: "8",
                artwork: .symbol(.collections, accent: .teal)
            ),
            LibraryMockupTopRibbonItem(
                id: "tags",
                title: "Tags",
                subtitle: "24",
                artwork: .symbol(.tags, accent: .teal)
            ),
            LibraryMockupTopRibbonItem(
                id: "needs-info",
                title: "Needs Info",
                subtitle: "3",
                artwork: .symbol(.warning, accent: .amber)
            )
        ],
        gridItems: [
            LibraryMockupGridItem(
                id: "mug",
                asset: .mug,
                title: nil,
                subtitle: nil,
                badge: nil,
                isSelected: false
            ),
            LibraryMockupGridItem(
                id: "plate",
                asset: .plate,
                title: "Positano, Italy",
                subtitle: "May 2024",
                badge: nil,
                isSelected: false
            ),
            LibraryMockupGridItem(
                id: "kyoto",
                asset: .kyoto,
                title: nil,
                subtitle: nil,
                badge: nil,
                isSelected: false
            ),
            LibraryMockupGridItem(
                id: "rugs",
                asset: .rugs,
                title: nil,
                subtitle: nil,
                badge: nil,
                isSelected: false
            ),
            LibraryMockupGridItem(
                id: "camel",
                asset: .camel,
                title: nil,
                subtitle: nil,
                badge: .shared,
                isSelected: false
            ),
            LibraryMockupGridItem(
                id: "lantern",
                asset: .lantern,
                title: nil,
                subtitle: nil,
                badge: nil,
                isSelected: false
            ),
            LibraryMockupGridItem(
                id: "bottle",
                asset: .bottle,
                title: "Marrakech, Morocco",
                subtitle: "Apr 2024",
                badge: nil,
                isSelected: false
            ),
            LibraryMockupGridItem(
                id: "bowl",
                asset: .bowl,
                title: nil,
                subtitle: nil,
                badge: nil,
                isSelected: true
            ),
            LibraryMockupGridItem(
                id: "pouch",
                asset: .pouch,
                title: nil,
                subtitle: nil,
                badge: .needsInfo,
                isSelected: false
            )
        ],
        addButton: LibraryMockupButtonSpec(
            title: "Add",
            icon: .add
        ),
        bottomTabs: [
            LibraryMockupTabSpec(
                id: "library",
                title: "Library",
                icon: .libraryTab,
                isSelected: true
            ),
            LibraryMockupTabSpec(
                id: "map",
                title: "Map",
                icon: .mapTab,
                isSelected: false
            )
        ]
    )
}

struct LibraryMockupWordmark: View {
    var title: String = LibraryMockupReferences.goal.wordmark
    var size: CGFloat = 39

    var body: some View {
        Text(title)
            .font(AppFont.wordmark(size: size, relativeTo: .largeTitle))
            .foregroundStyle(AppTheme.libraryWordmarkText)
            .tracking(-1.0)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
