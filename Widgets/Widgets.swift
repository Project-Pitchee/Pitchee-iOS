import SwiftUI
import WidgetKit

struct DashboardWidgetEntry: TimelineEntry {
    let date: Date
    let state: DashboardWidgetState
}

struct DashboardWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardWidgetEntry {
        DashboardWidgetEntry(date: .now, state: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardWidgetEntry) -> Void) {
        completion(DashboardWidgetEntry(date: .now, state: DashboardWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardWidgetEntry>) -> Void) {
        let entry = DashboardWidgetEntry(date: .now, state: DashboardWidgetStore.load())
        // shortcut: retain the last Homepage snapshot until app sync; add dated entries for background day rollover.
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct DashboardWidgetEntryView: View {
    let component: DashboardComponent
    let entry: DashboardWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var size: DashboardComponentSize {
        switch family {
        case .systemMedium: .medium
        case .systemLarge: .large
        default: .small
        }
    }

    var body: some View {
        let theme = AppThemeOption(rawValue: entry.state.theme) ?? .twilt
        let appearance: GradientAppearance = colorScheme == .dark ? .dark : .light
        DashboardCard(
            component: component,
            size: size,
            snapshot: entry.state.snapshot,
            preference: entry.state.preference,
            palette: theme.dashboardPalette(for: appearance, contrast: contrast),
            isEditing: false
        )
        .containerBackground(for: .widget) {
            ThemeBackground(
                theme: theme,
                appearance: appearance,
                intensity: colorScheme == .dark ? 0.94 : 0.78
            )
        }
    }
}

struct Widgets: Widget {
    let component: DashboardComponent

    init() { component = .compositeScore }
    init(component: DashboardComponent) { self.component = component }

    private var kind: String {
        component == .compositeScore ? "Widgets" : "com.rolvy.Pitchee.\(component.rawValue)"
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardWidgetProvider()) { entry in
            DashboardWidgetEntryView(component: component, entry: entry)
        }
        .configurationDisplayName(LocalizedStringKey(component.titleKey))
        .supportedFamilies(component.supportsResizing ? [.systemSmall, .systemMedium, .systemLarge] : [.systemSmall])
        .contentMarginsDisabled()
    }
}

#Preview("Voice analyses", as: .systemSmall) {
    Widgets(component: .analysisCount)
} timeline: {
    DashboardWidgetEntry(date: .now, state: .empty)
}

#Preview("Composite score", as: .systemMedium) {
    Widgets(component: .compositeScore)
} timeline: {
    DashboardWidgetEntry(date: .now, state: .empty)
}

#Preview("Mean pitch", as: .systemLarge) {
    Widgets(component: .meanPitch)
} timeline: {
    DashboardWidgetEntry(date: .now, state: .empty)
}
