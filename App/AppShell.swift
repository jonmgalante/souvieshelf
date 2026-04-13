import SwiftUI

struct AppShell: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var store: AppStore

    var body: some View {
        NavigationStack(path: $store.routePath) {
            currentScreen
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .appScreenBackground()
        .appNavigationChrome()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShellTabBar(
                selectedTab: store.selectedTab,
                onLibraryTap: { store.selectTab(.library) },
                onMapTap: { store.selectTab(.map) }
            )
        }
        .sheet(isPresented: $store.isShowingAddSheet) {
            if let activeLibraryContext = store.activeLibraryContext {
                AddSouvenirSheet(
                    activeLibraryContext: activeLibraryContext,
                    dependencies: environment.dependencies,
                    onSaved: { store.dismissAddSheet() }
                )
            } else {
                AddUnavailableSheet(onDismiss: { store.dismissAddSheet() })
            }
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch store.selectedTab {
        case .library:
            LibraryScreen(store: store)
        case .map:
            if let activeLibraryContext = store.activeLibraryContext {
                MapScreen(
                    filterContext: store.mapFilterContext,
                    activeLibraryContext: activeLibraryContext,
                    mapRepository: environment.dependencies.mapRepository,
                    onOpenRoute: { route in
                        store.open(route)
                    }
                )
            } else {
                StateMessageView(
                    icon: "map",
                    title: "Map Still Loading",
                    message: "SouvieShelf is still resolving your active library before it can show saved souvenir locations."
                )
                .padding(AppSpacing.large)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .souvenir(let souvenirID):
            if let activeLibraryContext = store.activeLibraryContext {
                SouvenirDetailScreen(
                    souvenirID: souvenirID,
                    activeLibraryContext: activeLibraryContext,
                    dependencies: environment.dependencies,
                    onOpenRoute: { nextRoute in
                        store.open(nextRoute)
                    }
                )
            } else {
                RouteUnavailableScreen(route: route)
            }
        case .trip(let tripID):
            if let activeLibraryContext = store.activeLibraryContext {
                TripDetailScreen(
                    tripID: tripID,
                    activeLibraryContext: activeLibraryContext,
                    dependencies: environment.dependencies,
                    onOpenRoute: { nextRoute in
                        store.open(nextRoute)
                    },
                    onViewOnMap: {
                        store.showMap(
                            filterContext: .trip(
                                tripID,
                                storeScope: activeLibraryContext.storeScope
                            )
                        )
                    }
                )
            } else {
                RouteUnavailableScreen(route: route)
            }
        case .place(let placeKey):
            if let activeLibraryContext = store.activeLibraryContext {
                PlaceDetailScreen(
                    placeKey: placeKey,
                    activeLibraryContext: activeLibraryContext,
                    persistenceController: environment.dependencies.persistenceController,
                    onOpenRoute: { nextRoute in
                        store.open(nextRoute)
                    },
                    onViewOnMap: {
                        store.showMap(
                            filterContext: .place(
                                placeKey,
                                storeScope: activeLibraryContext.storeScope
                            )
                        )
                    }
                )
            } else {
                RouteUnavailableScreen(route: route)
            }
        case .settings:
            SettingsScreen(store: store)
        case .recentlyDeleted:
            if let activeLibraryContext = store.activeLibraryContext {
                RecentlyDeletedScreen(
                    activeLibraryContext: activeLibraryContext,
                    dependencies: environment.dependencies
                )
            } else {
                StateMessageView(
                    icon: "trash",
                    title: "Recently Deleted Unavailable",
                    message: "SouvieShelf is still resolving your active library before it can show deleted items."
                )
                .padding(AppSpacing.large)
                .navigationTitle("Recently Deleted")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct ShellTabBar: View {
    let selectedTab: MainTab
    let onLibraryTap: () -> Void
    let onMapTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppTheme.libraryBorder.opacity(0.9))
                .frame(height: 1)

            HStack(spacing: AppSpacing.medium) {
                TabBarButton(
                    title: MainTab.library.title,
                    symbolName: "list.bullet.rectangle.portrait.fill",
                    isSelected: selectedTab == .library,
                    action: onLibraryTap
                )

                TabBarButton(
                    title: MainTab.map.title,
                    symbolName: "mappin.and.ellipse",
                    isSelected: selectedTab == .map,
                    action: onMapTap
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(AppTheme.libraryTabBarFill)
        }
        .background(AppTheme.libraryTabBarFill)
    }
}

private struct TabBarButton: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(AppFont.ui(size: 15.5, weight: .semibold, relativeTo: .footnote))
            }
            .foregroundStyle(isSelected ? AppTheme.libraryTerracotta : AppTheme.libraryTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(isSelected ? "Current tab." : "Switches to the \(title) tab.")
    }
}

private struct AddUnavailableSheet: View {
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StateMessageView(
                icon: "books.vertical.fill",
                title: "Library Still Loading",
                message: "SouvieShelf is still resolving your active library. Try again in a moment."
            )
            .padding(AppSpacing.large)
            .navigationTitle("Add Souvenir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        .appScreenBackground()
        .appNavigationChrome()
    }
}

private struct RouteUnavailableScreen: View {
    let route: AppRoute

    var body: some View {
        StateMessageView(
            icon: route.symbolName,
            title: route.title,
            message: "SouvieShelf is still resolving the active library for this screen. Try again in a moment."
        )
        .padding(AppSpacing.large)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppShell_Previews: PreviewProvider {
    static var previews: some View {
        let environment = AppEnvironment.preview(.ready)
        return AppShell(store: environment.appStore)
            .environmentObject(environment)
    }
}
