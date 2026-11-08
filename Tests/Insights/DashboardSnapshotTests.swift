//
//  DashboardSnapshotTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import Foundation

@main
enum DashboardSnapshotTests {
    @MainActor
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        let now = date(10, 7)
        func assessment(_ recordedAt: Date, score: Double, pitch: Double? = 175,
                        standard: Double = 65, naturalness: Double = 70) throws -> RecordingAssessment {
            let result = PitcheeAnalysisResult(
                schemaVersion: 2, modelVersion: "dashboard-tests", scoreProfile: nil,
                audio: .init(sourceSampleRate: 16_000, sourceChannels: 1, inputSeconds: 12, analyzedSeconds: 12),
                vad: .init(segmentCount: 0, speechSeconds: 10, sileroSegmentCount: 0,
                           discardedBreathLikeCount: 0, trimmedSegmentCount: 0, segments: []),
                f0: .init(windowSeconds: 0.5, meanHz: pitch, standardDeviationHz: nil,
                          voicedFrameCount: 0, voicedWindowCount: 0, windows: []),
                vfp: .init(vfpStandardScore: standard, windowCount: 0, windowDurationSeconds: 1, windows: []),
                naturalness: .init(score: naturalness, windowCount: 0, windowDurationSeconds: 1, windows: []),
                composite: .init(baseScore: score, finalScore: score, cap: nil,
                                 rule: "continuous", limited: false, boosted: false)
            )
            return try RecordingAssessment(recordedAt: recordedAt, result: result)
        }
        func snapshot(_ assessments: [RecordingAssessment], openedDates: String = "",
                      range: InsightsRange = .sevenDays, preference: VoicePreference = .undecided,
                      relativeTo referenceDate: Date? = nil) -> DashboardSnapshot {
            DashboardSnapshot(assessments: assessments, openedDateKeys: openedDates, range: range,
                              preference: preference, now: referenceDate ?? now, calendar: calendar)
        }

        let empty = snapshot([])
        check(empty.assessmentCount == 0 && empty.openedDays == 0, "An empty dashboard has no counts")
        check(empty.recordDayCount == 0 && empty.latestDate == nil,
              "An empty dashboard has no recorded day or representative date")
        check(empty.latestScore == nil && empty.latestNaturalness == nil && empty.latestPitch == nil,
              "An empty dashboard has no latest values")
        check(empty.scorePoints.isEmpty && empty.naturalnessPoints.isEmpty && empty.pitchPoints.isEmpty,
              "An empty dashboard has no chart points")
        check(empty.averages.finalScore == nil && empty.averages.naturalnessScore == nil
              && empty.averages.meanPitchHz == nil, "An empty dashboard has no baseline")

        let first = try assessment(date(10, 1, 8), score: 80, pitch: 120, naturalness: 65)
        let tiedLater = try assessment(date(10, 1, 10), score: 80, pitch: 200, naturalness: 75)
        let sameDayLower = try assessment(date(10, 1, 11), score: 70, pitch: 300, naturalness: 90)
        let middle = try assessment(date(10, 5), score: 40, pitch: 140, naturalness: 50)
        let latest = try assessment(date(10, 7), score: 90, pitch: 180, naturalness: 95)
        let old = try assessment(date(9, 30), score: 100, pitch: 250, naturalness: 10)
        let future = try assessment(date(10, 8), score: 99)
        let history = [future, latest, sameDayLower, old, first, middle, tiedLater]
        let openedDates = "2026-9-30,2026-10-1,2026-10-01,2026-10-5,2026-10-7,2026-10-8,invalid"
        let weekly = snapshot(history, openedDates: openedDates)
        check(weekly.referenceDate == now,
              "Dashboard details share the snapshot's reference date rather than the wall clock")
        check(weekly.assessmentCount == 5, "The count includes every recording in the range, not only daily winners")
        check(weekly.recordDayCount == 3 && weekly.latestDate == latest.recordedAt,
              "Recorded days and the latest date follow daily representatives, not recording count")
        check(weekly.openedDays == 3, "Opened days use the same range and deduplicate equivalent date keys")
        check(weekly.scorePoints.map(\.id) == [tiedLater.id, middle.id, latest.id],
              "Daily winners break score ties by recency and appear in chronological order")
        check(weekly.naturalnessPoints.map(\.id) == weekly.scorePoints.map(\.id)
              && weekly.pitchPoints.map(\.id) == weekly.scorePoints.map(\.id),
              "All charts use the same daily recording even when another recording has a higher metric")
        check(weekly.scorePoints.map(\.position) == [0, 1, 2]
              && weekly.scorePoints[0].date == calendar.startOfDay(for: first.recordedAt),
              "Points use compact positions and calendar-day dates")
        check(weekly.latestScore == 90 && weekly.latestNaturalness == 95 && weekly.latestPitch == 180,
              "Latest values come from the newest daily winner")
        check(weekly.averages.finalScore == 60 && weekly.averages.naturalnessScore == 62.5
              && weekly.averages.meanPitchHz == 170,
              "Baselines average prior daily winners and exclude the latest day")
        let single = snapshot([latest])
        check(single.latestScore == 90 && single.averages.finalScore == nil,
              "A single daily winner has a latest value but no previous baseline")
        let monthly = snapshot(history, openedDates: openedDates, range: .thirtyDays)
        check(monthly.assessmentCount == 6 && monthly.openedDays == 4,
              "Changing range refreshes recording and activity counts together")
        check(monthly.scorePoints.first?.id == old.id && monthly.scorePoints.last?.id == latest.id,
              "A larger range includes old history and still excludes future days")
        let nextDay = snapshot(history, openedDates: openedDates, relativeTo: date(10, 8))
        check(nextDay.assessmentCount == 3 && nextDay.latestScore == 99 && nextDay.openedDays == 3,
              "Advancing the reference day expires the old boundary and includes the new day")

        latest.meanPitchHz = nil
        let missingLatestPitch = snapshot(history)
        check(missingLatestPitch.latestPitch == nil && missingLatestPitch.pitchPoints.map(\.value) == [200, 140],
              "A missing latest pitch does not reuse an older value as the latest reading")
        check(missingLatestPitch.averages.meanPitchHz == 170,
              "A missing latest metric does not change the previous-days baseline")
        check(weekly.latestPitch == 180 && weekly.pitchPoints.last?.value == 180,
              "An existing snapshot retains its scalar values when the source model changes")
        latest.meanPitchHz = 180

        let beforeMutation = snapshot(history)
        tiedLater.finalScore = 50
        first.meanPitchHz = 160
        first.naturalnessScore = 68
        latest.finalScore = 92
        let afterMutation = snapshot(history)
        check(afterMutation.scorePoints.first?.id == first.id && afterMutation.latestScore == 92,
              "Rebuilding from the same model instances reselects daily winners and reads edited scores")
        check(afterMutation.pitchPoints.first?.value == 160 && afterMutation.averages.meanPitchHz == 150
              && afterMutation.averages.naturalnessScore == 59,
              "Rebuilding reads edited scalar metrics and recalculates the prior-days baseline")
        check(beforeMutation.scorePoints.first?.id == tiedLater.id && beforeMutation.latestScore == 90,
              "A previous snapshot does not retain mutable assessment references")
        latest.recordedAt = date(9, 1)
        let changedDate = snapshot(history)
        check(changedDate.assessmentCount == 4 && changedDate.latestScore == middle.finalScore,
              "Editing an existing recording date updates range membership without changing array identity")
        check(changedDate.latestDate == middle.recordedAt && weekly.latestDate == date(10, 7),
              "Representative dates refresh in new snapshots without changing an existing snapshot")

        let masculine = try assessment(date(10, 1, 8), score: 20, pitch: 120, standard: 20, naturalness: 100)
        let feminine = try assessment(date(10, 1, 9), score: 100, pitch: 200, standard: 90, naturalness: 100)
        let directionalHistory = [masculine, feminine]
        let masculineSnapshot = snapshot(directionalHistory, preference: .masculine)
        let feminineSnapshot = snapshot(directionalHistory, preference: .feminine)
        check(masculineSnapshot.scorePoints.first?.id == masculine.id
              && feminineSnapshot.scorePoints.first?.id == feminine.id,
              "Changing voice preference reselects daily winners")
        check(masculineSnapshot.latestScore == 84 && feminineSnapshot.latestScore == 100,
              "Directional latest values and chart values use the same scoring rules")
        masculine.resultPayload = feminine.resultPayload
        let replacedPayload = snapshot(directionalHistory, preference: .masculine)
        check(replacedPayload.scorePoints.first?.id == feminine.id
              && replacedPayload.latestScore == feminine.finalScore(for: .masculine),
              "Replacing payload bytes on the same model invalidates directional scoring caches")

        let invalidPitchRecords = try (1...4).map { try assessment(date(10, $0), score: 70) }
        for (record, invalidValue) in zip(invalidPitchRecords, [-10.0, .nan, .infinity, 0.0]) {
            record.meanPitchHz = invalidValue
        }
        let validPast = try assessment(date(10, 5), score: 75, pitch: 150)
        let validLatest = try assessment(date(10, 7), score: 80, pitch: 180)
        let invalidHistory = invalidPitchRecords + [validPast, validLatest]
        let sanitized = snapshot(invalidHistory)
        check(sanitized.assessmentCount == 6 && sanitized.scorePoints.count == 6,
              "Invalid pitch does not discard the recording or its valid score")
        check(sanitized.recordDayCount == 6,
              "A missing individual metric does not discard an otherwise recorded day")
        check(sanitized.pitchPoints.map(\.value) == [150, 180]
              && sanitized.pitchPoints.map(\.position) == [0, 1],
              "Negative, zero, NaN, and infinite pitch values are excluded without leaving chart gaps")
        check(sanitized.averages.meanPitchHz == 150,
              "Pitch baselines apply the same positive finite validation as current values and charts")
        for invalidValue in [-10.0, Double.nan, .infinity, 0.0] {
            validLatest.meanPitchHz = invalidValue
            let invalidLatest = snapshot(invalidHistory)
            check(invalidLatest.latestPitch == nil && invalidLatest.pitchPoints.map(\.value) == [150],
                  "Every invalid latest pitch is unavailable and cannot enter the chart domain")
        }

        let rangeNow = date(11, 8)
        func records(daysAgo offsets: [Int]) throws -> [RecordingAssessment] {
            try offsets.enumerated().map { index, offset in
                let recordedAt = calendar.date(byAdding: .day, value: -offset, to: rangeNow)!
                return try assessment(recordedAt, score: 80 + Double(index * 7 % 17))
            }
        }
        func configuration(_ records: [RecordingAssessment], selection: InsightsRange = .all,
                           preference: VoicePreference = .undecided) -> DashboardRangeConfiguration {
            DashboardRangeConfiguration(assessments: records, selection: selection, preference: preference,
                                        now: rangeNow, calendar: calendar)
        }
        let oneDay = try records(daysAgo: [0])
        let sparseDays = try records(daysAgo: [0, 36, 57])
        let fourDays = try records(daysAgo: Array(0..<4))
        let fortnight = try records(daysAgo: Array(0..<14))
        let twoMonths = try records(daysAgo: Array(stride(from: 0, to: 60, by: 2)))
        let longHistory = try records(daysAgo: Array(stride(from: 0, to: 180, by: 2)))
        let interruptedHistory = try records(daysAgo: [0, 5, 37, 57, 83])
        let filteredSingleHistory = try records(daysAgo: [0, 14, 29, 38])
        let scenarios: [(name: String, records: [RecordingAssessment], ranges: [InsightsRange],
                         requested: InsightsRange, effective: InsightsRange)] = [
            ("One recorded day", oneDay, [], .sevenDays, .all),
            ("Three sparse recorded days", sparseDays, [], .sevenDays, .all),
            ("Four recent recorded days", fourDays, [], .sevenDays, .all),
            ("Two weeks of history", fortnight, [.sevenDays, .all], .all, .all),
            ("Two months of history", twoMonths, [.sevenDays, .thirtyDays, .all], .all, .all),
            ("More than three months", longHistory, InsightsRange.allCases, .all, .all),
            ("Interrupted history", interruptedHistory, [.sevenDays, .all], .thirtyDays, .sevenDays),
            ("A selected range with one day", filteredSingleHistory,
             [.sevenDays, .thirtyDays, .all], .sevenDays, .sevenDays)
        ]
        for scenario in scenarios {
            let config = configuration(scenario.records, selection: scenario.requested)
            check(config.ranges == scenario.ranges, "\(scenario.name) has the expected distinct time options")
            check(config.selection == scenario.effective, "\(scenario.name) preserves the intended record scope")
            check(config.totalRecordDays == scenario.records.count,
                  "\(scenario.name) counts all recorded days independently of the selected period")
            let display = snapshot(scenario.records, range: config.selection, relativeTo: rangeNow)
            let expected = InsightsData.assessments(scenario.records, in: config.selection,
                                                   relativeTo: rangeNow, calendar: calendar)
            check(display.assessmentCount == expected.count,
                  "\(scenario.name) applies the resolved range to displayed recording counts")
        }

        let selectedSingle = configuration(filteredSingleHistory, selection: .sevenDays)
        let selectedSingleSnapshot = snapshot(filteredSingleHistory, range: selectedSingle.selection,
                                              relativeTo: rangeNow)
        check(selectedSingle.totalRecordDays == 4 && selectedSingleSnapshot.recordDayCount == 1,
              "Filtering to one recorded day never makes an established user's picker disappear")
        check(configuration(fortnight, selection: .thirtyDays).selection == .all
              && configuration(twoMonths, selection: .ninetyDays).selection == .all,
              "A range containing all history resolves to the retained all option")
        let beforeInterruption = InsightsData.assessments(interruptedHistory, in: .thirtyDays,
                                                         relativeTo: rangeNow, calendar: calendar)
        let afterInterruption = InsightsData.assessments(interruptedHistory,
            in: configuration(interruptedHistory, selection: .thirtyDays).selection,
            relativeTo: rangeNow, calendar: calendar)
        check(Set(beforeInterruption.map(\.id)) == Set(afterInterruption.map(\.id)),
              "Merging equivalent bounded ranges preserves every original recording ID")
        check(configuration(longHistory) == configuration(Array(longHistory.reversed())),
              "Configuration equality and range grouping do not depend on input ordering")

        let sameDayExtras = try (1...9).map { hour in
            try assessment(date(11, 8, hour), score: Double(70 + hour))
        }
        let sameDayHistory = oneDay + sameDayExtras
        let sameDayConfiguration = configuration(sameDayHistory, selection: .sevenDays)
        let sameDaySnapshot = snapshot(sameDayHistory, range: sameDayConfiguration.selection,
                                       relativeTo: rangeNow)
        check(sameDayConfiguration.totalRecordDays == 1 && sameDayConfiguration.ranges.isEmpty,
              "Ten recordings on one day do not unlock date filtering")
        check(sameDaySnapshot.assessmentCount == 10 && sameDaySnapshot.recordDayCount == 1,
              "The raw recording count remains distinct from the representative-day count")
        check(sameDaySnapshot.latestDate == oneDay[0].recordedAt,
              "The latest date belongs to the day's chosen representative")

        let tomorrow = try assessment(date(11, 9), score: 99)
        let withFuture = configuration(fourDays + [tomorrow], selection: .sevenDays)
        check(withFuture == configuration(fourDays, selection: .sevenDays),
              "Future dates cannot add recorded days or make equivalent ranges diverge")
        let futureSnapshot = snapshot(fourDays + [tomorrow], range: .all, relativeTo: rangeNow)
        check(futureSnapshot.recordDayCount == 4 && futureSnapshot.latestDate == rangeNow,
              "An all-history snapshot also excludes future dates")

        for selection in InsightsRange.allCases {
            let emptyConfiguration = configuration([], selection: selection)
            check(emptyConfiguration.ranges == InsightsRange.allCases
                  && emptyConfiguration.selection == selection && emptyConfiguration.totalRecordDays == 0,
                  "No history keeps the existing picker and requested range")
            let futureOnly = configuration([tomorrow], selection: selection)
            check(futureOnly == emptyConfiguration, "Future-only history uses the unchanged empty state")
        }
        let previousHistory = try records(daysAgo: [57, 65, 72, 80])
        for selection in [InsightsRange.sevenDays, .thirtyDays] {
            let noRecent = configuration(previousHistory, selection: selection)
            check(noRecent.ranges == InsightsRange.allCases && noRecent.selection == selection,
                  "An established user's selected empty period keeps the original picker")
            let noRecentSnapshot = snapshot(previousHistory, range: noRecent.selection, relativeTo: rangeNow)
            check(noRecentSnapshot.assessmentCount == 0 && noRecentSnapshot.recordDayCount == 0
                  && noRecentSnapshot.latestDate == nil,
                  "A selected empty period does not substitute older results")
        }
        let sparseWeekly = snapshot(sparseDays, range: .sevenDays, relativeTo: rangeNow)
        check(sparseWeekly.assessmentCount == 1 && sparseWeekly.recordDayCount == 1,
              "Snapshot initialization continues to honor its explicit range without implicit widening")
        let sparseAll = snapshot(sparseDays, range: configuration(sparseDays, selection: .sevenDays).selection,
                                relativeTo: rangeNow)
        check(sparseAll.recordDayCount == 3 && sparseAll.assessmentCount == 3,
              "The caller explicitly passes the all-history selection when the picker is hidden")
        print("Dashboard snapshots: \(checks) checks passed")
    }
}
