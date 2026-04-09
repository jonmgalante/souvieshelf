import SwiftUI
import UIKit

/// Source of truth for SouvieShelf's approved brand palette.
/// Prefer `AppTheme` semantic tokens in UI code instead of using palette colors or hex values directly.
enum AppPalette {
    static let walnut = PaletteColor(hex: 0x4D1F0D)
    static let parchment = PaletteColor(hex: 0xF4E8CE)
    static let rosewood = PaletteColor(hex: 0x7A4A4A)
    static let blushSand = PaletteColor(hex: 0xD8BBB0)
    static let camel = PaletteColor(hex: 0xBA8D68)
    static let espresso = PaletteColor(hex: 0x2F1D18)

    struct PaletteColor {
        fileprivate let hex: UInt32

        var color: Color {
            Color(uiColor: uiColor)
        }

        var uiColor: UIColor {
            UIColor(hex: hex)
        }

        func opacity(_ alpha: CGFloat) -> UIColor {
            uiColor.withAlphaComponent(alpha)
        }
    }
}

/// Semantic app chrome colors for light and dark mode.
/// Keep destructive and platform status colors on system semantics unless the behavior explicitly calls for them.
enum AppTheme {
    static let backgroundPrimary = Color(uiColor: UIColorTokens.backgroundPrimary)
    static let backgroundSecondary = Color(uiColor: UIColorTokens.backgroundSecondary)
    static let surfacePrimary = Color(uiColor: UIColorTokens.surfacePrimary)
    static let surfaceSecondary = Color(uiColor: UIColorTokens.surfaceSecondary)
    static let surfaceEmphasis = Color(uiColor: UIColorTokens.surfaceEmphasis)
    static let surfaceOverlay = Color(uiColor: UIColorTokens.surfaceOverlay)
    static let placeholderSurface = Color(uiColor: UIColorTokens.placeholderSurface)
    static var brandSurface: Color { surfaceEmphasis }
    static let textPrimary = Color(uiColor: UIColorTokens.textPrimary)
    static let textSecondary = Color(uiColor: UIColorTokens.textSecondary)
    static let textMuted = Color(uiColor: UIColorTokens.textMuted)
    static let textOnEmphasis = Color(uiColor: UIColorTokens.textOnEmphasis)
    static let accentPrimary = Color(uiColor: UIColorTokens.accentPrimary)
    static let accentSecondary = Color(uiColor: UIColorTokens.accentSecondary)
    static let fieldFill = Color(uiColor: UIColorTokens.fieldFill)
    static let chipFill = Color(uiColor: UIColorTokens.chipFill)
    static let chipSelectedFill = Color(uiColor: UIColorTokens.chipSelectedFill)
    static let borderSubtle = Color(uiColor: UIColorTokens.borderSubtle)
    static var divider: Color { borderSubtle }
    static let toolbarBackground = Color(uiColor: UIColorTokens.toolbarBackground)
    static let tabBarBackground = Color(uiColor: UIColorTokens.tabBarBackground)
    static let shadowColor = Color(uiColor: UIColorTokens.shadowColor)

    enum UIColorTokens {
        static let backgroundPrimary = dynamicColor(
            light: AppPalette.parchment.uiColor,
            dark: AppPalette.espresso.uiColor
        )
        static let backgroundSecondary = dynamicColor(
            light: AppPalette.blushSand.opacity(0.48),
            dark: AppPalette.walnut.uiColor
        )
        static let surfacePrimary = dynamicColor(
            light: AppPalette.blushSand.opacity(0.38),
            dark: AppPalette.walnut.uiColor
        )
        static let surfaceSecondary = dynamicColor(
            light: AppPalette.blushSand.opacity(0.52),
            dark: AppPalette.rosewood.opacity(0.88)
        )
        static let surfaceEmphasis = dynamicColor(
            light: AppPalette.walnut.uiColor,
            dark: AppPalette.rosewood.uiColor
        )
        static let surfaceOverlay = dynamicColor(
            light: AppPalette.parchment.opacity(0.96),
            dark: AppPalette.walnut.opacity(0.94)
        )
        static let placeholderSurface = dynamicColor(
            light: AppPalette.blushSand.opacity(0.72),
            dark: AppPalette.rosewood.opacity(0.82)
        )
        static var brandSurface: UIColor { surfaceEmphasis }
        static let textPrimary = dynamicColor(
            light: AppPalette.espresso.uiColor,
            dark: AppPalette.parchment.uiColor
        )
        static let textSecondary = dynamicColor(
            light: AppPalette.walnut.uiColor,
            dark: AppPalette.blushSand.uiColor
        )
        static let textMuted = dynamicColor(
            light: AppPalette.rosewood.opacity(0.84),
            dark: AppPalette.blushSand.opacity(0.82)
        )
        static let textOnEmphasis = dynamicColor(
            light: AppPalette.parchment.uiColor,
            dark: AppPalette.parchment.uiColor
        )
        static let accentPrimary = dynamicColor(
            light: AppPalette.walnut.uiColor,
            dark: AppPalette.camel.uiColor
        )
        static let accentSecondary = dynamicColor(
            light: AppPalette.camel.uiColor,
            dark: AppPalette.blushSand.uiColor
        )
        static let fieldFill = dynamicColor(
            light: AppPalette.blushSand.opacity(0.38),
            dark: AppPalette.walnut.opacity(0.88)
        )
        static let chipFill = dynamicColor(
            light: AppPalette.blushSand.opacity(0.62),
            dark: AppPalette.rosewood.opacity(0.74)
        )
        static let chipSelectedFill = dynamicColor(
            light: AppPalette.camel.opacity(0.36),
            dark: AppPalette.camel.opacity(0.34)
        )
        static let borderSubtle = dynamicColor(
            light: AppPalette.rosewood.opacity(0.18),
            dark: AppPalette.blushSand.opacity(0.18)
        )
        static var divider: UIColor { borderSubtle }
        static let toolbarBackground = dynamicColor(
            light: AppPalette.parchment.opacity(0.96),
            dark: AppPalette.walnut.opacity(0.96)
        )
        static var tabBarBackground: UIColor { toolbarBackground }
        static let shadowColor = dynamicColor(
            light: AppPalette.espresso.opacity(0.12),
            dark: AppPalette.espresso.opacity(0.42)
        )

        private static func dynamicColor(light: UIColor, dark: UIColor) -> UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        }
    }
}

enum AppSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
}

extension View {
    func appScreenBackground(_ color: Color = AppTheme.backgroundPrimary) -> some View {
        background {
            color.ignoresSafeArea()
        }
    }

    func appNavigationChrome() -> some View {
        toolbarBackground(AppTheme.toolbarBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    func appGroupedScreenChrome(_ color: Color = AppTheme.backgroundPrimary) -> some View {
        scrollContentBackground(.hidden)
            .appScreenBackground(color)
            .appNavigationChrome()
    }

    func appGroupedRowChrome(_ background: Color = AppTheme.surfacePrimary) -> some View {
        listRowBackground(background)
            .listRowSeparatorTint(AppTheme.borderSubtle)
    }

    func appCardChrome(
        cornerRadius: CGFloat = 20,
        fill: Color = AppTheme.surfacePrimary
    ) -> some View {
        modifier(AppCardChrome(cornerRadius: cornerRadius, fill: fill))
    }
}

struct SurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .appCardChrome()
    }
}

struct StateMessageView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.textOnEmphasis)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppTheme.surfaceEmphasis)
                    )

                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AppCardChrome: ViewModifier {
    let cornerRadius: CGFloat
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.borderSubtle, lineWidth: 1)
            }
            .shadow(color: AppTheme.shadowColor, radius: 18, y: 8)
    }
}

struct StateMessageView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StateMessageView(
                icon: "sparkles",
                title: "Preview State",
                message: "Shared UI previews the app's current empty and loading states."
            )
            .padding()
            .appScreenBackground()
            .preferredColorScheme(.light)

            StateMessageView(
                icon: "sparkles",
                title: "Preview State",
                message: "Shared UI previews the app's current empty and loading states."
            )
            .padding()
            .appScreenBackground()
            .preferredColorScheme(.dark)
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
