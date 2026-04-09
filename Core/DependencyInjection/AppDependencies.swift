import SwiftUI

enum AppBootstrapScenario: Sendable {
    case iCloudUnavailable
    case pairing
    case ready
}

struct AppDependencies {
    let persistenceController: PersistenceController
    let bootstrapRepository: any BootstrapRepository
    let libraryRepository: any LibraryRepository
    let sharingRepository: any SharingRepository
    let souvenirRepository: any SouvenirRepository
    let tripRepository: any TripRepository
    let deletedRepository: any DeletedRepository
    let mapRepository: any MapRepository
    let permissionCoordinator: any PermissionCoordinating
    let photoImporter: any PhotoImporting
    let locationSuggester: any LocationSuggesting

    @MainActor
    static func live() -> AppDependencies {
        // XCTest launches the app target before tests can inject dependencies. Keep the host app
        // on in-memory stores so unit tests validate repository behavior without requiring live
        // CloudKit capabilities in the simulator test runner.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return preview(scenario: .pairing)
        }

        do {
            let persistenceController = try PersistenceController.live()
            let repositoryBackend = PersistenceBackedAppBackend(
                persistenceController: persistenceController,
                iCloudStatusProvider: CloudKitICloudStatusProvider(
                    containerIdentifier: persistenceController.configuration.cloudKitContainerIdentifier
                )
            )

            return makeDependencies(
                persistenceController: persistenceController,
                repositoryBackend: repositoryBackend,
                permissionCoordinator: LivePermissionCoordinator(),
                photoImporter: LivePhotoImportService(),
                locationSuggester: LiveLocationSuggestionService()
            )
        } catch {
            fatalError("Failed to initialize persistence: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func preview(scenario: AppBootstrapScenario = .pairing) -> AppDependencies {
        do {
            let persistenceController = try PersistenceController.inMemory()
            if scenario == .ready {
                try persistenceController.seedLibrary(title: "Our Library", scope: .privateLibrary)
            }

            let repositoryBackend = PersistenceBackedAppBackend(
                persistenceController: persistenceController,
                iCloudStatusProvider: FixedICloudStatusProvider(
                    fixedStatus: scenario == .iCloudUnavailable ? .unavailable : .available
                )
            )

            return makeDependencies(
                persistenceController: persistenceController,
                repositoryBackend: repositoryBackend,
                permissionCoordinator: PreviewPermissionCoordinator(),
                photoImporter: PreviewPhotoImportService(),
                locationSuggester: PreviewLocationSuggestionService()
            )
        } catch {
            fatalError("Failed to initialize preview persistence: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func makeDependencies(
        persistenceController: PersistenceController,
        repositoryBackend: PersistenceBackedAppBackend,
        permissionCoordinator: any PermissionCoordinating,
        photoImporter: any PhotoImporting,
        locationSuggester: any LocationSuggesting
    ) -> AppDependencies {
        AppDependencies(
            persistenceController: persistenceController,
            bootstrapRepository: repositoryBackend,
            libraryRepository: repositoryBackend,
            sharingRepository: repositoryBackend,
            souvenirRepository: repositoryBackend,
            tripRepository: repositoryBackend,
            deletedRepository: repositoryBackend,
            mapRepository: repositoryBackend,
            permissionCoordinator: permissionCoordinator,
            photoImporter: photoImporter,
            locationSuggester: locationSuggester
        )
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let dependencies: AppDependencies
    let appStore: AppStore

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.appStore = AppStore(dependencies: dependencies)
    }

    static func live() -> AppEnvironment {
        AppEnvironment(dependencies: .live())
    }

    static func preview(_ scenario: AppBootstrapScenario) -> AppEnvironment {
        AppEnvironment(dependencies: .preview(scenario: scenario))
    }
}
