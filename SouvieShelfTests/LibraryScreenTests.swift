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
