import SwiftData
import SwiftUI

/// Keep desktop widgets current even when a recording or setting changes on another tab.
struct DashboardWidgetSync: ViewModifier {
    let range: InsightsRange
    @Query(sort: \RecordingAssessment.recordedAt, order: .reverse)
    private var assessments: [RecordingAssessment]
    @AppStorage(AppStorageKey.openedDateKeys) private var openedDateKeys = ""
    @AppStorage(AppStorageKey.voicePreference) private var savedPreference = ""
    @AppStorage(AppStorageKey.themeSelection) private var savedTheme = AppThemeOption.twilt.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now

    func body(content: Content) -> some View {
        let state = state(at: now)
        content
            .onChange(of: state, initial: true) { _, state in save(state) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active || phase == .background { refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
    }

    private func state(at date: Date) -> DashboardWidgetState {
        let preference = VoicePreference(legacyStoredValue: savedPreference) ?? .undecided
        let configuration = DashboardRangeConfiguration(
            assessments: assessments, selection: range, preference: preference, now: date
        )
        return DashboardWidgetState(
            snapshot: DashboardSnapshot(
                assessments: assessments, openedDateKeys: openedDateKeys,
                range: configuration.selection, preference: preference, now: date
            ),
            preference: preference, theme: savedTheme
        )
    }

    private func refresh() {
        now = .now
        save(state(at: now))
    }

    private func save(_ state: DashboardWidgetState) {
        #if DEBUG
        guard !ScreenshotMode.isEnabled,
              ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              !ProcessInfo.processInfo.arguments.contains("-dashboard-history-preview") else { return }
        #endif
        DashboardWidgetStore.save(state)
    }
}
