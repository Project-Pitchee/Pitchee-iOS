//
//  InsightsData.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/27.
//

import Foundation
import SwiftUI

enum InsightsRange: String, CaseIterable, Identifiable {
    case sevenDays, thirtyDays, ninetyDays, all

    var id: Self { self }

    var title: String {
        switch self {
        case .sevenDays: String(localized: "insights.range.sevenDays")
        case .thirtyDays: String(localized: "insights.range.thirtyDays")
        case .ninetyDays: String(localized: "insights.range.ninetyDays")
        case .all: String(localized: "insights.range.all")
        }
    }

    func startDate(relativeTo date: Date = .now, calendar: Calendar = .current) -> Date? {
        let days: Int
        switch self {
        case .sevenDays: days = 7
        case .thirtyDays: days = 30
        case .ninetyDays: days = 90
        case .all: return nil
        }
        // Today is one of the selected days, including across daylight-saving changes.
        return calendar.date(byAdding: .day, value: 1 - days, to: calendar.startOfDay(for: date))
    }

    func contains(_ date: Date, relativeTo now: Date = .now, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day <= calendar.startOfDay(for: now)
            && startDate(relativeTo: now, calendar: calendar).map { day >= $0 } != false
    }
}

enum InsightsMetric: String, CaseIterable, Identifiable {
    case composite, naturalness, pitch, variation

    var hasBestView: Bool { self == .composite || self == .naturalness }

    var id: Self { self }

    var title: String {
        switch self {
        case .composite: String(localized: "common.metric.compositeScore.title")
        case .naturalness: String(localized: "common.metric.naturalness.title")
        case .pitch: String(localized: "common.metric.meanPitch.title")
        case .variation: String(localized: "practice.metric.variation")
        }
    }

    var explanation: String {
        switch self {
        case .composite: String(localized: "insights.metric.compositeScore.description")
        case .naturalness: String(localized: "insights.metric.naturalness.description")
        case .pitch: String(localized: "insights.metric.meanPitch.description")
        case .variation: String(localized: "practice.kind.pitchStability.instruction")
        }
    }

    var symbol: String {
        switch self {
        case .composite: "chart.line.uptrend.xyaxis"
        case .naturalness: "waveform.path.ecg"
        case .pitch: "tuningfork"
        case .variation: "waveform.path"
        }
    }

    var tint: Color {
        switch self {
        case .composite: Color.pitcheeAccent
        case .naturalness: .teal
        case .pitch: .orange
        case .variation: .purple
        }
    }

    var unit: String {
        !hasBestView
            ? String(localized: "common.unit.hertz")
            : String(localized: "common.unit.pointsOutOf100")
    }

    func value(in assessment: RecordingAssessment, preference: VoicePreference = .undecided) -> Double? {
        let value: Double?
        switch self {
        case .composite: value = assessment.finalScore(for: preference)
        case .naturalness: value = assessment.naturalnessScore
        case .pitch: value = assessment.meanPitchHz
        case .variation: value = assessment.pitchVariationHz
        }
        guard let value, value.isFinite, value >= 0, self != .pitch || value > 0 else { return nil }
        return value
    }

    func formatted(_ value: Double?) -> String {
        guard let value, value.isFinite else { return String(localized: "common.placeholder.noValue") }
        return value.formatted(.number.precision(.fractionLength(hasBestView ? 0 : 1)))
    }
}

enum InsightsDestination: Hashable {
    case history, activity, metric(InsightsMetric)
}

enum InsightsData {
    static func comparable(_ assessments: [RecordingAssessment], cohort: PracticeCohort) -> [RecordingAssessment] {
        assessments.filter { $0.isBaselineEligible && $0.cohort == cohort }
    }

    static func dailySummary(
        _ assessments: [RecordingAssessment], cohort: PracticeCohort, metric: InsightsMetric,
        calendar: Calendar = .current
    ) -> [DailyPracticeSummary] {
        Dictionary(grouping: comparable(assessments, cohort: cohort)) { calendar.startOfDay(for: $0.recordedAt) }
            .compactMap { date, records in
                DailyPracticeSummary(date: date, values: records.compactMap { record in
                    if metric == .composite { return record.capturedFinalScore }
                    return metric.value(in: record)
                })
            }.sorted { $0.date < $1.date }
    }

    static func assessments(
        _ assessments: [RecordingAssessment],
        in range: InsightsRange,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> [RecordingAssessment] {
        let today = calendar.startOfDay(for: now)
        let start = range.startDate(relativeTo: now, calendar: calendar)
        return assessments.filter {
            let day = calendar.startOfDay(for: $0.recordedAt)
            return day <= today && start.map { day >= $0 } != false
        }
    }

    /// Every metric uses the same daily representative as the home dashboard.
    static func dailyBest(
        _ assessments: [RecordingAssessment], calendar: Calendar = .current,
        preference: VoicePreference = .undecided
    ) -> [RecordingAssessment] {
        var bestByDay: [Date: (assessment: RecordingAssessment, score: Double)] = [:]
        for assessment in assessments {
            let day = calendar.startOfDay(for: assessment.recordedAt)
            let score = assessment.finalScore(for: preference)
            if let current = bestByDay[day] {
                guard current.score < score
                    || (current.score == score && current.assessment.recordedAt < assessment.recordedAt)
                else { continue }
            }
            bestByDay[day] = (assessment, score)
        }
        return bestByDay.values.map(\.assessment)
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    static func openedDates(from storedKeys: String, calendar: Calendar = .current) -> Set<Date> {
        Set(storedKeys.split(separator: ",").compactMap { key -> Date? in
            let parts = key.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
                  let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
            else { return nil }
            let actual = calendar.dateComponents([.year, .month, .day], from: date)
            // Calendar.date normalizes invalid dates; persisted keys must match exactly.
            guard actual.year == year, actual.month == month, actual.day == day else { return nil }
            return calendar.startOfDay(for: date)
        })
    }

    static func longestStreak(in dates: Set<Date>, calendar: Calendar = .current) -> Int {
        var previous: Date?
        var current = 0
        var longest = 0
        for date in dates.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == date {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = date
        }
        return longest
    }

}
