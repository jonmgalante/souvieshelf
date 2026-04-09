import CloudKit
import OSLog
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var phase: AppPhase = .launching
    @Published private(set) var activeLibraryContext: ActiveLibraryContext?
    @Published var selectedTab: MainTab = .library
    @Published var routePath: [AppRoute] = []
    @Published var isShowingAddSheet = false
    @Published var joinInformation: String?
    @Published var mapFilterContext = MapFilterContext.library(storeScope: .privateLibrary)

    private let dependencies: AppDependencies
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SouvieShelf",
        category: "AppState"
    )
    private var hasBootstrapped = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        IncomingCloudKitShareCoordinator.shared.register { [weak self] metadata in
            guard let self else { return }
            Task { @MainActor [weak self] in
                await self?.handleIncomingShareMetadata(metadata)
            }
        }
    }

    func launchIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await refreshLaunchState()
    }

    func retryLaunch() async {
        await refreshLaunchState()
    }

    func refreshAfterSharingLifecycleChange() async {
        await refreshLaunchState()
    }

    func applyShareSummary(_ summary: ShareSummary) {
        guard var activeLibraryContext else {
            return
        }

        activeLibraryContext.libraryTitle = summary.libraryName
        activeLibraryContext.partnerState = summary.partnerState
        activeLibraryContext.isOwner = summary.isOwner || activeLibraryContext.storeScope == .privateLibrary
        activeLibraryContext.shareSummary = summary
        self.activeLibraryContext = activeLibraryContext
    }

    func createOurLibrary() async {
        do {
            let context = try await dependencies.libraryRepository.createOurLibrary()
            applyReadyState(context)
        } catch {
            joinInformation = "Couldn't create Our Library yet. Try again."
        }
    }

    func showJoinLibraryPlaceholder() {
        joinInformation = "Open your partner's invite link from Messages or Mail on this iPhone. SouvieShelf will join the shared library and reopen here."
    }

    func selectTab(_ tab: MainTab) {
        routePath.removeAll()

        if tab == .map {
            let storeScope = activeLibraryContext?.storeScope ?? mapFilterContext.storeScope
            mapFilterContext = .library(storeScope: storeScope)
        }

        selectedTab = tab
    }

    func showMap(filterContext: MapFilterContext) {
        routePath.removeAll()
        mapFilterContext = filterContext
        selectedTab = .map
    }

    func presentAddSheet() {
        isShowingAddSheet = true
    }

    func dismissAddSheet() {
        isShowingAddSheet = false
    }

    func open(_ route: AppRoute) {
        routePath.append(route)
    }

    private func refreshLaunchState() async {
        switch await dependencies.bootstrapRepository.resolveLaunchContext() {
        case .iCloudUnavailable:
            activeLibraryContext = nil
            phase = .iCloudUnavailable
        case .needsPairing:
            activeLibraryContext = nil
            phase = .pairing
        case .ready(let activeLibraryContext):
            applyReadyState(activeLibraryContext)
        }
    }

    private func handleIncomingShareMetadata(_ metadata: CKShare.Metadata) async {
        logger.info(
            "Received CloudKit share metadata for container \(metadata.containerIdentifier, privacy: .public)."
        )

        hasBootstrapped = true
        phase = .launching
        joinInformation = "Joining your shared library..."

        do {
            try await dependencies.bootstrapRepository.acceptShare(metadata: metadata)
            await refreshLaunchState()

            if activeLibraryContext?.storeScope != .sharedLibrary {
                logger.warning("Share acceptance completed but the shared library is not resolved yet.")
                joinInformation = "Your shared library was accepted, but it is still syncing to this iPhone. Retry in a moment if it does not appear automatically."
                phase = .pairing
            }
        } catch {
            logger.error("Failed accepting incoming CloudKit share metadata: \(error.localizedDescription, privacy: .public)")
            activeLibraryContext = nil
            joinInformation = error.localizedDescription
            phase = .pairing
        }
    }

    private func applyReadyState(_ context: ActiveLibraryContext) {
        activeLibraryContext = context
        mapFilterContext = .library(storeScope: context.storeScope)
        joinInformation = nil
        selectedTab = .library
        phase = .ready
    }
}
