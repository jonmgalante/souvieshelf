import SwiftUI

struct LaunchGateScreen: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Group {
            switch store.phase {
            case .launching:
                VStack(spacing: AppSpacing.large) {
                    StateMessageView(
                        icon: "sparkles",
                        title: "Starting SouvieShelf",
                        message: "Checking for your library."
                    )

                    ProgressView()
                }
                .padding(AppSpacing.large)
            case .iCloudUnavailable:
                ICloudRequiredScreen(store: store)
            case .pairing:
                PairingChoiceScreen(store: store)
            case .ready:
                AppShell(store: store)
            }
        }
        .appScreenBackground()
        .task {
            await store.launchIfNeeded()
        }
    }
}

struct ICloudRequiredScreen: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            StateMessageView(
                icon: "icloud.slash.fill",
                title: "iCloud Is Required",
                message: "SouvieShelf uses your Apple account to create and join Our Library. Sign in to iCloud on this device, then retry."
            )

            Button("Retry") {
                Task {
                    await store.retryLaunch()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(AppSpacing.large)
    }
}

struct PairingChoiceScreen: View {
    @ObservedObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        Text("Our Library")
                            .font(.largeTitle.bold())

                        Text("Create your library now, then invite your partner later, or open their invite link on this iPhone to join.")
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)

                        Button("Create Library") {
                            Task {
                                await store.createOurLibrary()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Join via Invite Link") {
                            store.showJoinLibraryPlaceholder()
                        }
                        .buttonStyle(.bordered)

                        Button("Refresh Library Status") {
                            Task {
                                await store.retryLaunch()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let joinInformation = store.joinInformation {
                    SurfaceCard {
                        Text(joinInformation)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }
}

struct LaunchScreens_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            let pairingEnvironment = AppEnvironment.preview(.pairing)
            PairingChoiceScreen(store: pairingEnvironment.appStore)
                .environmentObject(pairingEnvironment)

            let iCloudEnvironment = AppEnvironment.preview(.iCloudUnavailable)
            ICloudRequiredScreen(store: iCloudEnvironment.appStore)
                .environmentObject(iCloudEnvironment)
        }
    }
}
