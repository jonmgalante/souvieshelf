import CoreData
import UIKit
import XCTest
@testable import SouvieShelf

final class LibraryScreenTests: XCTestCase {
    @MainActor
    func testTripCoverFallsBackToAnAvailablePhotoInTheObjectsPhotoOrder() throws {
        let persistence = try PersistenceController.inMemory()
        let context = persistence.viewContext
        let item = NSEntityDescription.insertNewObject(forEntityName: "Souvenir", into: context) as! Souvenir
        func photo(_ index: Int16) -> PhotoAsset {
            let photo = NSEntityDescription.insertNewObject(forEntityName: "PhotoAsset", into: context) as! PhotoAsset
            photo.id = UUID()
            photo.sortIndex = index
            photo.souvenir = item
            return photo
        }
        let primary = photo(2)
        primary.isPrimary = true
        primary.thumbnailData = Data([0, 1])
        let secondary = photo(1)
        XCTAssertNil(item.galleryPhoto)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { $0.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
        secondary.displayImageData = image
        XCTAssertEqual(item.galleryPhoto, secondary)
        XCTAssertNotNil(item.primaryThumbnailData.flatMap { UIImage(data: $0) })
        primary.displayImageData = image
        XCTAssertEqual(item.galleryPhoto, primary)
        XCTAssertEqual(item.orderedPhotos, [primary, secondary])
        XCTAssertNotNil(item.primaryThumbnailData.flatMap { UIImage(data: $0) })
    }

    func testAnniversariesUseAnEarlierAcquisitionYearAndTheLocalCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        func instant(_ text: String) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: text)) }
        let day = try instant("2024-03-01T02:00:00Z") // February 29 in New York
        XCTAssertTrue(GalleryDailyFeature.isAnniversary(try instant("2020-02-29T18:00:00Z"), on: day, calendar: calendar))
        for date in [nil, day, try instant("2028-02-29T18:00:00Z"), try instant("2020-03-01T18:00:00Z")] {
            XCTAssertFalse(GalleryDailyFeature.isAnniversary(date, on: day, calendar: calendar))
        }
    }

    @MainActor
    func testFeatureStaysStableForTheDayRotatesAndPrioritizesTheRealAnniversary() throws {
        let persistence = try PersistenceController.inMemory()
        let context = persistence.viewContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 12)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        func souvenir(_ story: String?) -> Souvenir {
            let object = NSEntityDescription.insertNewObject(forEntityName: "Souvenir", into: context) as! Souvenir
            object.id = UUID()
            object.story = story
            return object
        }
        let first = souvenir("From the potter's workshop")
        let second = souvenir(nil)
        let trip = NSEntityDescription.insertNewObject(forEntityName: "Trip", into: context) as! Trip
        trip.title = "Amalfi Coast"
        second.trip = trip
        let plain = souvenir(nil)
        let pool = [plain, first, second]
        let selected = try XCTUnwrap(GalleryDailyFeature.pick(from: pool, on: today, calendar: calendar))
        XCTAssertNotEqual(selected, plain)
        first.updatedAt = Date.now
        XCTAssertEqual(GalleryDailyFeature.pick(from: pool.reversed(), on: today.addingTimeInterval(3600), calendar: calendar), selected)
        XCTAssertNotEqual(GalleryDailyFeature.pick(from: pool, on: tomorrow, calendar: calendar), selected)
        plain.acquiredDate = calendar.date(byAdding: .year, value: -3, to: today)
        XCTAssertEqual(GalleryDailyFeature.pick(from: pool, on: today, calendar: calendar), plain)
        plain.deletedAt = today
        XCTAssertEqual(GalleryDailyFeature.pick(from: pool, on: today, calendar: calendar), selected)
        XCTAssertNil(GalleryDailyFeature.pick(from: [], on: today, calendar: calendar))
    }

    @MainActor
    func testTripBrowseOrderIncludesUnmappedObjectsAndExcludesRemovedAndOtherTrips() async throws {
        let dependencies = AppDependencies.preview(scenario: .ready)
        let persistence = dependencies.persistenceController
        guard case .ready(let active) = await dependencies.bootstrapRepository.resolveLaunchContext() else {
            return XCTFail("Expected the test library")
        }
        let context = persistence.viewContext
        let library = try XCTUnwrap(context.fetch(Library.fetchRequest()).first)
        let store = try persistence.persistentStore(for: active.storeScope)
        func makeTrip() -> Trip {
            let trip = NSEntityDescription.insertNewObject(forEntityName: "Trip", into: context) as! Trip
            trip.id = UUID()
            trip.library = library
            context.assign(trip, to: store)
            return trip
        }
        let trip = makeTrip()
        let other = makeTrip()
        let date = Date.now
        func add(_ number: Int, to trip: Trip) -> Souvenir {
            let item = NSEntityDescription.insertNewObject(forEntityName: "Souvenir", into: context) as! Souvenir
            item.id = UUID(uuidString: String(format: "A0000000-0000-4000-8000-%012d", number))
            item.library = library
            item.trip = trip
            item.createdAt = date
            item.updatedAt = date
            context.assign(item, to: store)
            return item
        }
        let withoutPin = add(2, to: trip)
        let withPin = add(1, to: trip)
        withPin.gotItInLatitude = 40.6491
        withPin.gotItInLongitude = 14.6115
        add(3, to: trip).deletedAt = date
        _ = add(4, to: other)
        try context.save()
        let request = TripDetailFetchRequestFactory.souvenirs(tripID: try XCTUnwrap(trip.id),
            activeLibraryContext: active, persistenceController: persistence)
        XCTAssertEqual(try context.fetch(request), [withPin, withoutPin])
        let map = dependencies.mapRepository.souvenirFetchRequest(for: .trip(try XCTUnwrap(trip.id), storeScope: active.storeScope),
                                                                   activeLibraryContext: active)
        XCTAssertEqual(try context.fetch(map), [withPin])
        withoutPin.trip = other
        try context.save()
        XCTAssertEqual(try context.fetch(request), [withPin])
    }

    @MainActor
    func testLibraryDetailRequestsSupportLiveObservation() async throws {
        let dependencies = AppDependencies.preview(scenario: .ready)
        let persistence = dependencies.persistenceController
        let launch = await dependencies.bootstrapRepository.resolveLaunchContext()
        guard case .ready(let library) = launch else { return XCTFail("Expected a seeded library") }

        func observe<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws {
            // An empty descriptor list raises an Objective-C exception at navigation time.
            XCTAssertFalse(request.sortDescriptors?.isEmpty ?? true)
            guard request.sortDescriptors?.isEmpty == false else { return }
            let controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: persistence.viewContext,
                                                        sectionNameKeyPath: nil, cacheName: nil)
            try controller.performFetch()
        }
        try observe(SouvenirDetailFetchRequestFactory.make(souvenirID: UUID(), activeLibraryContext: library, persistenceController: persistence))
        try observe(TripDetailFetchRequestFactory.trip(tripID: UUID(), activeLibraryContext: library, persistenceController: persistence))
    }

    func testGoalMockupChromeMatchesReference() {
        let goal = LibraryMockupReferences.goal

        XCTAssertEqual(goal.statusTime, "9:41")
        XCTAssertEqual(goal.wordmark, "SouvieShelf")
        XCTAssertEqual(goal.avatarAsset, .avatar)
        XCTAssertEqual(goal.selectedScope, .personal)
        XCTAssertEqual(goal.availableScopes, [.personal, .shared])
        XCTAssertEqual(goal.searchPlaceholder, "Search souvenirs, places, trips, tags...")
        XCTAssertEqual(goal.addButton, LibraryMockupButtonSpec(title: "Add", icon: .add))
        XCTAssertEqual(
            goal.bottomTabs,
            [
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

    func testGoalMockupTopRibbonMatchesReference() {
        let goal = LibraryMockupReferences.goal

        XCTAssertEqual(
            goal.topRibbonItems.map(\.title),
            ["Recent Trip", "On This Day", "Trips", "Collections", "Tags", "Needs Info"]
        )
        XCTAssertEqual(
            goal.topRibbonItems.map(\.subtitle),
            ["Amalfi Coast", "Mar 28", "12", "8", "24", "3"]
        )

        guard case .image(let asset) = goal.topRibbonItems[0].artwork else {
            return XCTFail("Expected the Recent Trip ribbon item to use an image asset.")
        }
        XCTAssertEqual(asset, .recentTripAmalfi)

        guard case .symbol(let icon, let accent) = goal.topRibbonItems[5].artwork else {
            return XCTFail("Expected the Needs Info ribbon item to use an SF Symbol.")
        }
        XCTAssertEqual(icon, .warning)
        XCTAssertEqual(accent, .amber)
    }

    func testGoalMockupGridItemsMatchReference() {
        let goal = LibraryMockupReferences.goal

        XCTAssertEqual(
            goal.gridItems.map(\.asset),
            [.mug, .plate, .kyoto, .rugs, .camel, .lantern, .bottle, .bowl, .pouch]
        )

        XCTAssertEqual(goal.gridItems[0].title, nil)
        XCTAssertEqual(goal.gridItems[0].subtitle, nil)

        XCTAssertEqual(goal.gridItems[1].title, "Positano, Italy")
        XCTAssertEqual(goal.gridItems[1].subtitle, "May 2024")

        XCTAssertEqual(goal.gridItems[4].badge, .shared)

        XCTAssertEqual(goal.gridItems[6].title, "Marrakech, Morocco")
        XCTAssertEqual(goal.gridItems[6].subtitle, "Apr 2024")

        XCTAssertTrue(goal.gridItems[7].isSelected)
        XCTAssertEqual(goal.gridItems[8].badge, .needsInfo)
    }

    func testExtractedLibraryHomeBundleOmitsSegmentedControl() {
        let demo = LibraryHomePreviewFixture.extractedDemo

        XCTAssertFalse(demo.segmentedControlPresent)
        XCTAssertFalse(LibraryHomeDesign.Source.segmentedControlPresent)
        XCTAssertTrue(LibraryHomeDesign.Source.mockDeviceChromePresentInExport)
    }

    func testExtractedLibraryHomeAssetsCoverRequiredBundleImages() {
        XCTAssertEqual(LibraryHomeAsset.avatarProfile.extractedID, "avatar-profile")
        XCTAssertEqual(LibraryHomeAsset.featureRecentTripAmalfiCoast.extractedID, "feature-recent-trip-amalfi-coast")
        XCTAssertEqual(
            LibraryHomeAsset.gridAssets.map(\.extractedID),
            [
                "grid-01-blue-ceramic-mug",
                "grid-02-positano-lemon-plate",
                "grid-03-kyoto-poster",
                "grid-04-folded-rugs",
                "grid-05-wooden-camel",
                "grid-06-moroccan-lantern",
                "grid-07-marrakech-bottle",
                "grid-08-selected-bowl",
                "grid-09-wallet-needs-info"
            ]
        )
    }

    func testExtractedLibraryHomePreviewContentMatchesVisibleBundle() {
        let demo = LibraryHomePreviewFixture.extractedDemo

        XCTAssertEqual(demo.wordmarkText, "SouvieShelf")
        XCTAssertEqual(demo.addButtonLabel, "Add")
        XCTAssertEqual(demo.searchPlaceholder, "Search souvenirs, places, trips, tags...")
        XCTAssertEqual(
            demo.featureRibbonItems.map(\.title),
            ["Recent Trip", "On This Day", "Trips", "Collections", "Tags", "Needs Info"]
        )
        XCTAssertEqual(
            demo.featureRibbonItems.map(\.secondaryText),
            ["Amalfi Coast", "Mar 28", "12", "8", "24", "3"]
        )
        XCTAssertEqual(
            demo.gridCards.map(\.asset),
            [
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
        )
        XCTAssertEqual(demo.gridCards[1].overlay?.title, "Positano, Italy")
        XCTAssertEqual(demo.gridCards[1].overlay?.subtitle, "May 2024")
        XCTAssertEqual(demo.gridCards[4].badge?.text, "Shared")
        XCTAssertEqual(demo.gridCards[4].badge?.placement, .bottomCenter)
        XCTAssertTrue(demo.gridCards[7].isSelected)
        XCTAssertEqual(demo.gridCards[8].badge?.text, "Needs Info")
        XCTAssertEqual(demo.gridCards[8].badge?.placement, .bottomRight)
        XCTAssertEqual(
            demo.bottomTabs,
            [
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

    func testGalleryStoryExcerptHandlesMissingTextAndLongStories() throws {
        XCTAssertNil("  \n ".galleryStoryExcerpt)
        XCTAssertEqual("  A cup\n from Ravello. ".galleryStoryExcerpt, "A cup from Ravello.")
        let longStory = String(repeating: "We remembered the little shop. ", count: 12)
        let excerpt = try XCTUnwrap(longStory.galleryStoryExcerpt)
        XCTAssertLessThanOrEqual(excerpt.count, 141)
        XCTAssertTrue(excerpt.hasSuffix("…"))
        XCTAssertTrue(longStory.hasPrefix(excerpt.dropLast() + " "))
    }

    func testSharedImportDoesNotPresentAnEmptyShelfUntilComplete() {
        XCTAssertEqual(LibraryContentState.resolve(souvenirCount: 0, tripCount: 0, awaitingImport: true), .loading)
        XCTAssertEqual(LibraryContentState.resolve(souvenirCount: 0, tripCount: 0, awaitingImport: false), .empty)
    }

    func testCachedContentIsBrowsableDuringSharedImport() {
        XCTAssertEqual(LibraryContentState.resolve(souvenirCount: 1, tripCount: 0, awaitingImport: true), .populated)
        XCTAssertEqual(LibraryContentState.resolve(souvenirCount: 0, tripCount: 1, awaitingImport: true), .populated)
    }

    func testContentStateIsEmptyWhenSouvenirsAndTripsAreBothMissing() {
        let state = LibraryContentState.resolve(
            souvenirCount: 0,
            tripCount: 0
        )

        XCTAssertEqual(state, .empty)
    }

    func testContentStateIsPopulatedWhenSouvenirsExist() {
        let state = LibraryContentState.resolve(
            souvenirCount: 1,
            tripCount: 0
        )

        XCTAssertEqual(state, .populated)
    }

    func testContentStateIsPopulatedWhenTripsExist() {
        let state = LibraryContentState.resolve(
            souvenirCount: 0,
            tripCount: 1
        )

        XCTAssertEqual(state, .populated)
    }

    func testOwnerWithoutPartnerShowsInviteBanner() {
        let bannerState = LibraryOwnerShareBannerState.resolve(
            isOwner: true,
            partnerState: .none
        )

        XCTAssertEqual(bannerState, .invitePartner)
    }

    func testOwnerWithPendingInviteShowsPendingBanner() {
        let bannerState = LibraryOwnerShareBannerState.resolve(
            isOwner: true,
            partnerState: .inviteSent
        )

        XCTAssertEqual(bannerState, .invitePending)
    }

    func testOwnerWithConnectedPartnerHidesInviteBanner() {
        let bannerState = LibraryOwnerShareBannerState.resolve(
            isOwner: true,
            partnerState: .connected(displayName: "Taylor")
        )

        XCTAssertNil(bannerState)
    }

    func testParticipantNeverShowsOwnerInviteBanner() {
        let bannerState = LibraryOwnerShareBannerState.resolve(
            isOwner: false,
            partnerState: .connected(displayName: "Taylor")
        )

        XCTAssertNil(bannerState)
    }
}
