import Foundation
import SwiftData

/// Seeded integration checks use the real persisted model, history adapter,
/// scoring engine and daily cache. No substitute store or scoring implementation.
@main
enum ReadinessProviderTests {
    @MainActor
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        func close(_ value: Double?, _ expected: Double) -> Bool {
            value.map { $0.isFinite && abs($0 - expected) < 0.000_001 } ?? false
        }
        func factor(_ result: ReadinessResult, _ id: String) -> FactorContribution {
            guard let row = result.contributions.first(where: { $0.factorId == id }) else {
                preconditionFailure("Missing contribution \(id)")
            }
            return row
        }
        func conserved(_ result: ReadinessResult) -> Bool {
            close(result.score, 70 + result.contributions.reduce(0) { $0 + $1.contribution })
        }

        let day = beijingDate(2026, 10, 10, 4)
        let now = day.addingTimeInterval(8 * 3_600)
        let prior = ReadinessPracticeDay.adding(days: -1, to: day)
        check(ReadinessPracticeDay.start(containing: day.addingTimeInterval(-1)) == prior,
              "03:59:59 Beijing belongs to yesterday's practiceDay")
        check(ReadinessPracticeDay.start(containing: day) == day,
              "04:00 Beijing starts the next practiceDay")
        check(ReadinessPracticeDay.start(containing: now) == day,
              "A practiceDay has an absolute Beijing boundary, independent of the device zone")
        check(ReadinessPracticeDay.start(containing: beijingDate(2027, 1, 1, 3))
              == beijingDate(2026, 12, 31, 4), "The boundary handles year changes")

        do {
            let store = try SeededReadinessStore()
            let input = try store.input(at: now)
            check(input.practiceDaysLast7 == 0 && input.validAssessments == 0 && !input.isHabitualUser,
                  "Empty history has no practice or valid assessments")
            check(input.speechSecondsToday == nil && input.speechSecondsP90 == nil,
                  "No practice is missing speech, not zero speech")
            check(input.hnrRecent3 == [nil, nil, nil] && input.natRecent3 == [nil, nil, nil]
                  && input.pvRecent3 == [nil, nil, nil] && input.vRecent3 == [nil, nil, nil],
                  "An empty recording history still supplies three aligned C slots")
            let result = try store.provider().result(at: now)
            check(result.isColdStart && result.score == 70 && result.level == "A" && conserved(result),
                  "The complete empty-store chain preserves the engine's cold-start result")
        }

        do {
            let store = try SeededReadinessStore()
            let offsets = [-29, -20, -10, -1, 0]
            for (index, offset) in offsets.enumerated() {
                let i = Double(index + 1)
                let date = ReadinessPracticeDay.adding(days: offset, to: day)
                for (slot, scoreDelta) in [0.0, 2, 100].enumerated() {
                    let record = try store.add(
                        at: date.addingTimeInterval(Double(slot) * 60), score: 10 * i + scoreDelta,
                        naturalness: [60 + i, 62 + i, 100 + i][slot],
                        variation: [i, i + 2, i + 40][slot],
                        hnr: [20 + i / 100, 20.1 + i / 100, 23 + i][slot],
                        speech: 10 * i * Double(slot + 1)
                    )
                    record.capturedFinalScore = -9_999
                }
                try store.add(at: date.addingTimeInterval(240), score: -9_999,
                              naturalness: -9_999, variation: 9_999, hnr: -9_999,
                              speech: 9_999, quality: .invalid)
            }
            // One second outside [day-29, day] still contributes to the lifetime count.
            let old = try store.add(at: ReadinessPracticeDay.adding(days: -29, to: day)
                .addingTimeInterval(-1), score: 9_999, naturalness: 9_999, variation: 9_999, hnr: 9_999)
            old.resultPayload = Data("unused old detail is not JSON".utf8)
            try store.add(at: now.addingTimeInterval(1), score: 8_888, naturalness: 8_888,
                          variation: 8_888, hnr: 8_888)
            try store.save()
            let input = try store.input(at: now)
            check(input.validAssessments == 16,
                  "Lifetime count uses quality-gated recordings, including old history, excluding future rows")
            check(input.practiceDaysLast7 == 2 && input.gapDays == 0 && input.consecutiveAbsenceDays == 0,
                  "Practice days deduplicate all recordings, with no gap after practice today")
            check(!input.isHabitualUser, "Multiple recordings do not inflate habitual practice days")
            check(close(input.finalScoreBaseline?.mean, 32)
                  && close(input.finalScoreBaseline?.stdev, sqrt(250)),
                  "B baseline gates first, uses per-day medians, then sample SD; captured directional scores are unused")
            check(close(input.natBaseline?.mean, 65) && close(input.natBaseline?.stdev, sqrt(2.5)),
                  "Naturalness uses the persisted naturalness column and its own daily median")
            check(close(input.pvBaseline?.mean, 5) && close(input.pvBaseline?.stdev, sqrt(2.5)),
                  "Pitch variation comes from f0.standardDeviationHz and independent daily medians")
            check(close(input.hnrBaseline?.mean, 20.13) && close(input.hnrBaseline?.stdev, 0.5),
                  "Only the HNR baseline floors a small sample deviation to 0.5 dB")
            check(close(input.speechSecondsToday, 10_299) && close(input.speechSecondsP90, 276),
                  "Today keeps measured speech; P90 linearly interpolates five quality-gated daily totals")
            check(input.vRecent3 == [nil, nil, nil] && input.vBaselineMean == nil,
                  "The actual schema's absent totalFrames never fabricates a voiced denominator")
            check(input.recentFinalScores.count == 5
                  && input.recentFinalScores[0] == ScoredAssessment(finalScore: -9_999, canCompare: false),
                  "The newest five recording slots preserve invalid quality before B's own gate")
            let reloaded = try store.inputFromFreshContext(at: now)
            check(reloaded.validAssessments == 16 && close(reloaded.finalScoreBaseline?.mean, 32)
                  && close(reloaded.hnrBaseline?.mean, 20.13) && close(reloaded.speechSecondsP90, 276),
                  "A new context reads saved scalar projections, qualified payloads and old lifetime metadata")
        }

        do {
            let store = try SeededReadinessStore()
            for offset in -3...0 {
                for minute in 0..<8 {
                    try store.add(at: ReadinessPracticeDay.adding(days: offset, to: day)
                        .addingTimeInterval(Double(minute) * 60), score: Double(minute),
                        naturalness: Double(60 + minute), variation: Double(minute),
                        hnr: Double(20 + minute), voiced: 50 + minute, totalFrames: 100)
                }
            }
            try store.save()
            let input = try store.input(at: now)
            check(input.finalScoreBaseline == nil && input.hnrBaseline == nil && input.natBaseline == nil
                  && input.pvBaseline == nil && input.vBaselineMean == nil && input.speechSecondsP90 == nil,
                  "Thirty-two recordings across only four days cannot satisfy any five-day baseline or P90")
            check(input.validAssessments == 32 && input.practiceDaysLast7 == 4,
                  "Lifetime assessments count recordings while activity counts practiceDays")
        }

        do {
            let store = try SeededReadinessStore()
            for offset in -11...0 {
                try store.add(at: ReadinessPracticeDay.adding(days: offset, to: day),
                              score: 70, quality: offset == 0 ? .missing : .invalid)
            }
            try store.save()
            let input = try store.input(at: now)
            check(input.isHabitualUser && input.practiceDaysLast7 == 7 && input.validAssessments == 0,
                  "All recorded days count toward activity even when their assessments fail comparability")
            check(input.speechSecondsToday == 10 && input.speechSecondsP90 == nil,
                  "Unqualified activity retains measured speech today but cannot create qualified P90 samples")
            check(input.hnrRecent3 == [nil, nil, nil] && input.natRecent3 == [nil, nil, nil]
                  && input.pvRecent3 == [nil, nil, nil] && input.vRecent3 == [nil, nil, nil],
                  "Missing or false canCompare invalidates every C feature without skipping slots")
        }

        do {
            let store = try SeededReadinessStore()
            for offset in -12...0 {
                try store.add(at: ReadinessPracticeDay.adding(days: offset, to: day), score: 7,
                              naturalness: 7, variation: 7, hnr: 20, voiced: 60, totalFrames: 100)
            }
            try store.save()
            let input = try store.input(at: now)
            check(close(input.hnrBaseline?.stdev, 0.5), "A constant HNR baseline receives its specified floor")
            check(input.finalScoreBaseline == nil && input.natBaseline == nil
                  && input.pvBaseline == nil && input.vBaselineMean == nil,
                  "Zero sample SD remains unavailable for final score, n, p and v; no floor leaks from HNR")
            check(input.vRecent3 == [0.6, 0.6, 0.6],
                  "An explicitly persisted totalFrames enables voiced ratios without changing Core's schema")
        }

        do {
            let store = try SeededReadinessStore()
            for index in 0..<5 {
                let enormous = 1e307 * Double(index + 1)
                try store.add(at: ReadinessPracticeDay.adding(days: index - 4, to: day),
                              score: enormous, naturalness: enormous, variation: enormous, hnr: enormous)
            }
            try store.save()
            let input = try store.input(at: now)
            check(input.finalScoreBaseline == nil && input.hnrBaseline == nil
                  && input.natBaseline == nil && input.pvBaseline == nil,
                  "Overflowing sample SD from finite observations excludes the baseline, including HNR")
        }

        do {
            let store = try SeededReadinessStore()
            let first = try store.add(at: day, score: 70, voiced: 50, totalFrames: 0)
            let second = try store.add(at: day.addingTimeInterval(60), score: 71,
                                       variation: nil, hnr: nil, voiced: 101, totalFrames: 100)
            let third = try store.add(at: day.addingTimeInterval(120), score: 72,
                                      variation: -1, hnr: 22, speech: 0, voiced: -1, totalFrames: 100)
            try store.save()
            // Exercise the same live model context after a bad upstream value;
            // nonfinite columns must never become valid engine measurements.
            first.finalScore = .infinity
            first.naturalnessScore = .infinity
            first.speechSeconds = .infinity
            second.finalScore = .nan
            second.naturalnessScore = .nan
            second.speechSeconds = -1
            let input = try store.input(at: now)
            check(input.validAssessments == 1,
                  "Nonfinite final scores cannot increase lifetime valid-assessment counts")
            check(input.recentFinalScores.count == 3 && input.recentFinalScores[1].finalScore.isNaN
                  && input.recentFinalScores[2].finalScore.isInfinite,
                  "B keeps nonfinite raw slots for the engine's gate instead of skipping or replacing them")
            check(input.natRecent3 == [third.naturalnessScore, nil, nil],
                  "Nonfinite naturalness propagates as missing in its exact C slot")
            check(input.pvRecent3 == [nil, nil, 5] && input.hnrRecent3 == [22, nil, 20],
                  "Missing or invalid acoustic features are independent holes without interpolation")
            check(input.vRecent3 == [nil, nil, nil],
                  "A negative numerator, numerator above total or zero denominator cannot form a voiced ratio")
            check(input.speechSecondsToday == 0 && input.speechSecondsP90 == nil,
                  "Actual zero speech remains zero while negative and nonfinite measurements are excluded")
        }

        do {
            let store = try SeededReadinessStore()
            for index in 0..<5 {
                try store.add(at: ReadinessPracticeDay.adding(days: index - 4, to: day),
                              score: Double(60 + index), naturalness: Double(60 + index),
                              variation: Double(index + 1), hnr: 20, hnrWindows: 9,
                              voiced: 50 + index * 5, totalFrames: 100)
            }
            try store.save()
            let input = try store.input(at: now)
            check(input.hnrRecent3 == [nil, nil, nil] && input.hnrBaseline == nil,
                  "HNR requires at least ten windows for each recording before daily aggregation")
            check(input.natBaseline != nil && input.pvBaseline != nil && close(input.vBaselineMean, 0.6),
                  "The HNR window gate does not discard valid n, p or explicitly persisted v")
            check(input.natRecent3 == [64, 63, 62] && input.pvRecent3 == [5, 4, 3]
                  && input.vRecent3 == [0.7, 0.65, 0.6], "Recent features retain raw recording order")
        }

        do {
            let store = try SeededReadinessStore()
            for index in 0..<6 {
                try store.add(at: ReadinessPracticeDay.adding(days: index - 51, to: day),
                              score: Double(60 + index), naturalness: Double(70 + index),
                              variation: Double(index + 1), hnr: Double(10 + index),
                              quality: index == 2 ? .missing : .valid, legacy: index == 4)
            }
            try store.save()
            let input = try store.input(at: now)
            check(input.validAssessments == 5 && input.finalScoreBaseline == nil && input.hnrBaseline == nil,
                  "Old valid assessments prevent cold start without backfilling the 30-day baseline")
            check(input.recentFinalScores.map(\.finalScore) == [65, 64, 63, 62, 61]
                  && !input.recentFinalScores[3].canCompare,
                  "Recent B slots can be older than thirty days, but never skip the missing-quality hole")
            check(input.hnrRecent3 == [15, nil, 13] && input.natRecent3 == [75, 74, 73],
                  "A schema-v3 HNR hole remains in the exact recent slot while available naturalness survives")
            check(input.practiceDaysLast7 == 0 && input.gapDays == 46 && input.consecutiveAbsenceDays == 46,
                  "Gap and continuous absence use practiceDay distance to the latest actual recording")
            let reloaded = try store.inputFromFreshContext(at: now)
            check(reloaded == input,
                  "Saved old-only history has identical lifetime enumeration and recent payload slots in a fresh context")
            let result = try store.provider().result(at: now)
            check(!result.isColdStart && result.reason == .welcomeBack && conserved(result),
                  "Lifetime metadata and old recent slots reach the real engine through SwiftData")
        }

        do {
            let store = try SeededReadinessStore()
            for offset in -5 ... -1 {
                try store.add(at: ReadinessPracticeDay.adding(days: offset, to: day), score: 70,
                              naturalness: Double(75 + offset), variation: Double(10 + offset), hnr: 20)
            }
            try store.add(at: day, score: 70, hnr: 10)
            try store.add(at: day.addingTimeInterval(60), score: 70, hnr: nil, legacy: true)
            let latest = try store.add(at: day.addingTimeInterval(120), score: 70, hnr: 10)
            // Malformed unused detail arrays must not invalidate scalar features.
            try store.editPayload(of: latest) { payload in
                var f0 = payload["f0"] as! [String: Any]
                f0["windows"] = "unused malformed details"
                payload["f0"] = f0
                var voice = payload["voiceQuality"] as! [String: Any]
                voice["windows"] = "unused malformed details"
                payload["voiceQuality"] = voice
            }
            try store.save()
            let input = try store.input(at: now)
            check(input.hnrBaseline != nil && input.hnrRecent3 == [10, nil, 10],
                  "Scalar payload decoding ignores unused detail arrays and preserves the v3 hole")
            let result = try store.provider().result(at: now)
            check(!factor(result, "C1").isTriggered && factor(result, "C1").contribution == 0,
                  "One real v3 recording blocks C1; older eligible HNR values cannot refill it")
            check(conserved(result), "The v3 full-chain result reconciles every contribution")
        }

        do {
            let store = try SeededReadinessStore()
            for index in 0..<12 {
                try store.add(at: ReadinessPracticeDay.adding(days: index - 12, to: day),
                              score: Double(70 + index), naturalness: Double(70 + index % 3),
                              variation: Double(10 + index % 2), hnr: 20 + Double(index % 3) / 10)
            }
            for index in 0..<3 {
                try store.add(at: day.addingTimeInterval(Double(index) * 60),
                              score: Double(90 - index * 5), naturalness: 40, variation: 20, hnr: 17)
            }
            try store.save()
            let input = try store.input(at: now)
            let provider = store.provider()
            let result = try provider.result(at: now)
            check(result == ReadinessScoring.evaluate(input),
                  "The provider calls the delivered engine with the fetched input without adjusting scores")
            check(factor(result, "B2").isTriggered && factor(result, "B2").contribution == -10,
                  "The complete seeded path keeps uncalibrated B2 at -10")
            check(factor(result, "C1").isTriggered && factor(result, "C2").isTriggered
                  && factor(result, "C3").isTriggered && result.reason == .voiceTired,
                  "Persisted acoustic features and daily baselines reach the anomaly rules")
            check(["S", "A", "B", "C"].contains(result.level) && conserved(result),
                  "Result level remains a string and score equals 70 plus all evidence contributions")
            let repeated = try provider.result(at: now.addingTimeInterval(60))
            check(repeated == result && provider.evaluationCount == 1,
                  "The second call in the same practiceDay returns the cache without evaluation")
            print("Seeded Readiness: score=\(result.score), level=\(result.level), contribution sum=\(result.contributions.reduce(0) { $0 + $1.contribution })")
        }

        do {
            let store = try SeededReadinessStore()
            try store.seedHeavyDay(day)
            let provider = store.provider()
            let heavy = try provider.result(at: now)
            check(heavy.markHeavyYesterday && heavy.reason != .heavyYesterday,
                  "A4 marks tomorrow while leaving today's result uncapped by that marker")
            try store.add(at: now.addingTimeInterval(60), score: 0, speech: 300)
            try store.save()
            let cachedAfterRecording = try provider.result(at: now.addingTimeInterval(120))
            check(cachedAfterRecording == heavy,
                  "New recordings cannot invalidate the specified same-day debounce")
            let reopenedToday = store.provider()
            let cachedToday = try reopenedToday.result(at: now.addingTimeInterval(120))
            check(cachedToday == heavy && reopenedToday.evaluationCount == 0,
                  "The daily result and heavy marker survive provider reconstruction")
            let tomorrow = ReadinessPracticeDay.adding(days: 1, to: day)
            let nextProvider = store.provider()
            let capped = try nextProvider.result(at: tomorrow)
            check(capped.reason == .heavyYesterday && capped.score <= 64 && !capped.markHeavyYesterday,
                  "The persisted marker becomes effective at exactly the next Beijing 04:00 boundary")
            check(nextProvider.evaluationCount == 1 && conserved(capped),
                  "The next-day cap remains evidence-accounted through the full chain")
            let reopenedTomorrow = store.provider()
            let cachedTomorrow = try reopenedTomorrow.result(at: tomorrow.addingTimeInterval(60))
            check(cachedTomorrow == capped && reopenedTomorrow.evaluationCount == 0,
                  "Restarting after marker consumption returns the cached capped result")
            let afterConsumption = try store.provider().result(at: ReadinessPracticeDay.adding(days: 2, to: day))
            check(afterConsumption.reason != .heavyYesterday && afterConsumption.score > 64,
                  "The consumed heavy marker cannot carry over to a second day")
            check(conserved(afterConsumption), "The post-consumption score still reconciles its evidence")
        }

        do {
            let store = try SeededReadinessStore()
            try store.seedHeavyDay(day)
            let heavy = try store.provider().result(at: now)
            check(heavy.markHeavyYesterday, "The skipped-day fixture has a real persisted A4 marker")
            let skipped = try store.provider().result(at: ReadinessPracticeDay.adding(days: 2, to: day))
            check(skipped.reason != .heavyYesterday && skipped.score > 64,
                  "A marker expires when its only eligible next day was never evaluated")
            let later = try store.provider().result(at: ReadinessPracticeDay.adding(days: 3, to: day))
            check(later.reason != .heavyYesterday, "An expired marker stays cleared on subsequent days")
        }

        print("Readiness provider integration: \(checks) checks passed (Swift 6 strict concurrency)")
    }

    private static func beijingDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

@MainActor
private final class SeededReadinessStore {
    enum Quality { case valid, invalid, missing }

    private let container: ModelContainer
    private let suiteName = "pitchee.readiness.tests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(for: RecordingAssessment.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @discardableResult
    func add(
        at date: Date, score: Double, naturalness: Double = 75, variation: Double? = 5,
        hnr: Double? = 20, hnrWindows: Int = 10, speech: Double = 10,
        voiced: Int = 60, totalFrames: Int? = nil, quality: Quality = .valid, legacy: Bool = false
    ) throws -> RecordingAssessment {
        let result = PitcheeAnalysisResult(
            schemaVersion: legacy ? 3 : 4, modelVersion: "readiness-seeded-tests", scoreProfile: nil,
            audio: .init(sourceSampleRate: 16_000, sourceChannels: 1, inputSeconds: speech, analyzedSeconds: speech),
            vad: .init(segmentCount: 0, speechSeconds: speech, sileroSegmentCount: 0,
                       discardedBreathLikeCount: 0, trimmedSegmentCount: 0, segments: []),
            f0: .init(windowSeconds: 0.5, meanHz: 175, standardDeviationHz: variation,
                      voicedFrameCount: voiced, voicedWindowCount: 20, windows: []),
            vfp: .init(vfpStandardScore: 70, windowCount: 0, windowDurationSeconds: 1, windows: []),
            naturalness: .init(score: naturalness, windowCount: 0, windowDurationSeconds: 1, windows: []),
            composite: .init(baseScore: score, finalScore: score, cap: nil,
                             rule: "seeded", limited: false, boosted: false),
            voiceQuality: legacy ? nil : .init(algorithm: "autocorrelation", hnrDb: hnr,
                hnrWindowCount: hnrWindows, hnrStdDb: nil, windowSeconds: 0.04, windows: [])
        )
        let captureQuality: RecordingQuality? = switch quality {
        case .valid: RecordingQuality(speechSeconds: 10, speechDBFS: -20, backgroundDBFS: -60, clippedFraction: 0)
        case .invalid: RecordingQuality(speechSeconds: 1, speechDBFS: -20, backgroundDBFS: -60, clippedFraction: 0)
        case .missing: nil
        }
        let record = try RecordingAssessment(recordedAt: date, result: result, quality: captureQuality)
        if let totalFrames {
            try editPayload(of: record) { payload in
                var pitch = payload["f0"] as! [String: Any]
                pitch["totalFrames"] = totalFrames
                payload["f0"] = pitch
            }
        }
        context.insert(record)
        return record
    }

    func editPayload(of record: RecordingAssessment, _ edit: (inout [String: Any]) -> Void) throws {
        var payload = try JSONSerialization.jsonObject(with: record.resultPayload) as! [String: Any]
        edit(&payload)
        record.resultPayload = try JSONSerialization.data(withJSONObject: payload)
    }

    func save() throws { try context.save() }
    func input(at date: Date) throws -> ReadinessInput { try ReadinessHistory(modelContext: context).input(at: date) }
    func inputFromFreshContext(at date: Date) throws -> ReadinessInput {
        let freshContext = ModelContext(container)
        return try ReadinessHistory(modelContext: freshContext).input(at: date)
    }
    func provider() -> ReadinessProvider { ReadinessProvider(modelContext: context, defaults: defaults) }

    func seedHeavyDay(_ day: Date) throws {
        for offset in -10 ... -1 {
            try add(at: ReadinessPracticeDay.adding(days: offset, to: day), score: 70, speech: 10)
        }
        try add(at: day, score: 70, speech: 100)
        try save()
    }
}
