import SwiftUI

/// The native segmented control and glass treatment used in Kavsoft's PhotosTB example.
struct InsightsRangeTabBar: View {
    @Binding var selection: InsightsRange
    var ranges: [InsightsRange] = InsightsRange.allCases
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if #available(iOS 26.0, *) {
            InsightsRangePicker(selection: $selection, ranges: ranges)
                .labelsHidden()
                .controlSize(horizontalSizeClass == .regular ? .regular : .large)
                .glassEffect(.regular, in: .capsule)
                .accessibilityIdentifier("insights.range.bottom")
        } else {
            InsightsRangePicker(selection: $selection, ranges: ranges)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityIdentifier("insights.range.bottom")
        }
    }
}

/// Keeps the picker outside the system accessory so it has just one glass surface.
struct InsightsRangeTabBarOverlay: ViewModifier {
    @Binding var selection: InsightsRange
    var ranges: [InsightsRange] = InsightsRange.allCases
    let isVisible: Bool
    let isMinimized: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var safeAreaBottom: CGFloat = 0

    private var bottomOffset: CGFloat {
        let inlineOffset: CGFloat = safeAreaBottom == 0 ? -28 : (horizontalSizeClass == .regular ? -3 : 6)
        return inlineOffset - (isMinimized ? 0 : 64)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isVisible {
                    InsightsRangeTabBar(selection: $selection, ranges: ranges)
                        .frame(maxWidth: 560)
                        .padding(.leading, isMinimized ? 90 : 20)
                        .padding(.trailing, 20)
                        .offset(y: bottomOffset)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isMinimized)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeAreaBottom = $0 }
    }
}

struct InsightsTabBarMinimization: ViewModifier {
    let isEnabled: Bool
    @Binding var isMinimized: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var minimizes: Bool {
        isEnabled && !dynamicTypeSize.isAccessibilitySize && !voiceOverEnabled
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    InsightsTabBarObserver(isMinimized: $isMinimized)
                        .id(minimizes)
                }
                .compositingGroup()
                .tabBarMinimizeBehavior(minimizes ? .onScrollDown : .never)
                .onChange(of: minimizes) { _, _ in isMinimized = false }
        } else {
            content
        }
    }
}
