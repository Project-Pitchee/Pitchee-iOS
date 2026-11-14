import Foundation

/// Time options depend on all recorded days, while equivalent ranges are
/// compared using every recording so counts and history keep the same scope.
struct DashboardRangeConfiguration: Equatable {
    let ranges: [InsightsRange]
    let selection: InsightsRange
    let totalRecordDays: Int

    init(
        assessments: [RecordingAssessment],
        selection: InsightsRange,
        preference: VoicePreference,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let history = InsightsData.assessments(assessments, in: .all, relativeTo: now, calendar: calendar)
        totalRecordDays = InsightsData.dailyBest(history, calendar: calendar, preference: preference).count

        // Keep the existing empty-history presentation outside this adaptation.
        guard totalRecordDays > 0 else {
            ranges = InsightsRange.allCases
            self.selection = selection
            return
        }
        guard totalRecordDays > 3 else {
            ranges = []
            self.selection = .all
            return
        }

        func recordingIDs(in range: InsightsRange) -> Set<UUID> {
            Set(InsightsData.assessments(history, in: range, relativeTo: now, calendar: calendar).map(\.id))
        }
        // Keep empty periods selectable without changing the options on selection.
        guard !recordingIDs(in: .sevenDays).isEmpty else {
            ranges = InsightsRange.allCases
            self.selection = selection
            return
        }

        let allIDs = Set(history.map(\.id))
        var distinct: [(range: InsightsRange, ids: Set<UUID>)] = []
        for range in InsightsRange.allCases where range != .all {
            let ids = recordingIDs(in: range)
            guard ids != allIDs, !distinct.contains(where: { $0.ids == ids }) else { continue }
            distinct.append((range, ids))
        }
        distinct.append((.all, allIDs))
        guard distinct.count > 1 else {
            ranges = []
            self.selection = .all
            return
        }
        ranges = distinct.map(\.range)
        let selectedIDs = recordingIDs(in: selection)
        self.selection = distinct.first(where: { $0.ids == selectedIDs })?.range ?? .all
    }
}

extension DashboardSnapshot.Averages {
    @MainActor
    init(assessments: [RecordingAssessment], preference: VoicePreference) {
        func average(_ metric: InsightsMetric) -> Double? {
            let values = assessments.compactMap { metric.value(in: $0, preference: preference) }
            guard !values.isEmpty else { return nil }
            return values.reduce(0) { $0 + $1 / Double(values.count) }
        }
        finalScore = average(.composite)
        naturalnessScore = average(.naturalness)
        meanPitchHz = average(.pitch)
    }
}

extension DashboardSnapshot {
    /// Read model fields here so edits to existing SwiftData rows remain observable.
    @MainActor
    init(
        assessments: [RecordingAssessment],
        openedDateKeys: String,
        range: InsightsRange,
        preference: VoicePreference,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let visible = InsightsData.assessments(assessments, in: range, relativeTo: now, calendar: calendar)
        let dailyBest = InsightsData.dailyBest(visible, calendar: calendar, preference: preference)
        referenceDate = now
        assessmentCount = visible.count
        recordDayCount = dailyBest.count
        openedDays = InsightsData.openedDates(from: openedDateKeys, calendar: calendar)
            .filter { range.contains($0, relativeTo: now, calendar: calendar) }.count
        averages = Averages(assessments: Array(dailyBest.dropLast()), preference: preference)
        latestDate = dailyBest.last?.recordedAt
        latestScore = dailyBest.last.flatMap { InsightsMetric.composite.value(in: $0, preference: preference) }
        latestNaturalness = dailyBest.last.flatMap { InsightsMetric.naturalness.value(in: $0) }
        latestPitch = dailyBest.last.flatMap { InsightsMetric.pitch.value(in: $0) }

        func points(for metric: InsightsMetric) -> [DashboardTrendPoint] {
            var result: [DashboardTrendPoint] = []
            result.reserveCapacity(dailyBest.count)
            for assessment in dailyBest {
                guard let value = metric.value(in: assessment, preference: preference) else { continue }
                result.append(DashboardTrendPoint(
                    id: assessment.id,
                    date: calendar.startOfDay(for: assessment.recordedAt),
                    value: value,
                    position: Double(result.count)
                ))
            }
            return result
        }
        scorePoints = points(for: .composite)
        naturalnessPoints = points(for: .naturalness)
        pitchPoints = points(for: .pitch)
    }
}
