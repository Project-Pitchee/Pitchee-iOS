import SwiftUI

enum AppTab: String, CaseIterable {
    case trends
    case practice
    case pianoKeys
    case about

    var title: LocalizedStringKey {
        switch self {
        case .trends: "insights.screen.title"
        case .practice: "practice.hub.tab"
        case .pianoKeys: "piano.screen.title"
        case .about: "about.screen.title"
        }
    }

    var systemImage: String {
        switch self {
        case .trends: "chart.line.uptrend.xyaxis"
        case .practice: "figure.mind.and.body"
        case .pianoKeys: "pianokeys"
        case .about: "info.circle"
        }
    }
}

// Adapted from Kavsoft's TabBariOS26.zip: TabBariOS26/TabBariOS26/View/CustomTabBar.swift.
struct LegacyGlassTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .caption2) private var itemHeight = 56.0
    @GestureState private var dragPosition: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let itemWidth = geometry.size.width / CGFloat(AppTab.allCases.count)
            let selectedIndex = CGFloat(AppTab.allCases.firstIndex(of: selection) ?? 0)

            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.title3)
                                .accessibilityHidden(true)
                            Text(tab.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(selection == tab ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .frame(maxWidth: .infinity)
                        .frame(height: itemHeight)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityIdentifier("tab.\(tab.rawValue)")
                }
            }
            .background(alignment: .leading) {
                Capsule()
                    .fill(reduceTransparency ? AnyShapeStyle(.primary.opacity(0.12)) : AnyShapeStyle(.background))
                    .overlay { Capsule().stroke(.primary.opacity(dragPosition == nil ? 0.06 : 0.18)) }
                    .frame(width: itemWidth, height: itemHeight)
                    .scaleEffect(dragPosition != nil && !reduceMotion ? 1.08 : 1)
                    .offset(x: (dragPosition ?? selectedIndex) * itemWidth * (layoutDirection == .rightToLeft ? -1 : 1))
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: selection)
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: dragPosition == nil)
                    .accessibilityHidden(true)
            }
            .coordinateSpace(name: "legacyTabBar")
            .highPriorityGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .named("legacyTabBar"))
                    .updating($dragPosition) { value, position, _ in
                        position = Self.position(at: value.location.x, width: geometry.size.width, direction: layoutDirection)
                    }
                    .onEnded { value in
                        let position = Self.position(at: value.location.x, width: geometry.size.width, direction: layoutDirection)
                        selection = AppTab.allCases[Int(position.rounded())]
                    }
            )
        }
        .frame(height: itemHeight)
        .padding(4)
        .background { LegacyTabBarBackground() }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 560 : 440)
    }

    static func position(at x: CGFloat, width: CGFloat, direction: LayoutDirection) -> CGFloat {
        guard width > 0 else { return 0 }
        let location = direction == .rightToLeft ? width - x : x
        let position = location / (width / CGFloat(AppTab.allCases.count)) - 0.5
        return min(max(position, 0), CGFloat(AppTab.allCases.count - 1))
    }
}

struct LegacyTabBarBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        ZStack {
            shape.fill(.background.opacity(reduceTransparency ? 1 : 0.8))
            if !reduceTransparency {
                shape.fill(.ultraThinMaterial)
            }
            shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
