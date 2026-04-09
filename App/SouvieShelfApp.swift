import CloudKit
import CoreData
import OSLog
import SwiftUI
import UIKit

@MainActor
final class IncomingCloudKitShareCoordinator {
    static let shared = IncomingCloudKitShareCoordinator()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SouvieShelf",
        category: "CloudKitShareIngress"
    )
    private var pendingMetadata: [CKShare.Metadata] = []
    private var handler: ((CKShare.Metadata) -> Void)?

    private init() {}

    func register(_ handler: @escaping (CKShare.Metadata) -> Void) {
        self.handler = handler

        guard !pendingMetadata.isEmpty else { return }

        let bufferedMetadata = pendingMetadata
        pendingMetadata.removeAll()
        logger.info("Draining \(bufferedMetadata.count, privacy: .public) buffered CloudKit share acceptance event(s).")
        bufferedMetadata.forEach(handler)
    }

    func enqueue(_ metadata: CKShare.Metadata) {
        logger.info(
            "Queued CloudKit share metadata for container \(metadata.containerIdentifier, privacy: .public)."
        )

        guard let handler else {
            pendingMetadata.append(metadata)
            return
        }

        handler(metadata)
    }
}

final class SouvieShelfAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SouvieShelfSceneDelegate.self
        return configuration
    }
}

final class SouvieShelfSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            IncomingCloudKitShareCoordinator.shared.enqueue(cloudKitShareMetadata)
        }
    }
}

@main
struct SouvieShelfApp: App {
    @UIApplicationDelegateAdaptor(SouvieShelfAppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            LaunchGateScreen(store: environment.appStore)
                .environmentObject(environment)
                .environment(
                    \.managedObjectContext,
                    environment.dependencies.persistenceController.viewContext
                )
                .tint(AppTheme.accentPrimary)
        }
    }
}
