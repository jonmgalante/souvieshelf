import SwiftUI
import UIKit

/// Mirrors the extracted `Design/Extracted/LibraryHome` bundle without changing the current
/// production Library UI.
///
/// Developer entry points:
/// - Extracted asset namespace: `App/Media.xcassets/LibraryHome...`
/// - App-local extracted tokens/layout: `LibraryHomeDesign`
/// - Preview/demo fixture: `LibraryHomePreviewFixture.extractedDemo`
/// - Follow-up work: implement the actual Library Home screen in a later prompt using these
///   resources instead of re-extracting values from the design bundle.
enum LibraryHomeAsset: String, CaseIterable, Sendable {
    case avatarProfile = "LibraryHomeAvatarProfile"
    case featureRecentTripAmalfiCoast = "LibraryHomeFeatureRecentTripAmalfiCoast"
    case grid01BlueCeramicMug = "LibraryHomeGrid01BlueCeramicMug"
    case grid02PositanoLemonPlate = "LibraryHomeGrid02PositanoLemonPlate"
    case grid03KyotoPoster = "LibraryHomeGrid03KyotoPoster"
    case grid04FoldedRugs = "LibraryHomeGrid04FoldedRugs"
    case grid05WoodenCamel = "LibraryHomeGrid05WoodenCamel"
    case grid06MoroccanLantern = "LibraryHomeGrid06MoroccanLantern"
    case grid07MarrakechBottle = "LibraryHomeGrid07MarrakechBottle"
    case grid08SelectedBowl = "LibraryHomeGrid08SelectedBowl"
    case grid09WalletNeedsInfo = "LibraryHomeGrid09WalletNeedsInfo"

    static let gridAssets: [LibraryHomeAsset] = [
        .grid01BlueCeramicMug,
        .grid02PositanoLemonPlate,
        .grid03KyotoPoster,
        .grid04FoldedRugs,
        .grid05WoodenCamel,
        .grid06MoroccanLantern,
        .grid07MarrakechBottle,
        .grid08SelectedBowl,
        .grid09WalletNeedsInfo
    ]

    var image: Image {
        Image(rawValue)
    }

    var assetName: String {
        rawValue
    }

    var extractedID: String {
        switch self {
        case .avatarProfile:
            "avatar-profile"
        case .featureRecentTripAmalfiCoast:
            "feature-recent-trip-amalfi-coast"
        case .grid01BlueCeramicMug:
            "grid-01-blue-ceramic-mug"
        case .grid02PositanoLemonPlate:
            "grid-02-positano-lemon-plate"
        case .grid03KyotoPoster:
            "grid-03-kyoto-poster"
        case .grid04FoldedRugs:
            "grid-04-folded-rugs"
        case .grid05WoodenCamel:
            "grid-05-wooden-camel"
        case .grid06MoroccanLantern:
            "grid-06-moroccan-lantern"
        case .grid07MarrakechBottle:
            "grid-07-marrakech-bottle"
        case .grid08SelectedBowl:
            "grid-08-selected-bowl"
        case .grid09WalletNeedsInfo:
            "grid-09-wallet-needs-info"
        }
    }

    var sourceFileName: String {
        "\(extractedID).jpg"
    }
}

enum LibraryHomeIcon: CaseIterable, Sendable {
    case search
    case mic
    case onThisDay
    case trips
    case collections
    case tags
    case needsInfo
    case sharedBadge
    case needsInfoBadge
    case libraryTab
    case mapTab
    case addPlus

    var systemName: String {
        switch self {
        case .search:
            "magnifyingglass"
        case .mic:
            "mic"
        case .onThisDay:
            "calendar"
        case .trips:
            "briefcase"
        case .collections:
            "square.grid.2x2"
        case .tags:
            "tag"
        case .needsInfo, .needsInfoBadge:
            "exclamationmark.circle"
        case .sharedBadge:
            "person.2"
        case .libraryTab:
            "books.vertical"
        case .mapTab:
            "mappin"
        case .addPlus:
            "plus"
        }
    }

    var sourceName: String {
        switch self {
        case .search:
            "Search"
        case .mic:
            "Mic"
        case .onThisDay:
            "Calendar"
        case .trips:
            "Briefcase"
        case .collections:
            "LayoutGrid"
        case .tags:
            "Tag"
        case .needsInfo, .needsInfoBadge:
            "AlertCircle"
        case .sharedBadge:
            "Users"
        case .libraryTab:
            "Library"
        case .mapTab:
            "MapPin"
        case .addPlus:
            "+"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .search, .mic:
            17
        case .onThisDay, .trips, .collections, .tags, .needsInfo:
            20
        case .sharedBadge:
            11
        case .needsInfoBadge:
            10
        case .libraryTab, .mapTab:
            23
        case .addPlus:
            15
        }
    }
}

enum LibraryHomeAccent: String, Equatable, Sendable {
    case teal
    case amber
}

enum LibraryHomeDesign {
    enum Source {
        static let segmentedControlPresent = false
        static let mockDeviceChromePresentInExport = true
    }

    enum Colors {
        static let outerCanvas = Color(uiColor: UIColor(hex: 0xE6DED2))
        static let searchFieldFill = outerCanvas
        static let phoneSurface = Color(uiColor: UIColor(hex: 0xF1E9DD))
        static let elevatedSurface = Color(uiColor: UIColor(hex: 0xF7F1E7))
        static let textPrimary = Color(uiColor: UIColor(hex: 0x3F403F))
        static let textMuted = Color(uiColor: UIColor(hex: 0x8D8B86))
        static let textInverse = Color(uiColor: UIColor(hex: 0xFDFBF8))
        static let textInverseSecondary = Color(uiColor: UIColor(hex: 0xFDFBF8, alpha: 0.75))
        static let terracotta = Color(uiColor: UIColor(hex: 0xA95D41))
        static let teal = Color(uiColor: UIColor(hex: 0x497174))
        static let amber = Color(uiColor: UIColor(hex: 0xC49147))
        static let inactiveIcon = Color(uiColor: UIColor(hex: 0x6E6E6B))
        static let subtleBorder = Color(uiColor: UIColor(hex: 0xE9DFD2))
        static let ribbonShadow = Color(uiColor: UIColor(hex: 0x000000, alpha: 0.05))
        static let overlayTextShadow = Color(uiColor: UIColor(hex: 0x000000, alpha: 0.40))
        static let positanoGradientStart = Color(uiColor: UIColor(hex: 0x000000, alpha: 0.52))
        static let marrakechGradientStart = Color(uiColor: UIColor(hex: 0x000000, alpha: 0.55))
        static let overlayGradientEnd = Color(uiColor: UIColor(hex: 0x000000, alpha: 0))
    }

    enum Typography {
        static let wordmarkSize: CGFloat = 26
        static let wordmarkTracking: CGFloat = 1.04
        static let buttonLabelSize: CGFloat = 14
        static let searchPlaceholderSize: CGFloat = 14
        static let featureTitleSize: CGFloat = 10
        static let featureSecondarySize: CGFloat = 10
        static let overlayTitleSize: CGFloat = 11
        static let overlaySubtitleSize: CGFloat = 10
        static let badgeLabelSize: CGFloat = 10
        static let tabLabelSize: CGFloat = 11

        /// The extracted bundle specifies Cormorant Garamond Regular at 26pt. The export did not
        /// include a local font file, so this resolves a bundled Cormorant face if one is added
        /// later and currently falls back to the system serif face.
        static func wordmarkFont(relativeTo textStyle: Font.TextStyle = .title2) -> Font {
            let size = wordmarkSize
            let candidates = [
                "CormorantGaramond-Regular",
                "Cormorant Garamond Regular",
                "Cormorant Garamond",
                "CormorantGaramond-Medium",
                "Cormorant Garamond Medium"
            ]

            guard let matchedName = candidates.first(where: { UIFont(name: $0, size: size) != nil }) else {
                return .system(size: size, weight: .regular, design: .serif)
            }

            return .custom(matchedName, size: size, relativeTo: textStyle)
        }
    }

    enum Spacing {
        static let contentInsetX: CGFloat = 16
        static let statusInsetX: CGFloat = 20
        static let statusInsetTop: CGFloat = 17
        static let statusToHeader: CGFloat = 4
        static let headerToSearch: CGFloat = 14
        static let searchToRibbon: CGFloat = 12
        static let ribbonToGrid: CGFloat = 10
        static let searchPaddingX: CGFloat = 14
        static let searchPaddingY: CGFloat = 11
        static let searchInnerGap: CGFloat = 10
        static let ribbonPaddingX: CGFloat = 10
        static let ribbonPaddingTop: CGFloat = 14
        static let ribbonPaddingBottom: CGFloat = 12
        static let featureItemGap: CGFloat = 6
        static let gridGap: CGFloat = 4
        static let overlayInset: CGFloat = 8
        static let badgeGap: CGFloat = 4
        static let bottomBarTopPadding: CGFloat = 10
        static let bottomBarBottomPadding: CGFloat = 12
        static let bottomBarItemGap: CGFloat = 4
        static let homeIndicatorBottomPadding: CGFloat = 8
        static let scrollContentBottomReserve: CGFloat = 96
    }

    enum Layout {
        static let frameWidth: CGFloat = 390
        static let frameHeight: CGFloat = 844
        static let headerHeight: CGFloat = 38
        static let avatarSize: CGFloat = 38
        static let addButtonHeight: CGFloat = 37
        static let addButtonInnerGap: CGFloat = 5
        static let addButtonLeadingPadding: CGFloat = 14
        static let addButtonTrailingPadding: CGFloat = 16
        static let addButtonVerticalPadding: CGFloat = 8
        static let searchFieldHeight: CGFloat = 43
        static let searchIconSize: CGFloat = 17
        static let ribbonHeight: CGFloat = 106
        static let ribbonItemWidth: CGFloat = 56.333
        static let ribbonItemHeight: CGFloat = 80
        static let ribbonCircleSize: CGFloat = 48
        static let gridColumnCount = 3
        static let gridCardWidth: CGFloat = 116.667
        static let gridCardHeight: CGFloat = 116.667
        static let gridCardAspectRatio: CGFloat = 1
        static let sharedBadgeHeight: CGFloat = 23
        static let needsInfoBadgeHeight: CGFloat = 25
        static let sharedBadgeLeadingPadding: CGFloat = 8
        static let sharedBadgeTrailingPadding: CGFloat = 9
        static let needsInfoBadgeLeadingPadding: CGFloat = 7
        static let needsInfoBadgeTrailingPadding: CGFloat = 8
        static let bottomTabIconSize: CGFloat = 23
        static let homeIndicatorWidth: CGFloat = 134
        static let homeIndicatorHeight: CGFloat = 5
    }

    enum CornerRadius {
        static let fullPill: CGFloat = 999
        static let featureRibbon: CGFloat = 16
        static let gridCard: CGFloat = 12
    }

    enum Border {
        static let subtleWidth: CGFloat = 1
        static let needsInfoBadgeWidth: CGFloat = 1
        static let selectedCardOutlineWidth: CGFloat = 2.5
        static let selectedCardOutlineInsetOffset: CGFloat = -1.5
    }

    enum Shadow {
        static let ribbonRadius: CGFloat = 4
        static let ribbonYOffset: CGFloat = 1
        static let overlayTextRadius: CGFloat = 3
        static let overlayTextYOffset: CGFloat = 1
    }
}

struct LibraryHomePreviewFixture: Equatable, Sendable {
    let statusTime: String
    let wordmarkText: String
    let addButtonLabel: String
    let addButtonLeadingGlyph: String
    let searchPlaceholder: String
    let segmentedControlPresent: Bool
    let featureRibbonItems: [LibraryHomeFeatureItem]
    let gridCards: [LibraryHomeGridCard]
    let bottomTabs: [LibraryHomeBottomTab]

    /// Preview/demo only. Do not seed this into persistence or use it as production content.
    static let extractedDemo = LibraryHomePreviewFixture(
        statusTime: "9:41",
        wordmarkText: "SouvieShelf",
        addButtonLabel: "Add",
        addButtonLeadingGlyph: "+",
        searchPlaceholder: "Search souvenirs, places, trips, tags...",
        segmentedControlPresent: LibraryHomeDesign.Source.segmentedControlPresent,
        featureRibbonItems: [
            LibraryHomeFeatureItem(
                id: "recentTrip",
                title: "Recent Trip",
                secondaryText: "Amalfi Coast",
                count: nil,
                artwork: .asset(.featureRecentTripAmalfiCoast),
                accent: nil,
                isEmphasized: false
            ),
            LibraryHomeFeatureItem(
                id: "onThisDay",
                title: "On This Day",
                secondaryText: "Mar 28",
                count: nil,
                artwork: .icon(.onThisDay),
                accent: .teal,
                isEmphasized: false
            ),
            LibraryHomeFeatureItem(
                id: "trips",
                title: "Trips",
                secondaryText: "12",
                count: 12,
                artwork: .icon(.trips),
                accent: .teal,
                isEmphasized: false
            ),
            LibraryHomeFeatureItem(
                id: "collections",
                title: "Collections",
                secondaryText: "8",
                count: 8,
                artwork: .icon(.collections),
                accent: .teal,
                isEmphasized: false
            ),
            LibraryHomeFeatureItem(
                id: "tags",
                title: "Tags",
                secondaryText: "24",
                count: 24,
                artwork: .icon(.tags),
                accent: .teal,
                isEmphasized: false
            ),
            LibraryHomeFeatureItem(
                id: "needsInfo",
                title: "Needs Info",
                secondaryText: "3",
                count: 3,
                artwork: .icon(.needsInfo),
                accent: .amber,
                isEmphasized: true
            )
        ],
        gridCards: [
            LibraryHomeGridCard(
                asset: .grid01BlueCeramicMug,
                overlay: nil,
                badge: nil,
                isSelected: false,
                sourceAnnotation: "Blue ceramic mug"
            ),
            LibraryHomeGridCard(
                asset: .grid02PositanoLemonPlate,
                overlay: .init(
                    placement: .bottomLeft,
                    title: "Positano, Italy",
                    subtitle: "May 2024"
                ),
                badge: nil,
                isSelected: false,
                sourceAnnotation: "Italian lemon plate"
            ),
            LibraryHomeGridCard(
                asset: .grid03KyotoPoster,
                overlay: nil,
                badge: nil,
                isSelected: false,
                sourceAnnotation: "Kyoto poster"
            ),
            LibraryHomeGridCard(
                asset: .grid04FoldedRugs,
                overlay: nil,
                badge: nil,
                isSelected: false,
                sourceAnnotation: "Folded rugs"
            ),
            LibraryHomeGridCard(
                asset: .grid05WoodenCamel,
                overlay: nil,
                badge: .init(
                    text: "Shared",
                    style: .shared,
                    placement: .bottomCenter,
                    icon: .sharedBadge
                ),
                isSelected: false,
                sourceAnnotation: "Wooden camel"
            ),
            LibraryHomeGridCard(
                asset: .grid06MoroccanLantern,
                overlay: nil,
                badge: nil,
                isSelected: false,
                sourceAnnotation: "Moroccan lantern"
            ),
            LibraryHomeGridCard(
                asset: .grid07MarrakechBottle,
                overlay: .init(
                    placement: .bottomLeft,
                    title: "Marrakech, Morocco",
                    subtitle: "Apr 2024"
                ),
                badge: nil,
                isSelected: false,
                sourceAnnotation: "Green glass bottle"
            ),
            LibraryHomeGridCard(
                asset: .grid08SelectedBowl,
                overlay: nil,
                badge: nil,
                isSelected: true,
                sourceAnnotation: "Blue white ceramic bowl"
            ),
            LibraryHomeGridCard(
                asset: .grid09WalletNeedsInfo,
                overlay: nil,
                badge: .init(
                    text: "Needs Info",
                    style: .needsInfo,
                    placement: .bottomRight,
                    icon: .needsInfoBadge
                ),
                isSelected: false,
                sourceAnnotation: "Embroidered wallet"
            )
        ],
        bottomTabs: [
            LibraryHomeBottomTab(
                id: "library",
                title: "Library",
                icon: .libraryTab,
                isSelected: true
            ),
            LibraryHomeBottomTab(
                id: "map",
                title: "Map",
                icon: .mapTab,
                isSelected: false
            )
        ]
    )
}

struct LibraryHomeFeatureItem: Identifiable, Equatable, Sendable {
    enum Artwork: Equatable, Sendable {
        case asset(LibraryHomeAsset)
        case icon(LibraryHomeIcon)
    }

    let id: String
    let title: String
    let secondaryText: String
    let count: Int?
    let artwork: Artwork
    let accent: LibraryHomeAccent?
    let isEmphasized: Bool
}

struct LibraryHomeGridCard: Identifiable, Equatable, Sendable {
    struct Overlay: Equatable, Sendable {
        enum Placement: String, Equatable, Sendable {
            case bottomLeft = "bottom-left"
        }

        let placement: Placement
        let title: String
        let subtitle: String
    }

    struct Badge: Equatable, Sendable {
        enum Style: String, Equatable, Sendable {
            case shared
            case needsInfo
        }

        enum Placement: String, Equatable, Sendable {
            case bottomCenter = "bottom-center"
            case bottomRight = "bottom-right"
        }

        let text: String
        let style: Style
        let placement: Placement
        let icon: LibraryHomeIcon
    }

    let asset: LibraryHomeAsset
    let overlay: Overlay?
    let badge: Badge?
    let isSelected: Bool
    let sourceAnnotation: String

    var id: String {
        asset.extractedID
    }
}

struct LibraryHomeBottomTab: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let icon: LibraryHomeIcon
    let isSelected: Bool
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
