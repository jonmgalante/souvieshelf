import Foundation

enum AppRoute: Hashable, Sendable {
    case souvenir(UUID)
    case trip(UUID)
    case tripSouvenir(tripID: UUID, souvenirID: UUID)
    case tripMap(UUID)
    case place(PlaceKey)
    case settings
    case recentlyDeleted

    var title: String {
        switch self {
        case .souvenir, .tripSouvenir:
            "Souvenir"
        case .trip:
            "Trip"
        case .tripMap:
            "Trip map"
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
        case .souvenir, .tripSouvenir:
            "shippingbox.fill"
        case .trip:
            "suitcase.rolling.fill"
        case .tripMap:
            "map"
        case .place:
            "mappin.and.ellipse"
        case .settings:
            "gearshape"
        case .recentlyDeleted:
            "trash"
        }
    }
}
