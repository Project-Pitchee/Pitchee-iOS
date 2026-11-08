//
//  TrendsView.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import SwiftData
import SwiftUI

/// Data changes rebuild the snapshot; the child owns all transient editing
/// state so lifting, hovering and resizing don't recompute recording history.
struct TrendsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \RecordingAssessment.recordedAt, order: .reverse)
    private var assessments: [RecordingAssessment]
    @AppStorage(AppStorageKey.openedDateKeys) private var openedDateKeys = ""
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""
    @Binding var selectedRange: InsightsRange
    var showsRangePicker: Bool
    var onAvailableRangesChange: ([InsightsRange]) -> Void
    @State private var now = Date.now
    @State private var previewHistory: [RecordingAssessment]?

    init(
        range: Binding<InsightsRange>,
        showsRangePicker: Bool = true,
        onAvailableRangesChange: @escaping ([InsightsRange]) -> Void = { _ in }
    ) {
        _selectedRange = range
        self.showsRangePicker = showsRangePicker
        self.onAvailableRangesChange = onAvailableRangesChange
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dashboard-history-preview") {
            let calendar = Calendar.current
            let history = (0..<14).compactMap { index -> RecordingAssessment? in
                guard let day = calendar.date(byAdding: .day, value: -index, to: .now) else { return nil }
                return try? RecordingAssessment(recordedAt: day, result: DebugPreviewData.history[index % DebugPreviewData.history.count])
            }
            _previewHistory = State(initialValue: history)
        }
        #endif
    }

    private var voicePreference: VoicePreference {
        VoicePreference(legacyStoredValue: savedVoicePreference) ?? .undecided
    }

    var body: some View {
        let history = previewHistory ?? assessments
        let configuration = DashboardRangeConfiguration(
            assessments: history,
            selection: selectedRange,
            preference: voicePreference,
            now: now
        )
        // The snapshot and the detail routes use the effective range immediately,
        // including the first frame before the parent picker receives its options.
        let effectiveRange = Binding(
            get: { configuration.selection },
            set: { selectedRange = $0 }
        )
        return DashboardView(
            snapshot: DashboardSnapshot(
                assessments: history,
                openedDateKeys: openedDateKeys,
                range: configuration.selection,
                preference: voicePreference,
                now: now
            ),
            range: effectiveRange,
            preference: voicePreference,
            showsRangePicker: showsRangePicker,
            availableRanges: configuration.ranges
        )
        .onChange(of: configuration, initial: true) { _, configuration in
            if selectedRange != configuration.selection {
                selectedRange = configuration.selection
            }
            onAvailableRangesChange(configuration.ranges)
        }
        .onAppear(perform: refreshDay)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshDay()
        }
    }

    private func refreshDay() {
        #if DEBUG
        if ScreenshotMode.isEnabled {
            now = ScreenshotMode.now
            return
        }
        #endif
        now = .now
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        let today = "\(year)-\(month)-\(day)"
        var dates = Set(openedDateKeys.split(separator: ",").map(String.init))
        guard dates.insert(today).inserted else { return }
        openedDateKeys = dates.sorted().joined(separator: ",")
    }
}
