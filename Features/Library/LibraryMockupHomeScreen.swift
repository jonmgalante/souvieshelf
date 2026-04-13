import SwiftUI

struct LibraryMockupHomeScreen: View {
    let onAddTapped: () -> Void
    let onAvatarTapped: () -> Void

    @State private var selectedScope = LibraryMockupReferences.goal.selectedScope
    @State private var searchText = ""

    private let reference = LibraryMockupReferences.goal

    private var displayedGridItems: [LibraryMockupGridItem] {
        let baseItems: [LibraryMockupGridItem]
        switch selectedScope {
        case .personal:
            baseItems = reference.gridItems
        case .shared:
            let sharedItems = reference.gridItems.filter { $0.badge == .shared }
            baseItems = sharedItems.isEmpty ? reference.gridItems : sharedItems
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return baseItems
        }

        let normalizedQuery = query.localizedLowercase
        return baseItems.filter { item in
            item.searchableText.localizedLowercase.contains(normalizedQuery)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                LibraryMockupHeader(
                    reference: reference,
                    onAvatarTapped: onAvatarTapped,
                    onAddTapped: onAddTapped
                )
                .padding(.bottom, 18)

                LibraryMockupScopePicker(
                    availableScopes: reference.availableScopes,
                    selectedScope: $selectedScope
                )
                .padding(.bottom, 14)

                LibraryMockupSearchField(
                    placeholder: reference.searchPlaceholder,
                    searchText: $searchText
                )
                .padding(.bottom, 14)

                LibraryMockupFeatureRibbon(items: reference.topRibbonItems)
                    .padding(.bottom, 12)

                LibraryMockupGrid(items: displayedGridItems)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, AppSpacing.medium)
        }
        .background {
            LibraryMockupBackground()
                .ignoresSafeArea()
        }
    }
}

private struct LibraryMockupHeader: View {
    let reference: LibraryMockupReference
    let onAvatarTapped: () -> Void
    let onAddTapped: () -> Void

    var body: some View {
        ZStack {
            LibraryMockupWordmark(title: reference.wordmark)
                .padding(.horizontal, 80)

            HStack {
                Button(action: onAvatarTapped) {
                    Image(reference.avatarAsset.name)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")

                Spacer()

                Button(action: onAddTapped) {
                    HStack(spacing: 11) {
                        Image(systemName: LibraryMockupIcon.add.systemName)
                            .font(.system(size: 19, weight: .regular))

                        Text(reference.addButton.title)
                            .font(AppFont.ui(size: 17, weight: .semibold, relativeTo: .body))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 24)
                    .frame(height: 52)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.libraryAccentTerracotta)
                    )
                    .shadow(color: AppTheme.libraryShadow, radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Souvenir")
            }
        }
        .padding(.top, 4)
    }
}

private struct LibraryMockupScopePicker: View {
    let availableScopes: [LibraryMockupScopeOption]
    @Binding var selectedScope: LibraryMockupScopeOption

    var body: some View {
        HStack(spacing: 0) {
            ForEach(availableScopes) { scope in
                Button {
                    selectedScope = scope
                } label: {
                    Text(scope.rawValue)
                        .font(AppFont.ui(size: 15.5, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(
                            selectedScope == scope
                            ? AppTheme.libraryTextPrimary
                            : AppTheme.libraryTextSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    selectedScope == scope
                                    ? AppTheme.libraryRaisedFill
                                    : Color.clear
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 248)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.librarySegmentedControlFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        )
    }
}

private struct LibraryMockupSearchField: View {
    let placeholder: String
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: LibraryMockupIcon.search.systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(AppTheme.libraryTextMuted)

            TextField(
                "",
                text: $searchText,
                prompt: Text(placeholder)
                    .foregroundStyle(AppTheme.libraryTextMuted)
            )
            .font(AppFont.ui(size: 16.5, relativeTo: .body))
            .foregroundStyle(AppTheme.libraryTextPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Image(systemName: LibraryMockupIcon.microphone.systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(AppTheme.libraryTextMuted)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.librarySearchFieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        )
    }
}

private struct LibraryMockupFeatureRibbon: View {
    let items: [LibraryMockupTopRibbonItem]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                VStack(spacing: 7) {
                    LibraryMockupFeatureArtwork(artwork: item.artwork)

                    Text(item.title)
                        .font(AppFont.ui(size: 12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(AppTheme.libraryTextPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)

                    Text(item.subtitle)
                        .font(AppFont.ui(size: 11.5, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(item.subtitleTint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.libraryElevatedCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        )
        .shadow(color: AppTheme.libraryShadow, radius: 10, y: 3)
    }
}

private struct LibraryMockupFeatureArtwork: View {
    let artwork: LibraryMockupTopRibbonItem.Artwork

    var body: some View {
        Group {
            switch artwork {
            case .image(let asset):
                Image(asset.name)
                    .resizable()
                    .scaledToFill()
            case .symbol(let icon, let accent):
                ZStack {
                    Circle()
                        .fill(AppTheme.libraryRaisedFill)

                    Image(systemName: icon.systemName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(accent.iconColor)
                }
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(AppTheme.libraryBorder, lineWidth: 1)
        )
    }
}

private struct LibraryMockupGrid: View {
    let items: [LibraryMockupGridItem]

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items) { item in
                LibraryMockupGridTile(item: item)
            }
        }
        .padding(.bottom, 6)
    }
}

private struct LibraryMockupGridTile: View {
    let item: LibraryMockupGridItem

    private var showsMetadata: Bool {
        item.title != nil || item.subtitle != nil
    }

    private var leadingBadge: LibraryMockupBadgeSpec? {
        item.badge?.accent == .teal ? item.badge : nil
    }

    private var trailingBadge: LibraryMockupBadgeSpec? {
        item.badge?.accent == .amber ? item.badge : nil
    }

    var body: some View {
        ZStack {
            Image(item.asset.name)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    if let leadingBadge {
                        LibraryMockupBadge(spec: leadingBadge)
                    }

                    Spacer(minLength: 0)

                    if let trailingBadge {
                        LibraryMockupBadge(spec: trailingBadge)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, showsMetadata ? 9 : 10)

                if showsMetadata {
                    VStack(alignment: .leading, spacing: 1) {
                        if let title = item.title {
                            Text(title)
                                .font(AppFont.ui(size: 11.5, weight: .medium, relativeTo: .caption))
                                .foregroundStyle(AppTheme.libraryTextPrimary)
                                .lineLimit(1)
                        }

                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(AppFont.ui(size: 10, weight: .medium, relativeTo: .caption2))
                                .foregroundStyle(AppTheme.libraryTextSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                AppTheme.libraryRaisedFill.opacity(0.84),
                                AppTheme.libraryRaisedFill.opacity(0.97)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .aspectRatio(0.97, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if item.isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.librarySelectedItemOutline, lineWidth: 1.7)
            }
        }
    }
}

private struct LibraryMockupBadge: View {
    let spec: LibraryMockupBadgeSpec

    var body: some View {
        HStack(spacing: 5) {
            if let icon = spec.icon {
                Image(systemName: icon.systemName)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(spec.title)
                .font(AppFont.ui(size: 11.5, weight: .semibold, relativeTo: .caption))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(
            Capsule(style: .continuous)
                .fill(spec.accent.badgeFillColor)
        )
    }
}

private struct LibraryMockupBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(uiColor: UIColor(hex: 0xF6ECDD)),
                    AppTheme.libraryParchmentBackground,
                    Color(uiColor: UIColor(hex: 0xEFE0C8))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 110)
                .offset(x: -110, y: -260)

            Circle()
                .fill(AppTheme.libraryAccentTerracotta.opacity(0.09))
                .frame(width: 280, height: 280)
                .blur(radius: 120)
                .offset(x: 120, y: -180)

            Circle()
                .fill(AppTheme.libraryFeatureIconTeal.opacity(0.06))
                .frame(width: 240, height: 240)
                .blur(radius: 120)
                .offset(x: -130, y: 180)

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 130)
                .offset(x: 120, y: 260)
        }
    }
}

private extension LibraryMockupGridItem {
    var searchableText: String {
        [
            id,
            title,
            subtitle,
            badge?.title
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

private extension LibraryMockupTopRibbonItem {
    var subtitleTint: Color {
        switch artwork {
        case .symbol(_, let accent):
            return accent == .amber ? AppTheme.libraryWarningAmber : AppTheme.libraryTextSecondary
        case .image:
            return AppTheme.libraryTextSecondary
        }
    }
}

private extension LibraryMockupAccent {
    var iconColor: Color {
        switch self {
        case .teal:
            return AppTheme.libraryFeatureIconTeal
        case .terracotta:
            return AppTheme.libraryAccentTerracotta
        case .amber:
            return AppTheme.libraryWarningAmber
        }
    }

    var badgeFillColor: Color {
        switch self {
        case .teal:
            return AppTheme.libraryFeatureIconTeal
        case .terracotta:
            return AppTheme.libraryAccentTerracotta
        case .amber:
            return AppTheme.libraryWarningAmber
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
