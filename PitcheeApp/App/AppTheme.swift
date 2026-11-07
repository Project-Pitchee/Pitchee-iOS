//
//  AppTheme.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/4.
//

import SwiftUI
import UIKit

/// Themes available to the person. Each option follows system appearance
/// without changing the selected theme; Pure uses a plain system background.
enum AppThemeOption: String, CaseIterable, Identifiable, Equatable {
    case pure
    case twilt
    case blush
    case noon
    case twilight

    var id: String { rawValue }

    var gradientStyle: PageGradientStyle? {
        switch self {
        case .pure: nil
        case .twilt: .twiltDawn
        case .blush: .blushRose
        case .noon: .noonMidnight
        case .twilight: .twilightDusk
        }
    }

    func title(for appearance: GradientAppearance) -> String {
        gradientStyle?.name(for: appearance) ?? "Pure"
    }

    /// Describes the plain background or the paired gradient names in the picker.
    var detail: String {
        guard let gradientStyle else {
            return String(localized: "settings.theme.pure.description")
        }
        return "\(gradientStyle.lightName) ↔ \(gradientStyle.darkName)"
    }

    /// Tinted neutrals carry the text and readings. Muted, related accent
    /// colors are reserved for symbols and charts, keeping the gradient the
    /// most colorful layer. A quiet surface supports text without neon tints.
    func dashboardPalette(
        for appearance: GradientAppearance,
        contrast: ColorSchemeContrast = .standard
    ) -> AppThemePalette {
        let palette: AppThemePalette = switch (self, appearance) {
        case (.pure, .light):
            AppThemePalette(
                primaryText: Color(srgbHex: 0x24262B),
                secondaryText: Color(srgbHex: 0x575B63),
                accent: Color(srgbHex: 0x496A94),
                secondary: Color(srgbHex: 0x677687),
                tertiary: Color(srgbHex: 0x65738E),
                surface: Color(srgbHex: 0xFFFFFF).opacity(0.46),
                glass: .clear
            )
        case (.pure, .dark):
            AppThemePalette(
                primaryText: Color(srgbHex: 0xF0F1F3),
                secondaryText: Color(srgbHex: 0xBEC2CB),
                accent: Color(srgbHex: 0xA4B9D3),
                secondary: Color(srgbHex: 0xBAC4D0),
                tertiary: Color(srgbHex: 0xBBC0D2),
                surface: Color(srgbHex: 0x1B1C21).opacity(0.38),
                glass: .clear
            )
        case (.twilt, .light):
            AppThemePalette(
                primaryText: Color(srgbHex: 0x262C37),
                secondaryText: Color(srgbHex: 0x4D5768),
                accent: Color(srgbHex: 0x506A94),
                secondary: Color(srgbHex: 0x687496),
                tertiary: Color(srgbHex: 0x496D82),
                surface: Color(srgbHex: 0xF5F7FC).opacity(0.42),
                glass: Color(red: 0.20, green: 0.34, blue: 0.84).opacity(0.13)
            )
        case (.twilt, .dark):
            AppThemePalette(
                primaryText: Color(srgbHex: 0xEFF1F6),
                secondaryText: Color(srgbHex: 0xC3C9D5),
                accent: Color(srgbHex: 0xA9BAD8),
                secondary: Color(srgbHex: 0xB2BBD0),
                tertiary: Color(srgbHex: 0xAAC3CF),
                surface: Color(srgbHex: 0x171D2B).opacity(0.42),
                glass: Color(red: 0.38, green: 0.48, blue: 1.00).opacity(0.18)
            )
        case (.blush, .light):
            AppThemePalette(
                primaryText: Color(srgbHex: 0x352C31),
                secondaryText: Color(srgbHex: 0x66535C),
                accent: Color(srgbHex: 0x945A70),
                secondary: Color(srgbHex: 0x9C7065),
                tertiary: Color(srgbHex: 0x8C6982),
                surface: Color(srgbHex: 0xFFF7F9).opacity(0.42),
                glass: Color(red: 0.90, green: 0.27, blue: 0.52).opacity(0.12)
            )
        case (.blush, .dark):
            AppThemePalette(
                primaryText: Color(srgbHex: 0xF5F0F2),
                secondaryText: Color(srgbHex: 0xD2C3CA),
                accent: Color(srgbHex: 0xD6AFBD),
                secondary: Color(srgbHex: 0xD1B4AA),
                tertiary: Color(srgbHex: 0xC8B2C5),
                surface: Color(srgbHex: 0x261B22).opacity(0.42),
                glass: Color(red: 1.00, green: 0.35, blue: 0.62).opacity(0.18)
            )
        case (.noon, .light):
            AppThemePalette(
                primaryText: Color(srgbHex: 0x27333B),
                secondaryText: Color(srgbHex: 0x4D606C),
                accent: Color(srgbHex: 0x49758A),
                secondary: Color(srgbHex: 0x587D7D),
                tertiary: Color(srgbHex: 0x637A93),
                surface: Color(srgbHex: 0xF4FAFC).opacity(0.42),
                glass: Color(red: 0.08, green: 0.48, blue: 0.82).opacity(0.12)
            )
        case (.noon, .dark):
            AppThemePalette(
                primaryText: Color(srgbHex: 0xEFF4F5),
                secondaryText: Color(srgbHex: 0xC0CED5),
                accent: Color(srgbHex: 0xA5C5D3),
                secondary: Color(srgbHex: 0xADCAC8),
                tertiary: Color(srgbHex: 0xADC0D7),
                surface: Color(srgbHex: 0x17232C).opacity(0.42),
                glass: Color(red: 0.16, green: 0.64, blue: 1.00).opacity(0.18)
            )
        case (.twilight, .light):
            AppThemePalette(
                primaryText: Color(srgbHex: 0x302D3A),
                secondaryText: Color(srgbHex: 0x5B5369),
                accent: Color(srgbHex: 0x77648F),
                secondary: Color(srgbHex: 0x63718F),
                tertiary: Color(srgbHex: 0x89677F),
                surface: Color(srgbHex: 0xF9F6FC).opacity(0.42),
                glass: Color(red: 0.38, green: 0.29, blue: 0.82).opacity(0.13)
            )
        case (.twilight, .dark):
            AppThemePalette(
                primaryText: Color(srgbHex: 0xF3F0F6),
                secondaryText: Color(srgbHex: 0xCDC5D7),
                accent: Color(srgbHex: 0xC1B4D4),
                secondary: Color(srgbHex: 0xB0BDD4),
                tertiary: Color(srgbHex: 0xCEB3C5),
                surface: Color(srgbHex: 0x211B2C).opacity(0.42),
                glass: Color(red: 0.74, green: 0.32, blue: 0.92).opacity(0.18)
            )
        }
        return contrast == .increased ? palette.increasingContrast(for: appearance) : palette
    }
}

struct AppThemePalette {
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let secondary: Color
    let tertiary: Color
    let surface: Color
    /// Existing tint used by shared insight-detail surfaces.
    let glass: Color

    fileprivate func increasingContrast(for appearance: GradientAppearance) -> Self {
        return Self(
            primaryText: primaryText.increasingContrast(for: appearance),
            secondaryText: primaryText.increasingContrast(for: appearance),
            accent: accent.increasingContrast(for: appearance),
            secondary: secondary.increasingContrast(for: appearance),
            tertiary: tertiary.increasingContrast(for: appearance),
            surface: surface,
            glass: glass
        )
    }
}

private extension Color {
    /// Use explicit sRGB components to keep this available on iOS 17 as well.
    func increasingContrast(for appearance: GradientAppearance) -> Color {
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        var alpha = CGFloat.zero
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return self
        }
        let endpoint: CGFloat = appearance == .dark ? 1 : 0
        return Color(
            .sRGB,
            red: Double(red + (endpoint - red) * 0.25),
            green: Double(green + (endpoint - green) * 0.25),
            blue: Double(blue + (endpoint - blue) * 0.25),
            opacity: 1
        )
    }

    init(srgbHex: UInt32) {
        self.init(
            .sRGB,
            red: Double((srgbHex >> 16) & 0xFF) / 255,
            green: Double((srgbHex >> 8) & 0xFF) / 255,
            blue: Double(srgbHex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Shared page backdrop, following the selected theme and system appearance.
struct AppThemeBackground: View {
    @AppStorage(AppStorageKey.themeSelection) private var savedTheme = AppThemeOption.twilt.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = AppThemeOption(rawValue: savedTheme) ?? .twilt
        ThemeBackground(
            theme: theme,
            appearance: colorScheme == .dark ? .dark : .light,
            intensity: colorScheme == .dark ? 0.94 : 0.78
        )
    }
}

/// Renders the same theme treatment in pages, sheets, and settings thumbnails.
struct ThemeBackground: View {
    let theme: AppThemeOption
    let appearance: GradientAppearance
    var intensity: CGFloat = 1

    var body: some View {
        if let style = theme.gradientStyle {
            PageGradient(style: style, appearance: appearance, intensity: intensity)
        } else {
            Color(uiColor: .systemGroupedBackground)
                .environment(\.colorScheme, appearance == .dark ? .dark : .light)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

/// App-wide accent colors for each named theme and appearance.
enum AppTheme {
    /// Accent used by controls for a selected theme. The values are
    /// intentionally compact and readable over both appearances; the full
    /// background treatment is rendered by `PageGradient`.
    static func color(for theme: AppThemeOption, appearance: GradientAppearance) -> Color {
        switch (theme, appearance) {
        case (.pure, .light), (.twilt, .light):
            Color(red: 0.24, green: 0.40, blue: 0.92)
        case (.pure, .dark), (.twilt, .dark):
            Color(red: 0.45, green: 0.58, blue: 1.00)
        case (.blush, .light):
            Color(red: 0.88, green: 0.26, blue: 0.52)
        case (.blush, .dark):
            Color(red: 1.00, green: 0.40, blue: 0.64)
        case (.noon, .light):
            Color(red: 0.08, green: 0.52, blue: 0.83)
        case (.noon, .dark):
            Color(red: 0.22, green: 0.72, blue: 1.00)
        case (.twilight, .light):
            Color(red: 0.40, green: 0.31, blue: 0.84)
        case (.twilight, .dark):
            Color(red: 0.88, green: 0.38, blue: 0.88)
        }
    }
}

extension Color {
    /// Resolves the current app accent for places that need a concrete `Color`
    /// value (for example, Charts and Canvas). Views also receive the same
    /// value through the root `.tint` modifier.
    static var pitcheeAccent: Color {
        let defaults = UserDefaults.standard
        let customHex = defaults.string(forKey: AppStorageKey.customThemeColor) ?? ""
        if let customColor = Color(hex: customHex) {
            return customColor
        }

        let theme = AppThemeOption(
            rawValue: defaults.string(forKey: AppStorageKey.themeSelection) ?? ""
        ) ?? .twilt
        return Color(uiColor: UIColor { traits in
            let appearance: GradientAppearance =
                traits.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(AppTheme.color(for: theme, appearance: appearance))
        })
    }

    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16) else {
            return nil
        }

        let red = Double((number >> (value.count == 8 ? 24 : 16)) & 0xFF) / 255
        let green = Double((number >> (value.count == 8 ? 16 : 8)) & 0xFF) / 255
        let blue = Double((number >> (value.count == 8 ? 8 : 0)) & 0xFF) / 255
        let alpha = value.count == 8 ? Double(number & 0xFF) / 255 : 1
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
