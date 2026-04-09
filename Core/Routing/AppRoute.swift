import Foundation

enum AppRoute: Hashable, Sendable {
    case souvenir(UUID)
    case trip(UUID)
    case place(PlaceKey)
    case settings
    case recentlyDeleted

    var title: String {
        switch self {
        case .souvenir:
            "Souvenir"
        case .trip:
            "Trip"
        case .place(let placeKey):
            placeKey.label
        case .settings:
            "Settings"
        case .recentlyDeleted:
            "Recently Deleted"
        }
    }

    var symbolName: String {
        switch self {
        case .souvenir:
            "shippingbox.fill"
        case .trip:
            "suitcase.rolling.fill"
        case .place:
            "mappin.and.ellipse"
        case .settings:
            "gearshape"
        case .recentlyDeleted:
            "trash"
        }
    }
}
