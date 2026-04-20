import SwiftUI

struct AppShell: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var store: AppStore

    var body: some View {
        NavigationStack(path: $store.routePath) {
            TabView(selection: selectedTabBinding) {
                libraryTab
                    .tabItem {
                        Label(
                            MainTab.library.title,
                            systemImage: LibraryHomeIcon.libraryTab.systemName
                        )
                    }
                    .tag(MainTab.library)

                mapTab
                    .tabItem {
                        Label(
                            MainTab.map.title,
                            systemImage: "globe.americas"
                        )
                    }
                    .tag(MainTab.map)
            }
            .tint(AppTheme.librarySelectedTabAccent)
            .toolbarBackground(LibraryHomeDesign.Colors.elevatedSurface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
        .appScreenBackground()
        .appNavigationChrome()
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

    private var selectedTabBinding: Binding<MainTab> {
        Binding(
            get: { store.selectedTab },
            set: { newValue in
                guard store.selectedTab != newValue else {
                    return
                }

                store.selectTab(newValue)
            }
        )
    }

    @ViewBuilder
    private var libraryTab: some View {
        if store.selectedTab == .library {
            LibraryScreen(store: store)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var mapTab: some View {
        if store.selectedTab == .map {
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
        } else {
            Color.clear
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
