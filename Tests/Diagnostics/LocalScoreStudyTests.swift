//
//  LocalScoreStudyTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation

@main
enum LocalScoreStudyTests {
    @MainActor
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pitchee-score-study-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = DiagnosticConfiguration(appVersion: "test", appBuild: "1",
            manifestSHA256: String(repeating: "b", count: 64), measurementRevision: 1)
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var uptime: TimeInterval = 100
        let path = root.appendingPathComponent("study/state.json")
        let store = LocalScoreStudyStore(fileURL: path, configuration: configuration,
            now: { now }, uptime: { uptime }, select: { true })
        let better = ScoreStudyPair(baseline: 0, candidate: 100)!
        check(better.lossDifference(from: .fully) == -4, "Negative means candidate closer to self-rating")
        check(better.lossDifference(from: .notAtAll) == 4, "Positive means baseline closer to self-rating")
        check(better.lossDifference(from: .partly) == 0, "Equal distance must not be counted as an improvement")
        for rating in ScoreStudyRating.allCases {
            check(ScoreStudyPair(baseline: 65, candidate: 65)!.lossDifference(from: rating) == 0,
                  "Identical predictions always tie, whatever the rating")
        }
        check(ScoreStudyPair(baseline: .nan, candidate: 50) == nil, "Reject nonfinite scores")
        check(ScoreStudyPair(baseline: 50, candidate: 101) == nil, "Reject out-of-range scores instead of clamping away errors")
        check(ScoreStudyPair(baseline: 12.49, candidate: 12.5)!.lossDifference(from: .notAtAll) == 1,
              "The preregistered nearest-25 ordinal boundary is explicit")

        check(store.authorizeRecording() == nil, "Separate study consent defaults off")
        check(store.invite(authorizedBy: nil, direction: .feminine) == nil, "No consent must not enroll a recording")
        check(!FileManager.default.fileExists(atPath: path.path), "Default off writes no study data")
        store.setEnabled(true)
        let consent = store.authorizeRecording()!
        check(store.invite(authorizedBy: nil, direction: .feminine) == nil,
              "Enabling after recording starts does not retrospectively enroll it")
        check(store.invite(authorizedBy: consent, direction: nil) == nil,
              "Undecided goals are excluded without inferring a direction")
        check(store.state.usedScreens == 0, "Ineligible recordings do not become study observations")

        let first = store.invite(authorizedBy: consent, direction: .feminine)!
        check(store.isAwaitingFeedback(first), "An invitation must wait for feedback")
        check(store.invite(authorizedBy: consent, direction: .masculine) == nil, "Only one study recording can be pending")
        store.respond(first, feedback: .rating(.fully))
        store.respond(first, feedback: .skipped)
        check(!store.isAwaitingFeedback(first), "Only the first response is accepted")
        store.finish(first, pair: better, failed: false)
        store.finish(first, pair: better, failed: false)
        let female = store.state.summaries[ScoreStudyDirection.feminine.rawValue]
        check(female.invited == 1 && female.responses[0] == 1 && female.paired == 1,
              "Response and analysis completion are idempotent")
        check(female.candidateCloser == 1 && female.lossDifferences[0] == 1,
              "Store only the bounded paired loss contribution")
        check(store.state.summaries[ScoreStudyDirection.masculine.rawValue].invited == 0,
              "Direction summaries never mix")

        let second = store.invite(authorizedBy: consent, direction: .masculine)!
        store.respond(second, feedback: .unableToJudge)
        store.finish(second, pair: better, failed: false)
        check(store.state.summaries[1].paired == 0 && store.state.summaries[1].responses[1] == 1,
              "Unable to judge remains missing, not an invented midpoint rating")

        let third = store.invite(authorizedBy: consent, direction: .feminine)!
        uptime += LocalScoreStudyState.feedbackSeconds
        store.respond(third, feedback: .rating(.fully))
        store.finish(third, pair: better, failed: false)
        check(store.state.summaries[0].responses[ScoreStudyResponse.timedOut.rawValue] == 1,
              "A late button press is treated as timeout")
        check(store.state.summaries[0].paired == 1, "Timed-out ratings cannot enter the comparison")

        let fourth = store.invite(authorizedBy: consent, direction: .masculine)!
        store.respond(fourth, feedback: .rating(.fully))
        store.finish(fourth, pair: better, failed: true)
        check(store.state.summaries[1].responses[0] == 1 && store.state.summaries[1].analyses[ScoreStudyAnalysis.failed.rawValue] == 1,
              "Analysis failure retains invitation and response denominators")
        check(store.state.summaries[1].paired == 0, "Failed analysis contributes no fabricated loss")
        let fifth = store.invite(authorizedBy: consent, direction: .feminine)!
        store.respond(fifth, feedback: .rating(.fully))
        store.finish(fifth, pair: nil, failed: false)
        check(store.state.summaries[0].analyses[ScoreStudyAnalysis.unavailable.rawValue] == 1,
              "Missing reliable pitch/scores differs from analysis failure")
        check(store.invite(authorizedBy: consent, direction: .feminine) == nil, "Limit invitations to five across directions")
        store.clear()
        let refreshedConsent = store.authorizeRecording()!
        check(store.state.summaries.allSatisfy { $0.screened == 0 }, "Clearing removes all accumulated study observations")
        check(store.state.usedInvitations == 5 && store.invite(authorizedBy: refreshedConsent, direction: .feminine) == nil,
              "Clearing or reconsenting cannot reset the period quota")

        now += LocalScoreStudyState.retentionSeconds
        store.refresh()
        check(store.state.usedInvitations == 0 && store.state.usedScreens == 0, "Start a fresh period after expiry")
        check(store.invite(authorizedBy: consent, direction: .feminine) == nil, "Old-period recording authorization is invalid")
        let newConsent = store.authorizeRecording()!
        let stale = store.invite(authorizedBy: newConsent, direction: .feminine)!
        store.setEnabled(false)
        store.setEnabled(true)
        store.respond(stale, feedback: .rating(.fully))
        store.finish(stale, pair: better, failed: false)
        check(store.state.summaries.allSatisfy { $0.screened == 0 }, "Withdrawal prevents late labels or results from repopulating data")
        check(store.invite(authorizedBy: newConsent, direction: .feminine) == nil, "Withdrawal invalidates authorization held by a recording")

        let validConsent = store.authorizeRecording()!
        let beforeRestart = store.invite(authorizedBy: validConsent, direction: .masculine)!
        store.respond(beforeRestart, feedback: .rating(.fully))
        let restored = LocalScoreStudyStore(fileURL: path, configuration: configuration, now: { now })
        check(restored.state.summaries[1].responses[0] == 1 && restored.state.summaries[1].paired == 0,
              "Rating value is not recovered or manufactured after a restart")
        check(restored.state.summaries[1].analyses[ScoreStudyAnalysis.interrupted.rawValue] == 1,
              "A crash after response is separately recorded as interrupted analysis")
        let crashPath = root.appendingPathComponent("crash/state.json")
        let crash = LocalScoreStudyStore(fileURL: crashPath, configuration: configuration, now: { now }, select: { true })
        crash.setEnabled(true)
        _ = crash.invite(authorizedBy: crash.authorizeRecording(), direction: .feminine)
        let crashRestored = LocalScoreStudyStore(fileURL: crashPath, configuration: configuration, now: { now })
        check(crashRestored.state.summaries[0].responses[ScoreStudyResponse.interrupted.rawValue] == 1,
              "A crash before response retains a missing-feedback denominator")
        check(crashRestored.state.summaries[0].analyses[ScoreStudyAnalysis.interrupted.rawValue] == 1,
              "A crash before inference does not disappear from outcomes")
        let crashAgain = LocalScoreStudyStore(fileURL: crashPath, configuration: configuration, now: { now })
        check(crashAgain.state.summaries[0].responded == 1 && crashAgain.state.summaries[0].finished == 1,
              "Recovery cannot count the same interruption twice")

        let changedConfiguration = DiagnosticConfiguration(appVersion: "test", appBuild: "2",
            manifestSHA256: configuration.manifestSHA256, measurementRevision: 1)
        let upgraded = LocalScoreStudyStore(fileURL: crashPath, configuration: changedConfiguration, now: { now })
        check(upgraded.state.enabled && upgraded.state.summaries.allSatisfy { $0.screened == 0 },
              "A configuration change clears observations without mixing app versions")
        check(upgraded.state.usedInvitations == 1 && upgraded.state.usedScreens == 1,
              "A configuration change preserves this period's contribution limits")

        let rollbackPath = root.appendingPathComponent("rollback/state.json")
        let rollback = LocalScoreStudyStore(fileURL: rollbackPath, configuration: configuration,
            now: { now }, select: { true })
        rollback.setEnabled(true)
        let rollbackAuthorization = rollback.authorizeRecording()!
        let rollbackAttempt = rollback.invite(authorizedBy: rollbackAuthorization, direction: .feminine)!
        let periodStart = rollback.state.periodStartedAt
        now -= 60
        rollback.refresh()
        check(rollback.state.summaries.allSatisfy { $0.screened == 0 }
              && rollback.state.usedInvitations == 1 && rollback.state.periodStartedAt == periodStart,
              "Clock rollback clears observations but keeps quotas and the original period boundary")
        now = periodStart
        rollback.respond(rollbackAttempt, feedback: .rating(.fully))
        rollback.finish(rollbackAttempt, pair: better, failed: false)
        check(rollback.state.summaries.allSatisfy { $0.screened == 0 }
              && rollback.invite(authorizedBy: rollbackAuthorization, direction: .feminine) == nil,
              "Clock rollback invalidates in-flight feedback and the recording's authorization")

        let clearAttempt = rollback.invite(authorizedBy: rollback.authorizeRecording(), direction: .masculine)!
        rollback.respond(clearAttempt, feedback: .rating(.fully))
        rollback.clear()
        rollback.finish(clearAttempt, pair: better, failed: false)
        check(rollback.state.summaries.allSatisfy { $0.screened == 0 } && rollback.state.usedInvitations == 2,
              "Clearing during analysis prevents a late result from restoring feedback or resetting quotas")

        let unselectedPath = root.appendingPathComponent("unselected/state.json")
        let unselected = LocalScoreStudyStore(fileURL: unselectedPath, configuration: configuration, now: { now }, select: { false })
        unselected.setEnabled(true)
        let sampleConsent = unselected.authorizeRecording()
        for _ in 0..<110 { _ = unselected.invite(authorizedBy: sampleConsent, direction: .feminine) }
        check(unselected.state.usedScreens == 100 && unselected.state.usedInvitations == 0,
              "Even non-invited sampling decisions are bounded")
        check(unselected.state.summaries[0].screened == 100 && unselected.state.summaries[0].invited == 0,
              "Screened recordings must not inflate invitations or response rates")

        let exactPath = root.appendingPathComponent("serialization/state.json")
        let exact = LocalScoreStudyStore(fileURL: exactPath, configuration: configuration, now: { now }, select: { true })
        exact.setEnabled(true)
        let exactAttempt = exact.invite(authorizedBy: exact.authorizeRecording(), direction: .feminine)!
        exact.respond(exactAttempt, feedback: .rating(.mostly))
        exact.finish(exactAttempt, pair: ScoreStudyPair(baseline: 33.123456, candidate: 78.987654), failed: false)
        let data = try Data(contentsOf: exactPath)
        let text = String(decoding: data, as: UTF8.self)
        check(!text.contains("33.123456") && !text.contains("78.987654"), "Exact model scores cannot reach the study file")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        check(Set(json.keys) == ["schemaVersion", "candidateID", "baselineID", "enabled", "periodStartedAt",
                               "usedInvitations", "usedScreens", "summaries", "configuration"],
              "No individual feedback, audio identity, or token may be serialized")
        let summaries = json["summaries"] as! [[String: Any]]
        check(summaries.allSatisfy { Set($0.keys) == ["screened", "invited", "responses", "analyses", "lossDifferences"] },
              "Only the registered aggregate fields are persisted")
        let excluded = try exactPath.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        check(excluded == true, "Study state is excluded from backup")

        var corrupt = json
        corrupt["usedScreens"] = Int.max
        try JSONSerialization.data(withJSONObject: corrupt).write(to: exactPath)
        let rejected = LocalScoreStudyStore(fileURL: exactPath, configuration: configuration)
        check(rejected.storageUnavailable && !rejected.state.enabled && rejected.authorizeRecording() == nil,
              "Invalid counters disable collection before any arithmetic")
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        let failed = LocalScoreStudyStore(fileURL: blocked.appendingPathComponent("state.json"), configuration: configuration)
        failed.setEnabled(true)
        check(failed.storageUnavailable && failed.authorizeRecording() == nil, "Write errors never create untracked study sessions")

        func result(pitch: Double? = 120, naturalness: Double = 100) -> PitcheeAnalysisResult {
            .init(schemaVersion: 2, modelVersion: "test", scoreProfile: nil,
                  audio: .init(sourceSampleRate: 16_000, sourceChannels: 1, inputSeconds: 10, analyzedSeconds: 10),
                  vad: .init(segmentCount: 1, speechSeconds: 8, sileroSegmentCount: 1, discardedBreathLikeCount: 0, trimmedSegmentCount: 0, segments: []),
                  f0: .init(windowSeconds: 0.05, meanHz: pitch, standardDeviationHz: 1, voicedFrameCount: 10, voicedWindowCount: 10, windows: []),
                  vfp: .init(vfpStandardScore: 20, windowCount: 1, windowDurationSeconds: 1.5, windows: []),
                  naturalness: .init(score: naturalness, windowCount: 1, windowDurationSeconds: 1.5, windows: []),
                  composite: .init(baseScore: 75, finalScore: 30, cap: 30, rule: "test", limited: true, boosted: false))
        }
        check(ScoreStudyEvaluator.direction(for: .undecided) == nil, "Never treat an undecided user as feminine")
        check(ScoreStudyEvaluator.pair(for: result(), direction: .feminine)?.lossDifference(from: .mostly) == -2,
              "Feminine candidate uses Core's base score and baseline uses its final score")
        check(ScoreStudyEvaluator.pair(for: result(), direction: .masculine)?.lossDifference(from: .fully) == 0,
              "Masculinization's continuous Core score has no candidate cap")
        check(ScoreStudyEvaluator.pair(for: result(pitch: nil), direction: .feminine) == nil,
              "Missing F0 must not masquerade as evidence for the candidate")
        check(ScoreStudyEvaluator.pair(for: result(naturalness: .nan), direction: .masculine) == nil,
              "Invalid model output does not get silently normalized into evidence")
        print("Local score study: \(checks) checks passed")
    }
}
