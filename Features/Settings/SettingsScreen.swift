import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var store: AppStore

    @State private var iCloudStatus: ICloudStatus?
    @State private var refreshedShareSummary: ShareSummary?
    @State private var hasLoadedShareSummary = false
    @State private var isRefreshing = false
    @State private var isPreparingPartnerShare = false
    @State private var partnerShareControllerContext: LibraryShareControllerContext?
    @State private var needsShareStatusRefresh = false
    @State private var shareErrorMessage: String?

    var body: some View {
        List {
            Section("iCloud") {
                iCloudSection
            }

            Section("Partner") {
                if let activeLibraryContext = store.activeLibraryContext {
                    partnerSection(for: activeLibraryContext)
                } else {
                    SettingsStatusRow(
                        symbolName: "person.2.slash",
                        tintColor: AppTheme.textMuted,
                        title: "Library unavailable",
                        message: "SouvieShelf is still resolving your active library."
                    )
                    .appGroupedRowChrome()
                }
            }

            Section("Library") {
                NavigationLink(value: AppRoute.recentlyDeleted) {
                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Label("Recently Deleted", systemImage: "trash")
                            .font(.body.weight(.semibold))

                        Text("Review items and trips removed from Our Library.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.vertical, AppSpacing.xSmall)
                }
                .appGroupedRowChrome()
            }
        }
        .listStyle(.insetGrouped)
        .appGroupedScreenChrome()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isRefreshing {
                    ProgressView()
                } else {
                    Button {
                        Task {
                            await refreshStatus()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh Settings")
                }
            }
        }
        .task(id: refreshToken) {
            await refreshStatus()
        }
        .refreshable {
            await refreshStatus()
        }
        .sheet(item: $partnerShareControllerContext, onDismiss: {
            guard needsShareStatusRefresh else {
                return
            }

            needsShareStatusRefresh = false
            Task {
                await refreshStatus(afterSharingLifecycleChange: true)
            }
        }) { shareControllerContext in
            PartnerShareSheet(
                shareControllerContext: shareControllerContext,
                onLifecycleChange: {
                    needsShareStatusRefresh = true
                },
                onError: { message in
                    shareErrorMessage = message
                }
            )
        }
        .alert(
            "Couldn't open sharing",
            isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        shareErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "")
        }
    }

    private var refreshToken: String {
        guard let activeLibraryContext = store.activeLibraryContext else {
            return "settings|none"
        }

        return "settings|\(activeLibraryContext.libraryID.uuidString)|\(activeLibraryContext.storeScope.rawValue)"
    }

    @ViewBuilder
    private var iCloudSection: some View {
        if let iCloudStatus {
            switch iCloudStatus {
            case .available:
                SettingsStatusRow(
                    symbolName: "icloud.fill",
                    tintColor: AppTheme.accentPrimary,
                    title: "Connected to iCloud",
                    message: "SouvieShelf can sync and share your library with your Apple account on this iPhone."
                )
                .appGroupedRowChrome()
            case .unavailable:
                SettingsStatusRow(
                    symbolName: "icloud.slash.fill",
                    tintColor: .red,
                    title: "iCloud unavailable",
                    message: "Sign in to iCloud in Settings on this iPhone, then retry."
                )
                .appGroupedRowChrome()

                Button("Retry iCloud Check") {
                    Task {
                        await refreshStatus()
                    }
                }
                .appGroupedRowChrome()
            }
        } else {
            SettingsLoadingRow(
                symbolName: "icloud",
                title: "Checking iCloud status"
            )
            .appGroupedRowChrome()
        }
    }

    @ViewBuilder
    private func partnerSection(for activeLibraryContext: ActiveLibraryContext) -> some View {
        if let shareSummary = resolvedShareSummary(for: activeLibraryContext) {
            let presentation = SettingsPartnerPresentation.resolve(
                shareSummary: shareSummary,
                activeLibraryContext: activeLibraryContext
            )

            SettingsStatusRow(
                symbolName: presentation.symbolName,
                tintColor: presentation.tintColor,
                title: presentation.title,
                message: presentation.message
            )
            .appGroupedRowChrome()

            if let action = presentation.action {
                Button {
                    Task {
                        await preparePartnerShare(for: activeLibraryContext)
                    }
                } label: {
                    HStack {
                        Label(action.title, systemImage: action.symbolName)

                        Spacer()

                        if isPreparingPartnerShare {
                            ProgressView()
                        }
                    }
                }
                .disabled(isPreparingPartnerShare || iCloudStatus == .unavailable)
                .appGroupedRowChrome()
            }
        } else if hasLoadedShareSummary, activeLibraryContext.shareSummary == nil {
            SettingsStatusRow(
                symbolName: "exclamationmark.triangle.fill",
                tintColor: .orange,
                title: "Partner status unavailable",
                message: "SouvieShelf couldn't load the latest sharing details right now."
            )
            .appGroupedRowChrome()

            Button("Retry Partner Status") {
                Task {
                    await refreshStatus()
                }
            }
            .appGroupedRowChrome()
        } else {
            SettingsLoadingRow(
                symbolName: "person.2",
                title: "Checking partner status"
            )
            .appGroupedRowChrome()
        }
    }

    private func resolvedShareSummary(for activeLibraryContext: ActiveLibraryContext) -> ShareSummary? {
        refreshedShareSummary ?? activeLibraryContext.shareSummary
    }

    @MainActor
    private func refreshStatus(afterSharingLifecycleChange: Bool = false) async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        if afterSharingLifecycleChange {
            await store.refreshAfterSharingLifecycleChange()
        }

        let activeLibraryContext = store.activeLibraryContext
        async let refreshedICloudStatus = environment.dependencies.bootstrapRepository.iCloudStatus()

        let shareSummary: ShareSummary?
        if let activeLibraryContext {
            shareSummary = await environment.dependencies.sharingRepository.fetchShareSummary(
                libraryID: activeLibraryContext.libraryID,
                scope: activeLibraryContext.storeScope
            )
        } else {
            shareSummary = nil
        }

        iCloudStatus = await refreshedICloudStatus
        refreshedShareSummary = shareSummary
        if let shareSummary {
            store.applyShareSummary(shareSummary)
        }
        hasLoadedShareSummary = true
    }

    @MainActor
    private func preparePartnerShare(for activeLibraryContext: ActiveLibraryContext) async {
        guard activeLibraryContext.isOwner else {
            return
        }

        isPreparingPartnerShare = true
        shareErrorMessage = nil
        needsShareStatusRefresh = false
        defer { isPreparingPartnerShare = false }

        do {
            partnerShareControllerContext = try await environment.dependencies.sharingRepository.prepareShareController(
                libraryID: activeLibraryContext.libraryID,
                scope: activeLibraryContext.storeScope
            )
        } catch {
            shareErrorMessage = error.localizedDescription
        }
    }
}

enum SettingsPartnerAction: Equatable {
    case invitePartner
    case managePartner

    var title: String {
        switch self {
        case .invitePartner:
            "Invite Partner"
        case .managePartner:
            "Manage Partner"
        }
    }

    var symbolName: String {
        switch self {
        case .invitePartner:
            "person.badge.plus"
        case .managePartner:
            "person.crop.circle.badge.checkmark"
        }
    }
}

struct SettingsPartnerPresentation {
    let title: String
    let message: String
    let symbolName: String
    let tintColor: Color
    let action: SettingsPartnerAction?

    static func resolve(
        shareSummary: ShareSummary,
        activeLibraryContext: ActiveLibraryContext
    ) -> SettingsPartnerPresentation {
        if shareSummary.isOwner || activeLibraryContext.isOwner {
            switch shareSummary.partnerState {
            case .none:
                return SettingsPartnerPresentation(
                    title: "Invite Partner anytime",
                    message: "Keep using this library on your own for now, then invite your partner later from Apple's native share sheet.",
                    symbolName: "person.badge.plus",
                    tintColor: AppTheme.accentPrimary,
                    action: .invitePartner
                )
            case .inviteSent:
                return SettingsPartnerPresentation(
                    title: "Invite pending",
                    message: "Your invite is out. You can keep using the library while your partner accepts on their iPhone.",
                    symbolName: "paperplane.fill",
                    tintColor: .orange,
                    action: .managePartner
                )
            case .connected(let displayName):
                return SettingsPartnerPresentation(
                    title: displayName.map { "Connected with \($0)" } ?? "Partner connected",
                    message: "Everything you save here stays in your shared library.",
                    symbolName: "person.2.fill",
                    tintColor: AppTheme.accentPrimary,
                    action: .managePartner
                )
            }
        }

        switch shareSummary.partnerState {
        case .connected(let displayName):
            let ownerDisplayName = shareSummary.ownerDisplayName ?? displayName
            return SettingsPartnerPresentation(
                title: ownerDisplayName.map { "Shared by \($0)" } ?? "Shared with you",
                message: "You're viewing the shared library from your partner's invite.",
                symbolName: "person.2.fill",
                tintColor: AppTheme.accentPrimary,
                action: nil
            )
        case .inviteSent:
            return SettingsPartnerPresentation(
                title: "Shared library invite pending",
                message: "The shared library is still finishing setup on this iPhone.",
                symbolName: "paperplane.fill",
                tintColor: .orange,
                action: nil
            )
        case .none:
            return SettingsPartnerPresentation(
                title: "Shared library",
                message: "Partner sharing details are unavailable right now.",
                symbolName: "person.2.slash",
                tintColor: AppTheme.textMuted,
                action: nil
            )
        }
    }
}

private struct SettingsStatusRow: View {
    let symbolName: String
    let tintColor: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: symbolName)
                .foregroundStyle(tintColor)
                .frame(width: 24, height: 24)
                .padding(.top, 2)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.backgroundPrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.borderSubtle, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsLoadingRow: View {
    let symbolName: String
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            Image(systemName: symbolName)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.backgroundPrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.borderSubtle, lineWidth: 1)
                )

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            ProgressView()
        }
        .padding(.vertical, AppSpacing.xSmall)
    }
}
