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
        .safeAreaInset(edge: .bottom) {
            ShellTabBar(
                selectedTab: store.selectedTab,
                onLibraryTap: { store.selectTab(.library) },
                onAddTap: { store.presentAddSheet() },
                onMapTap: { store.selectTab(.map) }
            )
            .padding(.horizontal, AppSpacing.large)
            .padding(.top, AppSpacing.small)
            .padding(.bottom, AppSpacing.small)
            .background(AppTheme.tabBarBackground)
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
    let onAddTap: () -> Void
    let onMapTap: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            TabBarButton(
                title: MainTab.library.title,
                symbolName: MainTab.library.symbolName,
                isSelected: selectedTab == .library,
                action: onLibraryTap
            )

            Button(action: onAddTap) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textOnEmphasis)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(AppTheme.surfaceEmphasis))
            }
            .shadow(color: AppTheme.shadowColor, radius: 14, y: 5)
            .accessibilityLabel("Add Souvenir")
            .accessibilityHint("Import a photo to start a new souvenir.")

            TabBarButton(
                title: MainTab.map.title,
                symbolName: MainTab.map.symbolName,
                isSelected: selectedTab == .map,
                action: onMapTap
            )
        }
        .padding(AppSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.surfaceOverlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadowColor, radius: 18, y: 6)
    }
}

private struct TabBarButton: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xSmall) {
                Image(systemName: symbolName)
                    .font(.headline)
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(isSelected ? AppTheme.textOnEmphasis : AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.small)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AppTheme.surfaceEmphasis : Color.clear)
            )
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
