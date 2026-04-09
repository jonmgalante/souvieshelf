import XCTest
@testable import SouvieShelf

final class SettingsScreenTests: XCTestCase {
    func testOwnerWithoutPartnerShowsInvitePartnerAction() {
        let presentation = SettingsPartnerPresentation.resolve(
            shareSummary: ShareSummary(
                libraryName: "Our Library",
                shareExists: false,
                ownerDisplayName: "You",
                participantCount: 1,
                isOwner: true,
                partnerState: .none
            ),
            activeLibraryContext: ActiveLibraryContext.previewInviteSent.with(
                partnerState: .none,
                isOwner: true
            )
        )

        XCTAssertEqual(presentation.title, "No partner connected")
        XCTAssertEqual(presentation.action, .invitePartner)
    }

    func testOwnerWithConnectedPartnerShowsManagePartnerAction() {
        let presentation = SettingsPartnerPresentation.resolve(
            shareSummary: ShareSummary(
                libraryName: "Our Library",
                shareExists: true,
                ownerDisplayName: "You",
                participantCount: 2,
                isOwner: true,
                partnerState: .connected(displayName: "Taylor")
            ),
            activeLibraryContext: ActiveLibraryContext.previewInviteSent.with(
                partnerState: .connected(displayName: "Taylor"),
                isOwner: true
            )
        )

        XCTAssertEqual(presentation.title, "Connected with Taylor")
        XCTAssertEqual(presentation.action, .managePartner)
    }

    func testParticipantNeverShowsOwnerOnlyPartnerAction() {
        let presentation = SettingsPartnerPresentation.resolve(
            shareSummary: ShareSummary(
                libraryName: "Our Library",
                shareExists: true,
                ownerDisplayName: "Taylor",
                participantCount: 2,
                isOwner: false,
                partnerState: .connected(displayName: "Taylor")
            ),
            activeLibraryContext: ActiveLibraryContext.previewConnected
        )

        XCTAssertEqual(presentation.title, "Shared by Taylor")
        XCTAssertNil(presentation.action)
    }
}

private extension ActiveLibraryContext {
    func with(
        partnerState: PartnerConnectionState,
        isOwner: Bool
    ) -> ActiveLibraryContext {
        ActiveLibraryContext(
            libraryID: libraryID,
            storeScope: isOwner ? .privateLibrary : storeScope,
            libraryTitle: libraryTitle,
            partnerState: partnerState,
            isOwner: isOwner,
            shareSummary: shareSummary
        )
    }
}
