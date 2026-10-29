//
//  PracticeTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation
import SwiftData

@main
enum PracticeTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(value(), message)
        }
        func quality(_ speech: Double = 8, level: Double? = -25, background: Double? = -50, clipped: Double? = 0) -> RecordingQuality {
            RecordingQuality(speechSeconds: speech, speechDBFS: level, backgroundDBFS: background, clippedFraction: clipped)
        }
        check(quality().canCompare, "Adequate capture is eligible")
        check(RecordingQuality.hasMinimumSpeech(5)
              && !RecordingQuality.hasMinimumSpeech(4.99)
              && !RecordingQuality.hasMinimumSpeech(.nan),
              "The five-second VAD gate is finite and inclusive")
        check(!quality(4.99).canCompare && quality(5).canCompare, "Speech boundary is inclusive at five seconds")
        check(quality(level: -45).canCompare == false, "Low separation independently excludes a borderline level")
        check(quality(level: -45, background: -60).canCompare, "The level threshold is inclusive")
        check(quality(level: -45.1).issues.contains(.lowLevel), "Low input level has actionable feedback")
        check(quality(background: -34.9).issues.contains(.background), "Small speech/background separation is excluded")
        check(quality(background: -35).canCompare, "Separation threshold is inclusive")
        check(quality(background: nil).canCompare && !quality(background: nil).backgroundMeasured,
              "Continuous speech does not fabricate a background measurement")
        check(!quality(clipped: 0.01).canCompare && quality(clipped: 0.0099).canCompare, "One percent clipping threshold")
        check(!quality(level: nil).canCompare && !quality(clipped: nil).canCompare, "Unavailable essential checks cannot pass")
        check(!quality(.nan).canCompare && !quality(level: .infinity).canCompare, "Invalid measurements cannot pass")
        check(DailyPracticeSummary(date: .now, values: []) == nil, "Empty data has no zero-valued median")
        check(DailyPracticeSummary(date: .now, values: [1, 100, 2])?.median == 2, "Odd median resists a high outlier")
        check(DailyPracticeSummary(date: .now, values: [100, 2, 1, 4, .nan, .infinity])?.median == 3, "Even median excludes non-finite data")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let context = PracticeContext(kind: .pitchObservation, target: .masculine)
        func result(_ score: Double = 70, pitch: Double? = 150, naturalness: Double = 75) -> PitcheeAnalysisResult {
            PitcheeAnalysisResult(schemaVersion: 2, modelVersion: "practice-test", scoreProfile: nil,
                audio: .init(sourceSampleRate: 16000, sourceChannels: 1, inputSeconds: 10, analyzedSeconds: 10),
                vad: .init(segmentCount: 0, speechSeconds: 8, sileroSegmentCount: 0, discardedBreathLikeCount: 0, trimmedSegmentCount: 0, segments: []),
                f0: .init(windowSeconds: 0.5, meanHz: pitch, standardDeviationHz: 12, voicedFrameCount: 10, voicedWindowCount: 5, windows: []),
                vfp: .init(vfpStandardScore: score, windowCount: 0, windowDurationSeconds: 1, windows: []),
                naturalness: .init(score: naturalness, windowCount: 0, windowDurationSeconds: 1, windows: []),
                composite: .init(baseScore: score, finalScore: score, cap: nil, rule: "test", limited: false, boosted: false))
        }
        func record(_ pitch: Double?, context: PracticeContext = context, quality q: RecordingQuality? = nil) throws -> RecordingAssessment {
            try RecordingAssessment(recordedAt: day, result: result(pitch: pitch), practice: context, quality: q ?? quality())
        }
        let a = try record(100)
        let b = try record(300)
        let c = try record(110)
        let poor = try record(1000, quality: quality(2))
        let missing = try record(nil)
        let otherGoal = try record(2000, context: PracticeContext(kind: .pitchObservation, target: .feminine))
        let otherPractice = try record(3000, context: PracticeContext(kind: .pitchStability, target: .masculine))
        let legacy = try RecordingAssessment(recordedAt: day, result: result())
        let all = [a,b,c,poor,missing,otherGoal,otherPractice,legacy]
        let series = InsightsData.dailySummary(all, cohort: a.cohort!, metric: .pitch, calendar: calendar)
        check(series.count == 1 && series[0].count == 3 && series[0].median == 110,
              "Only the same goal/practice with eligible quality and a valid pitch enters median/count")
        check(series[0].minimum == 100 && series[0].maximum == 300, "Range covers every eligible attempt")
        let scoreSeries = InsightsData.dailySummary(all, cohort: a.cohort!, metric: .composite, calendar: calendar)
        check(scoreSeries[0].count == 4, "Metric counts handle missing pitch independently")
        check(legacy.recordedTarget == nil && legacy.quality == nil && !legacy.isBaselineEligible,
              "Old records do not invent target or recording quality")
        check(a.recordedTarget == .masculine && a.scoringRulesVersion == VoiceDirectionScore.rulesVersion,
              "Capture stores goal and scoring version")
        let captured = a.capturedFinalScore
        _ = a.finalScore(for: .feminine)
        check(a.capturedFinalScore == captured && a.result?.composite.finalScore == 70,
              "Recalculating for another direction cannot rewrite captured or raw results")
        let undecided = try record(150, context: PracticeContext(kind: .dailyReading, target: .undecided))
        check(undecided.capturedFinalScore == nil, "Undecided does not imply a feminine directional score")
        check(InsightsData.dailySummary([undecided], cohort: undecided.cohort!, metric: .composite).isEmpty,
              "Undecided direction has no directional score series")
        let restored = try JSONDecoder().decode(PracticeContext.self, from: JSONEncoder().encode(context))
        check(restored == context && restored.passage == context.passage, "Exact passage and target survive serialization")
        let nextSession = try record(160, context: PracticeContext(kind: .pitchObservation, target: .masculine))
        check(nextSession.cohort == a.cohort, "Matching material/goal aggregates across sessions")
        nextSession.modelVersion = "different-model"
        check(nextSession.cohort != a.cohort, "Model versions cannot silently mix")
        var changed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as! [String: Any]
        changed["passage"] = "different material"
        let differentText = try JSONDecoder().decode(PracticeContext.self, from: JSONSerialization.data(withJSONObject: changed))
        let changedTextRecord = try record(160, context: differentText)
        check(changedTextRecord.cohort != a.cohort, "Exact material separates languages and revised passages")

        let store = try ModelContainer(for: RecordingAssessment.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store.mainContext.insert(a)
        let paired = try RecordingAssessment(recordedAt: day, result: result(), practice: context, quality: quality(), comparedToID: a.id)
        paired.comparisonFeedbackRawValue = PracticeFeedback.closer.rawValue
        store.mainContext.insert(paired)
        try store.mainContext.save()
        let saved = try store.mainContext.fetch(FetchDescriptor<RecordingAssessment>())
        check(saved.count == 2 && saved.contains { $0.comparedToID == a.id && $0.comparisonFeedbackRawValue == "closer" },
              "Listening feedback persists with its explicit comparison pair")
        check(saved.first(where: { $0.id == a.id })?.quality?.canCompare == true, "Quality snapshot survives history save")

        let originalQualityPayload = a.qualityPayload
        a.qualityPayload = try JSONEncoder().encode(quality(2))
        check(!a.isBaselineEligible, "Replacing cached quality immediately updates comparison eligibility")
        a.qualityPayload = nil
        check(a.quality == nil && a.cohort == nil, "Removing quality clears the decoded snapshot and cohort")
        a.qualityPayload = Data("invalid".utf8)
        check(a.quality == nil && !a.isBaselineEligible, "Invalid quality cannot reuse a prior eligible snapshot")
        a.qualityPayload = originalQualityPayload
        check(a.isBaselineEligible, "Restoring valid quality recovers from a cached decoding failure")
        let originalPracticePayload = a.practicePayload
        a.practicePayload = try JSONEncoder().encode(PracticeContext(kind: .pitchStability, target: .feminine))
        check(a.cohort?.kind == .pitchStability && a.cohort?.target == .feminine,
              "Replacing cached practice changes cohort membership")
        a.practicePayload = nil
        check(a.practice == nil && a.cohort == nil, "Removing practice clears cohort membership")
        a.practicePayload = Data("invalid".utf8)
        check(a.practice == nil, "Invalid practice never reuses a prior decoded context")
        a.practicePayload = originalPracticePayload
        check(a.practice == context && a.isBaselineEligible, "Restoring practice recovers its original cohort")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let abandoned = directory.appendingPathComponent("pitchee-\(UUID()).wav")
        let unrelated = directory.appendingPathComponent("notes.wav")
        try Data([0]).write(to: abandoned)
        try Data([0]).write(to: unrelated)
        try PrivateAppStorage.removeAbandonedRecordings(in: directory)
        check(!FileManager.default.fileExists(atPath: abandoned.path) && FileManager.default.fileExists(atPath: unrelated.path),
              "Launch cleanup deletes owned abandoned takes and preserves unrelated files")
        print("Practice: \(checks) checks passed")
    }
}
