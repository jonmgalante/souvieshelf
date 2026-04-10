import XCTest
@testable import SouvieShelf

final class LibraryScreenTests: XCTestCase {
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
