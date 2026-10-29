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

private struct InsightsPage<Content: View>: View {
    let title: String
    @Binding var range: InsightsRange
    var usesThemeBackground = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                InsightsRangePicker(selection: $range)
                content()
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background {
            if usesThemeBackground {
                AppThemeBackground()
            } else {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(usesThemeBackground ? .hidden : .automatic, for: .navigationBar)
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
        InsightsCard {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(description)
            }
            .padding(.vertical, 24)
        }
    }
}

struct RecordingHistoryView: View {
    @Query(sort: \RecordingAssessment.recordedAt, order: .reverse)
    private var assessments: [RecordingAssessment]
    @Binding var range: InsightsRange

    var body: some View {
        let calendar = Calendar.current
        let visibleAssessments = InsightsData.assessments(assessments, in: range, calendar: calendar)
        let groups = Dictionary(grouping: visibleAssessments) { calendar.startOfDay(for: $0.recordedAt) }
        let groupedDays = groups.keys.sorted(by: >)
        let seconds = visibleAssessments.reduce(0) { $0 + max(0, $1.speechSeconds) }
        let speechDuration = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
        InsightsPage(title: String(localized: "insights.history.title"), range: $range, usesThemeBackground: false) {
            InsightsCard {
                HStack(alignment: .top, spacing: 12) {
                    InsightsStat(title: "insights.summary.analysisCount.title", value: visibleAssessments.count.formatted(), tint: .blue)
                    InsightsStat(title: "insights.history.recordingDays.label", value: groupedDays.count.formatted())
                    InsightsStat(title: "common.metric.speechDuration.title", value: speechDuration)
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
    @Query(sort: \RecordingAssessment.recordedAt, order: .reverse)
    private var assessments: [RecordingAssessment]

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
                    playbackAudioURL: assessment.audioFileName.flatMap {
                        RecordingAudioStore.url(for: $0)
                    },
                    previousScore: previousMetrics?.finalScore,
                    previousMetrics: previousMetrics,
                    animatesScore: false,
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
        .toolbarBackground(.automatic, for: .navigationBar)
    }

    private var previousMetrics: PreviousScoreMetrics? {
        guard let previous = assessments.first(where: { $0.recordedAt < assessment.recordedAt }) else {
            return nil
        }
        if let previousResult = previous.result {
            let score = voicePreference.score(for: previousResult)
            return PreviousScoreMetrics(
                finalScore: score.finalScore,
                standardScore: score.standardScore,
                naturalnessScore: score.naturalnessScore,
                meanPitchHz: previousResult.f0.meanHz
            )
        }
        return PreviousScoreMetrics(
            finalScore: previous.finalScore(for: voicePreference),
            standardScore: voicePreference == .masculine
                ? 100 - previous.standardScore
                : previous.standardScore,
            naturalnessScore: previous.naturalnessScore,
            meanPitchHz: previous.meanPitchHz
        )
    }
}

struct InsightsMetricDetailView: View {
    @Query(sort: \RecordingAssessment.recordedAt, order: .reverse)
    private var assessments: [RecordingAssessment]
    let metric: InsightsMetric
    @Binding var range: InsightsRange
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""

    private var voicePreference: VoicePreference {
        VoicePreference(legacyStoredValue: savedVoicePreference) ?? .undecided
    }

    private var metricTitle: String {
        metric == .composite ? voicePreference.scoreTitleText : metric.title
    }

    var body: some View {
        let dailyAssessments = InsightsData.dailyBest(
            InsightsData.assessments(assessments, in: range), preference: voicePreference
        )
        let data = InsightsMetricChartData(assessments: dailyAssessments, metric: metric, preference: voicePreference)
        InsightsPage(title: metricTitle, range: $range) {
            InsightsMetricChartCard(metric: metric, preference: voicePreference, range: range, data: data)

            InsightsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("insights.metric.explanation.title").font(.headline)
                    Text(metric.explanation).font(.subheadline).foregroundStyle(.secondary)
                    if metric == .composite, voicePreference != .undecided {
                        Text(voicePreference.scoreDirectionDescription).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("insights.metric.dailyBest.description").font(.caption).foregroundStyle(.secondary)
                }
            }

            if data.samples.isEmpty {
                InsightsEmptyState(title: "insights.metric.empty.title", description: "insights.metric.empty.description", symbol: metric.symbol)
            }
        }
    }

}

/// Immutable chart inputs are derived when history, range, or preference changes.
/// Scrubbing belongs to the card below and does not rebuild the history query.
private struct InsightsMetricChartData {
    struct Sample: Identifiable {
        let id: UUID
        let date: Date
        let recordedAt: Date
        let value: Double
    }

    let samples: [Sample]
    let latestValue: Double?
    let latestRecordedAt: Date?
    let average: Double?
    let minimum: Double?
    let maximum: Double?
    let yDomain: ClosedRange<Double>
    let dateDomain: ClosedRange<Date>

    init(assessments: [RecordingAssessment], metric: InsightsMetric, preference: VoicePreference) {
        let calendar = Calendar.current
        samples = assessments.compactMap { assessment in
            metric.value(in: assessment, preference: preference).map {
                Sample(id: assessment.id, date: calendar.startOfDay(for: assessment.recordedAt),
                       recordedAt: assessment.recordedAt, value: $0)
            }
        }
        latestValue = assessments.last.flatMap { metric.value(in: $0, preference: preference) }
        latestRecordedAt = assessments.last?.recordedAt
        var low = samples.first?.value
        var high = low
        var total = 0.0
        for sample in samples {
            low = min(low ?? sample.value, sample.value)
            high = max(high ?? sample.value, sample.value)
            total += sample.value
        }
        minimum = low
        maximum = high
        average = samples.isEmpty ? nil : total / Double(samples.count)
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

private struct InsightsMetricChartCard: View {
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
        InsightsCard {
            VStack(alignment: .leading, spacing: 18) {
                Label(metricTitle, systemImage: metric.symbol)
                    .font(.headline)
                    .foregroundStyle(metric.tint)
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDate == nil ? "insights.metric.latest.label" : "insights.metric.selected.label")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // A missing pitch for the latest day remains missing, as on the home card.
                        Text(metric.formatted(selectedSample?.value ?? data.latestValue))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(metric.tint)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(metric.unit).foregroundStyle(.secondary)
                    }
                    if let date = selectedSample?.recordedAt ?? data.latestRecordedAt {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !data.samples.isEmpty {
                    chart(selectedSample: selectedSample)
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        InsightsStat(title: "insights.metric.average.label", value: metric.formatted(data.average))
                        InsightsStat(title: "insights.metric.minimum.label", value: metric.formatted(data.minimum))
                        InsightsStat(title: "insights.metric.maximum.label", value: metric.formatted(data.maximum))
                    }
                }
            }
        }
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
            }
        }
        .chartXScale(domain: data.dateDomain)
        .chartYScale(domain: data.yDomain)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
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
    @Binding var range: InsightsRange
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
        InsightsPage(title: String(localized: "insights.activity.title"), range: $range) {
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
    @State private var range: InsightsRange = .all

    var body: some View {
        NavigationStack {
            switch destination {
            case .history: RecordingHistoryView(range: $range)
            case .activity: InsightsActivityView(range: $range)
            case .metric(let metric): InsightsMetricDetailView(metric: metric, range: $range)
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
