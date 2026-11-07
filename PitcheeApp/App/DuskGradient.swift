//
//  DuskGradient.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import SwiftUI

/// The two visual treatments stay explicit so a page can choose an appearance
/// without changing the palette family it uses.
enum GradientAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: Self { self }
}

/// Gradient families used by the page-refactor explorations.
enum PageGradientStyle: String, CaseIterable, Identifiable {
    /// Concept gradient: Twilt (light) ↔ Dawn (dark).
    case twiltDawn
    /// Pink gradient: Blush (light) ↔ Rose (dark).
    case blushRose
    /// Pale-blue gradient: Noon (light) ↔ Midnight (dark).
    case noonMidnight
    /// Blue-pink gradient: Twilight (light) ↔ Dusk (dark).
    case twilightDusk

    var id: Self { self }

    var lightName: String {
        switch self {
        case .twiltDawn: "Twilt"
        case .blushRose: "Blush"
        case .noonMidnight: "Noon"
        case .twilightDusk: "Twilight"
        }
    }

    var darkName: String {
        switch self {
        case .twiltDawn: "Dawn"
        case .blushRose: "Rose"
        case .noonMidnight: "Midnight"
        case .twilightDusk: "Dusk"
        }
    }

    func name(for appearance: GradientAppearance) -> String {
        appearance == .light ? lightName : darkName
    }
}

/// Shared renderer for all gradient families. The positions and layer weights
/// stay the same between light and dark, which keeps each pair one-to-one while
/// allowing the colors to carry the visual difference.
struct PageGradient: View {
    let style: PageGradientStyle
    var appearance: GradientAppearance = .light
    var intensity: CGFloat = 1

    private var clampedIntensity: Double {
        min(max(Double(intensity), 0), 1)
    }

    var body: some View {
        let palette = AtmosphericGradientPalette(style: style, appearance: appearance)
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: palette.baseStart, location: 0),
                        .init(color: palette.baseMiddle, location: 0.34),
                        .init(color: palette.baseEnd, location: 0.72),
                        .init(color: palette.baseBottom, location: 1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Cool light gathers in the upper-right corner.
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: palette.coolHighlight.opacity(scaledOpacity(0.74)), location: 0),
                        .init(color: palette.coolGlow.opacity(scaledOpacity(0.46)), location: 0.34),
                        .init(color: palette.coolGlow.opacity(scaledOpacity(0.08)), location: 0.72),
                        .init(color: .clear, location: 1)
                    ]),
                    center: UnitPoint(x: 1.02, y: 0.06),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.92
                )

                // The accent bloom stays in the lower-right for every family.
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: palette.accentHighlight.opacity(scaledOpacity(0.80)), location: 0),
                        .init(color: palette.accentGlow.opacity(scaledOpacity(0.54)), location: 0.28),
                        .init(color: palette.accentEdge.opacity(scaledOpacity(0.24)), location: 0.62),
                        .init(color: .clear, location: 1)
                    ]),
                    center: UnitPoint(x: 1.06, y: 0.72),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.72
                )

                // A quiet central bloom gives the background the same depth as
                // the glass-like reference without adding any foreground.
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: palette.centerGlow.opacity(scaledOpacity(0.25)), location: 0),
                        .init(color: palette.centerGlow.opacity(scaledOpacity(0.10)), location: 0.52),
                        .init(color: .clear, location: 1)
                    ]),
                    center: UnitPoint(x: 0.44, y: 0.43),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.82
                )

                LinearGradient(
                    colors: [
                        palette.edgeShade.opacity(palette.edgeOpacity * clampedIntensity),
                        .clear,
                        palette.edgeShade.opacity(palette.edgeOpacity * 0.62 * clampedIntensity)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func scaledOpacity(_ value: Double) -> Double {
        value * clampedIntensity
    }
}

/// The original Dusk colors remain available for subsequent page components.
enum DuskGradientPalette {
    static let midnight = Color(red: 0.012, green: 0.080, blue: 0.205)
    static let deepBlue = Color(red: 0.025, green: 0.180, blue: 0.390)
    static let indigo = Color(red: 0.135, green: 0.205, blue: 0.460)
    static let night = Color(red: 0.020, green: 0.080, blue: 0.220)

    static let periwinkle = Color(red: 0.570, green: 0.650, blue: 0.900)
    static let blueGlow = Color(red: 0.265, green: 0.455, blue: 0.825)
    static let cobalt = Color(red: 0.165, green: 0.365, blue: 0.790)
    static let rose = Color(red: 0.700, green: 0.445, blue: 0.570)
    static let apricot = Color(red: 0.930, green: 0.610, blue: 0.525)
    static let violet = Color(red: 0.360, green: 0.300, blue: 0.650)
}

/// Colors for one gradient family and one appearance. The renderer owns the
/// layout; these values only describe the corresponding palette.
private struct AtmosphericGradientPalette {
    let baseStart: Color
    let baseMiddle: Color
    let baseEnd: Color
    let baseBottom: Color
    let coolHighlight: Color
    let coolGlow: Color
    let accentHighlight: Color
    let accentGlow: Color
    let accentEdge: Color
    let centerGlow: Color
    let edgeShade: Color
    let edgeOpacity: Double

    private init(
        baseStart: Color,
        baseMiddle: Color,
        baseEnd: Color,
        baseBottom: Color,
        coolHighlight: Color,
        coolGlow: Color,
        accentHighlight: Color,
        accentGlow: Color,
        accentEdge: Color,
        centerGlow: Color,
        edgeShade: Color,
        edgeOpacity: Double
    ) {
        self.baseStart = baseStart
        self.baseMiddle = baseMiddle
        self.baseEnd = baseEnd
        self.baseBottom = baseBottom
        self.coolHighlight = coolHighlight
        self.coolGlow = coolGlow
        self.accentHighlight = accentHighlight
        self.accentGlow = accentGlow
        self.accentEdge = accentEdge
        self.centerGlow = centerGlow
        self.edgeShade = edgeShade
        self.edgeOpacity = edgeOpacity
    }

    init(style: PageGradientStyle, appearance: GradientAppearance) {
        switch (style, appearance) {
        case (.twiltDawn, .light):
            self.init(
                baseStart: Color(red: 0.80, green: 0.90, blue: 0.99),
                baseMiddle: Color(red: 0.58, green: 0.76, blue: 0.94),
                baseEnd: Color(red: 0.62, green: 0.64, blue: 0.88),
                baseBottom: Color(red: 0.86, green: 0.78, blue: 0.91),
                coolHighlight: Color(red: 0.96, green: 0.98, blue: 1.00),
                coolGlow: Color(red: 0.56, green: 0.75, blue: 0.94),
                accentHighlight: Color(red: 1.00, green: 0.76, blue: 0.67),
                accentGlow: Color(red: 0.94, green: 0.57, blue: 0.70),
                accentEdge: Color(red: 0.70, green: 0.62, blue: 0.86),
                centerGlow: Color(red: 0.45, green: 0.70, blue: 0.94),
                edgeShade: .black,
                edgeOpacity: 0.05
            )
        case (.twiltDawn, .dark):
            self.init(
                baseStart: DuskGradientPalette.midnight,
                baseMiddle: DuskGradientPalette.deepBlue,
                baseEnd: DuskGradientPalette.indigo,
                baseBottom: DuskGradientPalette.night,
                coolHighlight: DuskGradientPalette.periwinkle,
                coolGlow: DuskGradientPalette.blueGlow,
                accentHighlight: DuskGradientPalette.apricot,
                accentGlow: DuskGradientPalette.rose,
                accentEdge: DuskGradientPalette.violet,
                centerGlow: DuskGradientPalette.cobalt,
                edgeShade: .black,
                edgeOpacity: 0.13
            )
        case (.blushRose, .light):
            self.init(
                baseStart: Color(red: 1.00, green: 0.93, blue: 0.96),
                baseMiddle: Color(red: 1.00, green: 0.78, blue: 0.87),
                baseEnd: Color(red: 0.94, green: 0.65, blue: 0.78),
                baseBottom: Color(red: 1.00, green: 0.86, blue: 0.82),
                coolHighlight: Color(red: 1.00, green: 0.98, blue: 1.00),
                coolGlow: Color(red: 0.94, green: 0.64, blue: 0.82),
                accentHighlight: Color(red: 1.00, green: 0.72, blue: 0.65),
                accentGlow: Color(red: 0.96, green: 0.43, blue: 0.65),
                accentEdge: Color(red: 0.72, green: 0.46, blue: 0.72),
                centerGlow: Color(red: 1.00, green: 0.58, blue: 0.75),
                edgeShade: .black,
                edgeOpacity: 0.045
            )
        case (.blushRose, .dark):
            self.init(
                baseStart: Color(red: 0.12, green: 0.025, blue: 0.10),
                baseMiddle: Color(red: 0.31, green: 0.035, blue: 0.19),
                baseEnd: Color(red: 0.42, green: 0.060, blue: 0.25),
                baseBottom: Color(red: 0.10, green: 0.020, blue: 0.14),
                coolHighlight: Color(red: 0.92, green: 0.34, blue: 0.62),
                coolGlow: Color(red: 0.70, green: 0.18, blue: 0.48),
                accentHighlight: Color(red: 1.00, green: 0.42, blue: 0.43),
                accentGlow: Color(red: 0.80, green: 0.16, blue: 0.36),
                accentEdge: Color(red: 0.42, green: 0.10, blue: 0.35),
                centerGlow: Color(red: 0.88, green: 0.18, blue: 0.52),
                edgeShade: .black,
                edgeOpacity: 0.15
            )
        case (.noonMidnight, .light):
            self.init(
                baseStart: Color(red: 0.86, green: 0.95, blue: 1.00),
                baseMiddle: Color(red: 0.63, green: 0.86, blue: 0.98),
                baseEnd: Color(red: 0.62, green: 0.76, blue: 0.96),
                baseBottom: Color(red: 0.82, green: 0.88, blue: 0.98),
                coolHighlight: Color(red: 0.98, green: 1.00, blue: 1.00),
                coolGlow: Color(red: 0.42, green: 0.80, blue: 0.98),
                accentHighlight: Color(red: 0.58, green: 0.90, blue: 1.00),
                accentGlow: Color(red: 0.38, green: 0.68, blue: 0.92),
                accentEdge: Color(red: 0.50, green: 0.58, blue: 0.86),
                centerGlow: Color(red: 0.30, green: 0.72, blue: 0.98),
                edgeShade: .black,
                edgeOpacity: 0.04
            )
        case (.noonMidnight, .dark):
            self.init(
                baseStart: Color(red: 0.015, green: 0.080, blue: 0.16),
                baseMiddle: Color(red: 0.020, green: 0.220, blue: 0.38),
                baseEnd: Color(red: 0.080, green: 0.250, blue: 0.48),
                baseBottom: Color(red: 0.020, green: 0.080, blue: 0.22),
                coolHighlight: Color(red: 0.30, green: 0.82, blue: 1.00),
                coolGlow: Color(red: 0.08, green: 0.50, blue: 0.82),
                accentHighlight: Color(red: 0.18, green: 0.78, blue: 0.90),
                accentGlow: Color(red: 0.12, green: 0.45, blue: 0.72),
                accentEdge: Color(red: 0.18, green: 0.24, blue: 0.55),
                centerGlow: Color(red: 0.08, green: 0.48, blue: 0.88),
                edgeShade: .black,
                edgeOpacity: 0.15
            )
        case (.twilightDusk, .light):
            self.init(
                baseStart: Color(red: 0.69, green: 0.85, blue: 1.00),
                baseMiddle: Color(red: 0.38, green: 0.66, blue: 0.96),
                baseEnd: Color(red: 0.66, green: 0.55, blue: 0.91),
                baseBottom: Color(red: 0.90, green: 0.76, blue: 0.93),
                coolHighlight: Color(red: 0.78, green: 0.97, blue: 1.00),
                coolGlow: Color(red: 0.22, green: 0.72, blue: 0.98),
                accentHighlight: Color(red: 1.00, green: 0.66, blue: 0.82),
                accentGlow: Color(red: 0.91, green: 0.32, blue: 0.75),
                accentEdge: Color(red: 0.60, green: 0.38, blue: 0.82),
                centerGlow: Color(red: 0.38, green: 0.48, blue: 1.00),
                edgeShade: .black,
                edgeOpacity: 0.055
            )
        case (.twilightDusk, .dark):
            self.init(
                baseStart: Color(red: 0.010, green: 0.050, blue: 0.18),
                baseMiddle: Color(red: 0.040, green: 0.15, blue: 0.40),
                baseEnd: Color(red: 0.24, green: 0.10, blue: 0.50),
                baseBottom: Color(red: 0.030, green: 0.050, blue: 0.20),
                coolHighlight: Color(red: 0.20, green: 0.75, blue: 1.00),
                coolGlow: Color(red: 0.10, green: 0.40, blue: 0.90),
                accentHighlight: Color(red: 1.00, green: 0.27, blue: 0.67),
                accentGlow: Color(red: 0.68, green: 0.12, blue: 0.58),
                accentEdge: Color(red: 0.35, green: 0.18, blue: 0.68),
                centerGlow: Color(red: 0.25, green: 0.30, blue: 0.95),
                edgeShade: .black,
                edgeOpacity: 0.16
            )
        }
    }
}

#if DEBUG
#Preview("Page Gradients") {
    ScrollView {
        ForEach(PageGradientStyle.allCases) { style in
            HStack {
                PageGradient(style: style, appearance: .light)
                PageGradient(style: style, appearance: .dark)
            }
            .frame(height: 280)
        }
    }
}
#endif
