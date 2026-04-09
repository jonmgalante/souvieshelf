import CloudKit
import SwiftUI
import UIKit

struct PartnerShareSheet: UIViewControllerRepresentable {
    let shareControllerContext: LibraryShareControllerContext
    let onLifecycleChange: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            shareControllerContext: shareControllerContext,
            onLifecycleChange: onLifecycleChange,
            onError: onError
        )
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: shareControllerContext.share,
            container: shareControllerContext.container
        )
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UICloudSharingController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let shareControllerContext: LibraryShareControllerContext
        private let onLifecycleChange: () -> Void
        private let onError: (String) -> Void

        init(
            shareControllerContext: LibraryShareControllerContext,
            onLifecycleChange: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.shareControllerContext = shareControllerContext
            self.onLifecycleChange = onLifecycleChange
            self.onError = onError
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            shareControllerContext.libraryTitle
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            onError(error.localizedDescription)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onLifecycleChange()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onLifecycleChange()
        }
    }
}
