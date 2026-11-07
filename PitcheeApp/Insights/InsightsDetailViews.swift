//
//  InsightsDetailViews.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/27.
//

import Charts
import SwiftData
import SwiftUI

struct InsightsRangePicker: View {
    @Binding var selection: InsightsRange

    var body: some View {
        Picker("insights.range.label", selection: $selection) {
            ForEach(InsightsRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("insights.range.label")
    }
}

private struct InsightsDetailContent<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                content()
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }
}

private struct InsightsCard<Content: View>: View {
    @AppStorage(AppStorageKey.themeSelection) private var savedTheme = AppThemeOption.twilt.rawValue
    @Environment(\.colorScheme) private var colorScheme
    var interactive = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        let theme = AppThemeOption(rawValue: savedTheme) ?? .twilt
        let palette = theme.dashboardPalette(for: colorScheme == .dark ? .dark : .light)
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(tint: palette.glass, cornerRadius: 20, interactive: interactive, highlight: true)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct InsightsStat: View {
    let title: LocalizedStringKey
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct InsightsEmptyState: View {
    var title: LocalizedStringKey = "insights.history.empty.title"
    var description: LocalizedStringKey = "insights.history.empty.description"
    var symbol = "waveform"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(description)
        }
        .padding(.vertical, 24)
    }
}

struct RecordingHistoryView: View {
    @Query(sort: \RecordingAssessment.recordedAt, order: .reverse)
    private var assessments: [RecordingAssessment]
    let range: InsightsRange
    var now: Date = .now

    var body: some View {
        let calendar = Calendar.current
        let visibleAssessments = InsightsData.assessments(assessments, in: range, relativeTo: now, calendar: calendar)
        let groups = Dictionary(grouping: visibleAssessments) { calendar.startOfDay(for: $0.recordedAt) }
        let groupedDays = groups.keys.sorted(by: >)
        InsightsDetailContent {
            InsightsCard {
                HStack(alignment: .top, spacing: 12) {
                    InsightsStat(title: "insights.summary.analysisCount.title", value: visibleAssessments.count.formatted(), tint: .blue)
                    InsightsStat(title: "insights.history.recordingDays.label", value: groupedDays.count.formatted())
                }
            }

            if visibleAssessments.isEmpty {
                InsightsEmptyState()
            } else {
                ForEach(groupedDays, id: \.self) { day in
                    Section {
                        InsightsRecordingRows(assessments: groups[day] ?? [])
                    } header: {
                        Text(day, format: .dateTime.year().month().day().weekday())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
    }
}

private struct InsightsRecordingRows: View {
    let assessments: [RecordingAssessment]
    private let metric: InsightsMetric = .composite
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""

    private var voicePreference: VoicePreference {
        VoicePreference(legacyStoredValue: savedVoicePreference) ?? .undecided
    }

    var body: some View {
        ForEach(assessments) { assessment in
            NavigationLink {
                RecordingHistoryDetailView(assessment: assessment)
            } label: {
                InsightsCard(interactive: true) {
                    HStack(spacing: 12) {
                        Image(systemName: metric.symbol)
                            .font(.title3)
                            .foregroundStyle(metric.tint)
                            .frame(width: 40, height: 40)
                            .background(metric.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(assessment.recordedAt, format: .dateTime.hour().minute())
                                .font(.headline)
                            Text(Duration.seconds(max(0, assessment.inputSeconds)), format: .units(allowed: [.minutes, .seconds], width: .abbreviated))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(metric.formatted(metric.value(in: assessment, preference: voicePreference)))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(metric.tint)
                            Text(voicePreference.scoreTitleText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("insights.history.record.hint")
        }
    }
}

struct RecordingHistoryDetailView: View {
    let assessment: RecordingAssessment
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""

    private var voicePreference: VoicePreference {
        assessment.recordedTarget
            ?? VoicePreference(legacyStoredValue: savedVoicePreference)
            ?? .undecided
    }

    var body: some View {
        Group {
            if let result = assessment.result {
                RecordingResultView(
                    result: result,
                    volumeStatistics: nil,
                    saveError: nil,
                    quality: assessment.quality,
                    recordedPreference: assessment.recordedTarget,
                    showsBackground: false
                )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            RecordingExportButton(
                                result: result,
                                volumeStatistics: nil,
                                preference: voicePreference
                            )
                                .labelStyle(.iconOnly)
                        }
                    }
            } else {
                ContentUnavailableView {
                    Label("insights.history.unavailable.title", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("insights.history.unavailable.description")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(Text(assessment.recordedAt, format: .dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

struct InsightsMetricDetailView: View {
    @Query(sort: \RecordingAssessment.recordedAt, order: .reverse)
    private var assessments: [RecordingAssessment]
    let metric: InsightsMetric
    let range: InsightsRange
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""

    private var voicePreference: VoicePreference {
        VoicePreference(legacyStoredValue: savedVoicePreference) ?? .undecided
    }

    var body: some View {
        let dailyAssessments = InsightsData.dailyBest(
            InsightsData.assessments(assessments, in: range), preference: voicePreference
        )
        let data = InsightsMetricChartData(assessments: dailyAssessments, metric: metric, preference: voicePreference)
        InsightsDetailContent {
            if data.samples.isEmpty {
                InsightsEmptyState(title: "insights.metric.empty.title", description: "insights.metric.empty.description", symbol: metric.symbol)
            } else {
                InsightsMetricChart(metric: metric, preference: voicePreference, range: range, data: data)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("insights.metric.explanation.title").font(.headline)
                Text(metric.explanation).font(.subheadline).foregroundStyle(.secondary)
                if metric == .composite, voicePreference != .undecided {
                    Text(voicePreference.scoreDirectionDescription).font(.subheadline).foregroundStyle(.secondary)
                }
                Text("insights.metric.dailyBest.description").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Immutable chart inputs are derived when history, range, or preference changes.
/// Scrubbing belongs to the chart below and does not rebuild the history query.
private struct InsightsMetricChartData {
    struct Sample: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    let samples: [Sample]
    let yDomain: ClosedRange<Double>
    let dateDomain: ClosedRange<Date>

    init(assessments: [RecordingAssessment], metric: InsightsMetric, preference: VoicePreference) {
        let calendar = Calendar.current
        samples = assessments.compactMap { assessment in
            metric.value(in: assessment, preference: preference).map {
                Sample(id: assessment.id, date: calendar.startOfDay(for: assessment.recordedAt), value: $0)
            }
        }
        var low = samples.first?.value
        var high = low
        for sample in samples {
            low = min(low ?? sample.value, sample.value)
            high = max(high ?? sample.value, sample.value)
        }
        if metric == .pitch, let low, let high {
            let padding = max(10, (high - low) * 0.2)
            yDomain = max(0, low - padding)...(high + padding)
        } else {
            yDomain = 0...100
        }
        let first = samples.first?.date ?? .now
        let last = samples.last?.date ?? first
        dateDomain = first.addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
    }
}

private struct InsightsMetricChart: View {
    let metric: InsightsMetric
    let preference: VoicePreference
    let range: InsightsRange
    let data: InsightsMetricChartData
    @State private var selectedDate: Date?

    private var metricTitle: String {
        metric == .composite ? preference.scoreTitleText : metric.title
    }

    var body: some View {
        // Resolve selection once, not again for every mark and readout.
        let selectedSample = selectedDate.flatMap { date in
            data.samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        chart(selectedSample: selectedSample)
            .onChange(of: range) { selectedDate = nil }
            .onChange(of: preference) { selectedDate = nil }
    }

    private func chart(selectedSample: InsightsMetricChartData.Sample?) -> some View {
        Chart {
            ForEach(data.samples) { sample in
                if data.samples.count > 1 {
                    AreaMark(
                        x: .value(String(localized: "insights.chart.date.label"), sample.date),
                        yStart: .value(String(localized: "insights.chart.baseline.label"), data.yDomain.lowerBound),
                        yEnd: .value(metricTitle, sample.value)
                    )
                    .foregroundStyle(LinearGradient(colors: [metric.tint.opacity(0.20), metric.tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value(String(localized: "insights.chart.date.label"), sample.date), y: .value(metricTitle, sample.value))
                        .foregroundStyle(metric.tint)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                PointMark(x: .value(String(localized: "insights.chart.date.label"), sample.date), y: .value(metricTitle, sample.value))
                    .foregroundStyle(metric.tint)
                    .symbolSize(sample.id == selectedSample?.id ? 80 : 35)
                    .accessibilityLabel(Text(sample.date, format: .dateTime.month().day()))
                    .accessibilityValue(Text(verbatim: "\(metric.formatted(sample.value)) \(metric.unit)"))
            }
            if let selectedSample {
                RuleMark(x: .value(String(localized: "insights.chart.date.label"), selectedSample.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(
                        position: .top, alignment: .leading,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(verbatim: "\(metric.formatted(selectedSample.value)) \(metric.unit)")
                            .font(.caption.weight(.semibold))
                    }
            }
        }
        .chartXScale(domain: data.dateDomain)
        .chartYScale(domain: data.yDomain)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
        .chartYAxisLabel(metric.unit)
        .chartXSelection(value: $selectedDate)
        .frame(height: 220)
        .accessibilityLabel(metricTitle)
    }
}

struct InsightsActivityView: View {
    @Query(sort: \RecordingAssessment.recordedAt, order: .reverse)
    private var assessments: [RecordingAssessment]
    @AppStorage(AppStorageKey.openedDateKeys) private var openedDateKeys = ""
    @AppStorage(AppStorageKey.themeSelection) private var savedTheme = AppThemeOption.twilt.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let range: InsightsRange
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private var calendar: Calendar { .current }
    private var openedDates: Set<Date> {
        InsightsData.openedDates(from: openedDateKeys).filter { range.contains($0) }
    }
    private var visibleAssessments: [RecordingAssessment] {
        InsightsData.assessments(assessments, in: range)
    }
    private var recordingDates: Set<Date> {
        Set(visibleAssessments.map { calendar.startOfDay(for: $0.recordedAt) })
    }
    private var earliestDate: Date {
        range.startDate() ?? min(openedDates.min() ?? .now, visibleAssessments.last?.recordedAt ?? .now)
    }

    var body: some View {
        let theme = AppThemeOption(rawValue: savedTheme) ?? .twilt
        let palette = theme.dashboardPalette(
            for: colorScheme == .dark ? .dark : .light,
            contrast: colorSchemeContrast
        )
        InsightsDetailContent {
            InsightsCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        InsightsStat(title: "insights.summary.openedDays.title", value: openedDates.count.formatted(), tint: palette.secondary)
                        InsightsStat(title: "insights.history.recordingDays.label", value: recordingDates.count.formatted(), tint: palette.accent)
                        InsightsStat(title: "insights.activity.longestStreak.label", value: InsightsData.longestStreak(in: openedDates).formatted())
                    }
                    Text("insights.activity.description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            InsightsCard {
                InsightsActivityCalendar(
                    selectedDay: $selectedDay,
                    availableDates: availableDates,
                    openedDates: openedDates,
                    recordingDates: recordingDates,
                    openedTint: palette.secondary,
                    recordingTint: palette.accent
                )
            }
        }
        .onChange(of: range) {
            if !range.contains(selectedDay) { selectedDay = calendar.startOfDay(for: .now) }
        }
    }

    private var availableDates: DateInterval {
        let today = calendar.startOfDay(for: .now)
        let firstDay = range.startDate()
            ?? calendar.dateInterval(of: .month, for: earliestDate)?.start
            ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        return DateInterval(start: min(firstDay, today), end: tomorrow.addingTimeInterval(-1))
    }
}

#if DEBUG
private struct InsightsDetailPreview: View {
    let destination: InsightsDestination
    private let range: InsightsRange = .all

    var body: some View {
        Group {
            switch destination {
            case .history:
                NavigationStack {
                    RecordingHistoryView(range: range)
                        .toolbar(.hidden, for: .navigationBar)
                }
            case .activity: InsightsActivityView(range: range)
            case .metric(let metric): InsightsMetricDetailView(metric: metric, range: range)
            }
        }
        .defaultAppStorage(DebugPreviewDefaults.store)
    }
}

#Preview("Insights - Recording History") {
    if let container = DebugPreviewStore.makeContainer(withHistory: true) {
        InsightsDetailPreview(destination: .history).modelContainer(container)
    }
}

#Preview("Insights - Activity") {
    InsightsDetailPreview(destination: .activity)
        .modelContainer(for: RecordingAssessment.self, inMemory: true)
}

#Preview("Insights - Score Trend") {
    if let container = DebugPreviewStore.makeContainer(withHistory: true) {
        InsightsDetailPreview(destination: .metric(.composite)).modelContainer(container)
    }
}

#Preview("Insights - Naturalness Trend") {
    if let container = DebugPreviewStore.makeContainer(withHistory: true) {
        InsightsDetailPreview(destination: .metric(.naturalness)).modelContainer(container)
    }
}

#Preview("Insights - Pitch Empty") {
    InsightsDetailPreview(destination: .metric(.pitch))
        .modelContainer(for: RecordingAssessment.self, inMemory: true)
}
#endif
