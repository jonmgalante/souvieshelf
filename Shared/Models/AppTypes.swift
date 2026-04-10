import Foundation

enum StoreScope: String, CaseIterable, Codable, Sendable {
    case privateLibrary
    case sharedLibrary

    var configurationName: String {
        switch self {
        case .privateLibrary:
            "Private"
        case .sharedLibrary:
            "Shared"
        }
    }

    var isOwner: Bool {
        self == .privateLibrary
    }

    init?(configurationName: String) {
        switch configurationName {
        case StoreScope.privateLibrary.configurationName:
            self = .privateLibrary
        case StoreScope.sharedLibrary.configurationName:
            self = .sharedLibrary
        default:
            return nil
        }
    }
}

enum AppPhase: String, CaseIterable, Codable, Sendable {
    case launching
    case iCloudUnavailable
    case pairing
    case ready
}

enum MainTab: String, CaseIterable, Codable, Sendable {
    case library
    case map

    var title: String {
        switch self {
        case .library:
            "Library"
        case .map:
            "Map"
        }
    }

    var symbolName: String {
        switch self {
        case .library:
            "books.vertical.fill"
        case .map:
            "map.fill"
        }
    }
}

enum LibrarySegment: String, CaseIterable, Codable, Sendable {
    case items
    case trips
    case places

    var title: String {
        switch self {
        case .items:
            "Items"
        case .trips:
            "Trips"
        case .places:
            "Places"
        }
    }
}

struct MapFilterContext: Equatable, Codable, Sendable {
    var storeScope: StoreScope = .privateLibrary
    var tripID: UUID?
    var selectedPlace: PlaceKey?
    var includesSoftDeleted = false
}

extension MapFilterContext {
    static func library(storeScope: StoreScope) -> MapFilterContext {
        MapFilterContext(
            storeScope: storeScope,
            tripID: nil,
            selectedPlace: nil,
            includesSoftDeleted: false
        )
    }

    static func trip(
        _ tripID: UUID,
        storeScope: StoreScope
    ) -> MapFilterContext {
        MapFilterContext(
            storeScope: storeScope,
            tripID: tripID,
            selectedPlace: nil,
            includesSoftDeleted: false
        )
    }

    static func place(
        _ placeKey: PlaceKey,
        storeScope: StoreScope
    ) -> MapFilterContext {
        MapFilterContext(
            storeScope: storeScope,
            tripID: nil,
            selectedPlace: placeKey,
            includesSoftDeleted: false
        )
    }

    var isLibrary: Bool {
        tripID == nil && selectedPlace == nil
    }

    var identityKey: String {
        if let tripID {
            return "trip|\(storeScope.rawValue)|\(tripID.uuidString)"
        }

        if let selectedPlace {
            return "place|\(storeScope.rawValue)|\(selectedPlace.identifier)"
        }

        return "library|\(storeScope.rawValue)"
    }
}

enum PartnerConnectionState: Equatable, Codable, Sendable {
    case none
    case inviteSent
    case connected(displayName: String?)

    var statusText: String {
        switch self {
        case .none:
            "Invite Partner anytime"
        case .inviteSent:
            "Invite pending"
        case .connected(let displayName):
            if let displayName, !displayName.isEmpty {
                "Connected with \(displayName)"
            } else {
                "Connected with your partner"
            }
        }
    }

    var displayName: String? {
        switch self {
        case .connected(let displayName):
            displayName
        case .none, .inviteSent:
            nil
        }
    }
}

struct PlaceKey: Hashable, Codable, Sendable {
    var identifier: String
    var label: String
    var latitude: Double?
    var longitude: Double?
}

struct PlaceDraft: Equatable, Codable, Sendable {
    var title: String
    var locality: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
}

extension PlaceDraft {
    var displayTitle: String {
        let title = PlaceDisplayFormatter.normalized(title) ?? ""
        let locality = PlaceDisplayFormatter.normalized(locality)
        let country = PlaceDisplayFormatter.normalized(country)

        if let locality,
           title.caseInsensitiveCompare(locality) != .orderedSame {
            return title.isEmpty ? locality : "\(title), \(locality)"
        }

        if !title.isEmpty {
            return title
        }

        if let locality {
            return locality
        }

        if let country {
            return country
        }

        return "Unnamed place"
    }

    var displaySubtitle: String? {
        let locality = PlaceDisplayFormatter.normalized(locality)
        let country = PlaceDisplayFormatter.normalized(country)

        switch (locality, country) {
        case let (locality?, country?):
            return "\(locality), \(country)"
        case let (locality?, nil):
            return locality
        case let (nil, country?):
            return country
        case (nil, nil):
            return nil
        }
    }
}

struct PlaceCandidate: Equatable, Sendable {
    let name: String?
    let city: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let thumbnailData: Data?
}

struct PlaceGroup: Identifiable, Equatable, Sendable {
    let id: String
    let key: PlaceKey
    let title: String
    let souvenirCount: Int
    let thumbnailData: Data?
}

enum PlacePresentationLogic {
    static func groups(from candidates: [PlaceCandidate]) -> [PlaceGroup] {
        var buckets: [String: Bucket] = [:]

        for candidate in candidates {
            guard let descriptor = descriptor(
                name: candidate.name,
                city: candidate.city,
                country: candidate.country
            ) else {
                continue
            }

            var bucket = buckets[descriptor.identifier] ?? Bucket(
                descriptor: descriptor,
                souvenirCount: 0,
                latitude: nil,
                longitude: nil,
                thumbnailData: nil
            )
            bucket.souvenirCount += 1

            if bucket.thumbnailData == nil {
                bucket.thumbnailData = candidate.thumbnailData
            }

            if bucket.latitude == nil || bucket.longitude == nil,
               let latitude = candidate.latitude,
               let longitude = candidate.longitude {
                bucket.latitude = latitude
                bucket.longitude = longitude
            }

            buckets[descriptor.identifier] = bucket
        }

        return buckets.values
            .map { bucket in
                let key = PlaceKey(
                    identifier: bucket.descriptor.identifier,
                    label: bucket.descriptor.label,
                    latitude: bucket.latitude,
                    longitude: bucket.longitude
                )
                return PlaceGroup(
                    id: key.identifier,
                    key: key,
                    title: key.label,
                    souvenirCount: bucket.souvenirCount,
                    thumbnailData: bucket.thumbnailData
                )
            }
            .sorted { lhs, rhs in
                if lhs.souvenirCount != rhs.souvenirCount {
                    return lhs.souvenirCount > rhs.souvenirCount
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    static func placeKey(
        name: String?,
        city: String?,
        country: String?,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> PlaceKey? {
        guard let descriptor = descriptor(
            name: name,
            city: city,
            country: country
        ) else {
            return nil
        }

        return PlaceKey(
            identifier: descriptor.identifier,
            label: descriptor.label,
            latitude: latitude,
            longitude: longitude
        )
    }

    static func displayTitle(
        name: String?,
        city: String?,
        country: String?
    ) -> String? {
        placeKey(
            name: name,
            city: city,
            country: country
        )?.label
    }

    static func matches(
        placeKey: PlaceKey,
        name: String?,
        city: String?,
        country: String?
    ) -> Bool {
        self.placeKey(
            name: name,
            city: city,
            country: country
        )?.identifier == placeKey.identifier
    }

    private static func descriptor(
        name: String?,
        city: String?,
        country: String?
    ) -> Descriptor? {
        let resolvedName = PlaceDisplayFormatter.normalized(name)
        let resolvedCity = PlaceDisplayFormatter.normalized(city)
        let resolvedCountry = PlaceDisplayFormatter.normalized(country)

        if let resolvedCity,
           let resolvedCountry {
            return Descriptor(
                identifier: "city|\(PlaceDisplayFormatter.identifierValue(resolvedCity))|country|\(PlaceDisplayFormatter.identifierValue(resolvedCountry))",
                label: "\(resolvedCity), \(resolvedCountry)"
            )
        }

        if resolvedCity == nil,
           let resolvedName,
           let resolvedCountry {
            return Descriptor(
                identifier: "name|\(PlaceDisplayFormatter.identifierValue(resolvedName))|country|\(PlaceDisplayFormatter.identifierValue(resolvedCountry))",
                label: "\(resolvedName), \(resolvedCountry)"
            )
        }

        if let resolvedCountry {
            return Descriptor(
                identifier: "country|\(PlaceDisplayFormatter.identifierValue(resolvedCountry))",
                label: resolvedCountry
            )
        }

        if let resolvedCity {
            return Descriptor(
                identifier: "city|\(PlaceDisplayFormatter.identifierValue(resolvedCity))",
                label: resolvedCity
            )
        }

        if let resolvedName {
            return Descriptor(
                identifier: "name|\(PlaceDisplayFormatter.identifierValue(resolvedName))",
                label: resolvedName
            )
        }

        return nil
    }

    private struct Descriptor: Equatable, Sendable {
        let identifier: String
        let label: String
    }

    private struct Bucket: Equatable, Sendable {
        let descriptor: Descriptor
        var souvenirCount: Int
        var latitude: Double?
        var longitude: Double?
        var thumbnailData: Data?
    }
}

private enum PlaceDisplayFormatter {
    static func normalized(_ value: String?) -> String? {
        let collapsed = value?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard let collapsed,
              !collapsed.isEmpty else {
            return nil
        }

        return collapsed
    }

    static func identifierValue(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

struct ShareSummary: Equatable, Codable, Sendable {
    var libraryName: String
    var shareExists: Bool
    var ownerDisplayName: String?
    var participantCount: Int
    var isOwner: Bool
    var partnerState: PartnerConnectionState
}

struct ActiveLibraryContext: Equatable, Codable, Sendable {
    var libraryID: UUID
    var storeScope: StoreScope
    var libraryTitle: String
    var partnerState: PartnerConnectionState
    var isOwner: Bool
    var shareSummary: ShareSummary?

    var id: UUID { libraryID }
    var name: String { libraryTitle }
    var partnerConnectionState: PartnerConnectionState { partnerState }

    static let previewConnected = ActiveLibraryContext(
        libraryID: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
        storeScope: .sharedLibrary,
        libraryTitle: "Our Library",
        partnerState: .connected(displayName: "Partner"),
        isOwner: false,
        shareSummary: ShareSummary(
            libraryName: "Our Library",
            shareExists: true,
            ownerDisplayName: "Partner",
            participantCount: 2,
            isOwner: false,
            partnerState: .connected(displayName: "Partner")
        )
    )

    static let previewInviteSent = ActiveLibraryContext(
        libraryID: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
        storeScope: .privateLibrary,
        libraryTitle: "Our Library",
        partnerState: .inviteSent,
        isOwner: true,
        shareSummary: ShareSummary(
            libraryName: "Our Library",
            shareExists: true,
            ownerDisplayName: "You",
            participantCount: 1,
            isOwner: true,
            partnerState: .inviteSent
        )
    )
}

struct CreateSouvenirInput: Equatable, Codable, Sendable {
    var libraryContext: ActiveLibraryContext
    var id: UUID
    var tripID: UUID?
    var title: String?
    var story: String?
    var acquiredOn: Date?
    var gotItInPlace: PlaceDraft?
    var fromPlace: PlaceDraft?
    var photos: [ImportedPhoto]
}

// Edit flow saves the full current souvenir form state. Optional scalar fields therefore mean
// "clear this field" rather than "leave it unchanged."
struct UpdateSouvenirInput: Equatable, Codable, Sendable {
    var libraryContext: ActiveLibraryContext
    var souvenirID: UUID
    var tripID: UUID?
    var title: String?
    var story: String?
    var acquiredOn: Date?
    var gotItInPlace: PlaceDraft?
    var fromPlace: PlaceDraft?
    var photoOrder: [UUID]
    var addedPhotos: [ImportedPhoto]
    var primaryPhotoID: UUID
}

struct CreateTripInput: Equatable, Codable, Sendable {
    var libraryContext: ActiveLibraryContext
    var id: UUID
    var title: String
    var destinationSummary: String?
    var startDate: Date?
    var endDate: Date?
}

struct UpdateTripInput: Equatable, Codable, Sendable {
    var libraryContext: ActiveLibraryContext
    var tripID: UUID
    var title: String
    var destinationSummary: String?
    var startDate: Date?
    var endDate: Date?
}

struct MapSouvenirRecord: Equatable, Sendable {
    var souvenirID: UUID
    var title: String?
    var acquiredDate: Date?
    var updatedAt: Date?
    var tripID: UUID?
    var tripTitle: String?
    var tripDeletedAt: Date?
    var gotItInName: String?
    var gotItInCity: String?
    var gotItInCountry: String?
    var latitude: Double
    var longitude: Double
    var thumbnailData: Data?
}

struct SouvenirMapAnnotation: Identifiable, Equatable, Codable, Sendable {
    var souvenirID: UUID
    var title: String
    var subtitle: String?
    var tripTitle: String?
    var placeSummary: String?
    var thumbnailData: Data?
    var latitude: Double
    var longitude: Double

    var id: UUID { souvenirID }
}

struct MapEmptyStateContent: Equatable, Sendable {
    var icon: String
    var title: String
    var message: String
}

enum MapPresentationLogic {
    static func annotations(
        from records: [MapSouvenirRecord],
        filterContext: MapFilterContext
    ) -> [SouvenirMapAnnotation] {
        records
            .filter { includes($0, in: filterContext) }
            .compactMap(annotation(from:))
            .sorted { lhs, rhs in
                let lhsTitle = lhs.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                let rhsTitle = rhs.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

                if lhsTitle != rhsTitle {
                    return lhsTitle < rhsTitle
                }

                return lhs.souvenirID.uuidString < rhs.souvenirID.uuidString
            }
    }

    static func contextTitle(
        for filterContext: MapFilterContext,
        tripTitle: String?
    ) -> String {
        if let selectedPlace = filterContext.selectedPlace {
            return selectedPlace.label
        }

        if filterContext.tripID != nil {
            return normalized(tripTitle) ?? "Trip"
        }

        return "All Souvenirs"
    }

    static func emptyState(
        for filterContext: MapFilterContext,
        tripTitle: String?
    ) -> MapEmptyStateContent {
        if let selectedPlace = filterContext.selectedPlace {
            return MapEmptyStateContent(
                icon: "mappin.and.ellipse",
                title: "No souvenir locations yet.",
                message: "\(selectedPlace.label) doesn't have any saved souvenir locations in this library yet."
            )
        }

        if filterContext.tripID != nil {
            let resolvedTripTitle = normalized(tripTitle) ?? "This trip"
            return MapEmptyStateContent(
                icon: "map",
                title: "No souvenir locations yet.",
                message: "\(resolvedTripTitle) has no saved souvenir locations yet."
            )
        }

        return MapEmptyStateContent(
            icon: "map",
            title: "No souvenir locations yet.",
            message: "Add souvenirs with a \"Got it in\" location to see them on the map."
        )
    }

    private static func includes(
        _ record: MapSouvenirRecord,
        in filterContext: MapFilterContext
    ) -> Bool {
        if let tripID = filterContext.tripID,
           record.tripID != tripID {
            return false
        }

        if let selectedPlace = filterContext.selectedPlace,
           !PlacePresentationLogic.matches(
               placeKey: selectedPlace,
               name: record.gotItInName,
               city: record.gotItInCity,
               country: record.gotItInCountry
           ) {
            return false
        }

        return true
    }

    private static func annotation(
        from record: MapSouvenirRecord
    ) -> SouvenirMapAnnotation? {
        guard let coordinate = coordinate(
            latitude: record.latitude,
            longitude: record.longitude
        ) else {
            return nil
        }

        let visibleTripTitle = record.tripDeletedAt == nil ? normalized(record.tripTitle) : nil
        let placeSummary = PlacePresentationLogic.displayTitle(
            name: record.gotItInName,
            city: record.gotItInCity,
            country: record.gotItInCountry
        )

        return SouvenirMapAnnotation(
            souvenirID: record.souvenirID,
            title: normalized(record.title) ?? "Untitled souvenir",
            subtitle: visibleTripTitle ?? placeSummary,
            tripTitle: visibleTripTitle,
            placeSummary: placeSummary,
            thumbnailData: record.thumbnailData,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private static func coordinate(
        latitude: Double,
        longitude: Double
    ) -> (latitude: Double, longitude: Double)? {
        guard latitude.isFinite,
              longitude.isFinite,
              latitude >= -90,
              latitude <= 90,
              longitude >= -180,
              longitude <= 180,
              latitude != 0 || longitude != 0 else {
            return nil
        }

        return (latitude, longitude)
    }

    private static func normalized(_ value: String?) -> String? {
        let collapsed = value?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed?.isEmpty == false ? collapsed : nil
    }
}
