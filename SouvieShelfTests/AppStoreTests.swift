import XCTest
@testable import SouvieShelf

@MainActor
final class AppStoreTests: XCTestCase {
    func testLaunchTransitionsToPairingWhenNoLibraryExists() async {
        let store = AppStore(dependencies: .preview(scenario: .pairing))

        await store.launchIfNeeded()

        XCTAssertEqual(store.phase, .pairing)
        XCTAssertNil(store.activeLibraryContext)
    }

    func testLaunchTransitionsToPairingWhenNoLibraryExistsAndICloudIsUnavailable() async {
        let store = AppStore(dependencies: .preview(scenario: .iCloudUnavailable))

        await store.launchIfNeeded()

        XCTAssertEqual(store.phase, .pairing)
        XCTAssertNil(store.activeLibraryContext)
    }

    func testAcceptedShareWaitsForItsRootEvenWhenAPrivateShelfExists() async throws {
        let dependencies = AppDependencies.preview(scenario: .ready)
        let store = AppStore(dependencies: dependencies)
        await store.launchIfNeeded()
        await store.waitForAcceptedLibrary()
        XCTAssertEqual(store.phase, .waitingForSharedLibrary)
        XCTAssertNil(store.activeLibraryContext)

        await store.retryLaunch()
        XCTAssertEqual(store.phase, .waitingForSharedLibrary)
        try dependencies.persistenceController.seedLibrary(title: "Our Library", scope: .sharedLibrary)
        await store.retryLaunch()
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.activeLibraryContext?.storeScope, .sharedLibrary)
    }

    func testCreateOurLibraryShowsICloudRequiredWhenICloudIsUnavailable() async {
        let store = AppStore(dependencies: .preview(scenario: .iCloudUnavailable))

        await store.launchIfNeeded()
        await store.createOurLibrary()

        XCTAssertEqual(store.phase, .iCloudUnavailable)
        XCTAssertNil(store.activeLibraryContext)
    }

    func testCreateOurLibraryTransitionsToReady() async {
        let store = AppStore(dependencies: .preview(scenario: .pairing))

        await store.launchIfNeeded()
        await store.createOurLibrary()

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.activeLibraryContext?.name, "Our Library")
        XCTAssertEqual(store.activeLibraryContext?.partnerConnectionState, PartnerConnectionState.none)
        XCTAssertEqual(store.activeLibraryContext?.storeScope, .privateLibrary)
        XCTAssertTrue(store.activeLibraryContext?.isOwner == true)
    }

    func testApplyShareSummaryUpdatesActiveLibraryContext() async {
        let store = AppStore(dependencies: .preview(scenario: .ready))

        await store.launchIfNeeded()
        store.applyShareSummary(
            ShareSummary(
                libraryName: "Our Library",
                shareExists: true,
                ownerDisplayName: "You",
                participantCount: 2,
                isOwner: true,
                partnerState: .connected(displayName: "Taylor")
            )
        )

        XCTAssertEqual(store.activeLibraryContext?.libraryTitle, "Our Library")
        XCTAssertEqual(store.activeLibraryContext?.partnerState, .connected(displayName: "Taylor"))
        XCTAssertEqual(store.activeLibraryContext?.shareSummary?.partnerState, .connected(displayName: "Taylor"))
        XCTAssertTrue(store.activeLibraryContext?.isOwner == true)
    }

    func testSelectingMapTabResetsToLibraryScopeAndClearsRoutes() async {
        let store = AppStore(dependencies: .preview(scenario: .ready))

        await store.launchIfNeeded()

        store.showMap(
            filterContext: .trip(
                UUID(),
                storeScope: .privateLibrary
            )
        )
        store.selectTab(.library)
        store.open(.settings)

        store.selectTab(.map)

        XCTAssertEqual(store.selectedTab, .map)
        XCTAssertTrue(store.mapFilterContext.isLibrary)
        XCTAssertEqual(store.mapFilterContext.storeScope, .privateLibrary)
        XCTAssertTrue(store.routePath.isEmpty)
    }
}
