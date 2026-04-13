import XCTest
@testable import SouvieShelf

final class LibraryScreenTests: XCTestCase {
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
