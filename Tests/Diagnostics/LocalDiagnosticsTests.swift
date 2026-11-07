//
//  LocalDiagnosticsTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation

@main
enum LocalDiagnosticsTests {
    @MainActor
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pitchee-privacy-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = DiagnosticConfiguration(
            appVersion: "test", appBuild: "1", manifestSHA256: String(repeating: "a", count: 64),
            measurementRevision: 1
        )
        let path = root.appendingPathComponent("diagnostics/state.json")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = LocalDiagnosticsStore(fileURL: path, configuration: configuration, now: { now })
        check(!store.state.enabled && store.beginAttempt() == nil, "Default off must not collect")
        check(!FileManager.default.fileExists(atPath: path.path), "Disabled fresh installs do not write diagnostic records")

        store.setEnabled(true)
        let token = store.beginAttempt()
        check(token != nil && store.state.summary.attempts == 1, "Count the attempt before inference can fail")
        check(store.beginAttempt() == nil, "Do not admit overlapping attempts")
        store.finish(token, outcome: .noSpeech, observation: .init(inputSeconds: 10, latencySeconds: 3))
        store.finish(token, outcome: .success, observation: .init())
        check(store.state.summary.completed == 1, "Completion must be idempotent")
        check(store.state.summary.outcomes[DiagnosticOutcome.noSpeech.rawValue] == 1, "Failed analyses remain in the denominator")
        check(store.state.summary.speechRatios[DiagnosticSpeechRatio.unavailable.rawValue] == 1,
              "No-speech failure cannot fabricate a measured speech ratio")

        let late = store.beginAttempt()
        store.setEnabled(false)
        check(store.state.summary.attempts == 0, "Withdrawal clears pending and completed summary")
        store.setEnabled(true)
        store.finish(late, outcome: .success, observation: .init(inputSeconds: 12, speechSeconds: 10))
        check(store.state.summary.attempts == 0, "An old async result must not cross a new consent boundary")
        check(store.state.usedAttempts == 2, "Toggling does not replenish the quota")
        for _ in 0..<3 {
            let next = store.beginAttempt()
            check(next != nil, "Remaining quota is available")
            store.finish(next, outcome: .success, observation: .init(inputSeconds: 5, speechSeconds: 4, latencySeconds: 1))
        }
        check(store.beginAttempt() == nil, "Stop at five attempts, including discarded attempts")
        store.clearSummary()
        check(store.state.summary.attempts == 0 && store.beginAttempt() == nil,
              "Clearing summaries cannot be used to increase contributions")

        now.addTimeInterval(LocalDiagnosticState.retentionSeconds)
        store.refresh()
        check(store.state.usedAttempts == 0 && store.state.summary.attempts == 0, "Expire data and start a new period")
        _ = store.beginAttempt()
        let restored = LocalDiagnosticsStore(fileURL: path, configuration: configuration, now: { now })
        check(restored.state.summary.attempts == 1 && restored.state.summary.completed == 1,
              "A restart must preserve the denominator of an unfinished attempt")
        check(restored.state.summary.outcomes[DiagnosticOutcome.interrupted.rawValue] == 1,
              "Unfinished work is interrupted, never inferred successful")
        let restoredAgain = LocalDiagnosticsStore(fileURL: path, configuration: configuration, now: { now })
        check(restoredAgain.state.summary.completed == 1, "Restart recovery must not duplicate an outcome")

        let replacement = DiagnosticConfiguration(appVersion: "test", appBuild: "2",
                                                manifestSHA256: configuration.manifestSHA256, measurementRevision: 1)
        let upgraded = LocalDiagnosticsStore(fileURL: path, configuration: replacement, now: { now })
        check(upgraded.state.summary.attempts == 0 && upgraded.state.usedAttempts == 1,
              "Do not mix versions or reset the contribution limit on upgrade")
        now.addTimeInterval(-1)
        upgraded.refresh()
        check(upgraded.state.summary.attempts == 0 && upgraded.state.usedAttempts == 1,
              "Clock rollback clears potentially stale data without renewing quota")
        now.addTimeInterval(2)

        check(DiagnosticDuration(seconds: .nan) == .unavailable, "NaN is not a zero-length recording")
        check(DiagnosticDuration(seconds: 0) == .unavailable, "Invalid input duration is unknown")
        check(DiagnosticDuration(seconds: 5) == .from5To10 && DiagnosticDuration(seconds: 60) == .atLeast60,
              "Duration buckets have unambiguous boundaries")
        check(DiagnosticSpeechRatio(speechSeconds: 6, inputSeconds: 5) == .unavailable,
              "Reject impossible speech coverage")
        check(DiagnosticSpeechRatio(speechSeconds: 0, inputSeconds: 5) == .underQuarter,
              "A measured zero differs from unavailable")
        check(DiagnosticSpeechRatio(speechSeconds: 1, inputSeconds: 4) == .quarterToHalf,
              "Speech ratio boundary belongs to only one bucket")
        check(DiagnosticLatency(seconds: .infinity) == .unavailable && DiagnosticLatency(seconds: 0) == .under1,
              "Latency preserves unknown versus measured zero")
        check(DiagnosticQuality(speechDBFS: -20, backgroundDBFS: nil) == .unavailable,
              "No background reference must not produce a favorable quality classification")
        check(DiagnosticQuality(speechDBFS: -60, backgroundDBFS: nil) == .lowLevel,
              "Low speech level can be measured without inventing a noise reference")
        check(DiagnosticQuality(speechDBFS: -20, backgroundDBFS: -25) == .lowSeparation,
              "Close speech/background levels are distinguished")
        check(DiagnosticQuality(speechDBFS: -20, backgroundDBFS: -40) == .sufficientSeparation,
              "A real background reference supports the separation category")

        let sample = upgraded.beginAttempt()
        upgraded.finish(sample, outcome: .success, observation: .init(inputSeconds: 12.3456789, speechSeconds: 9.8765432,
            quality: .sufficientSeparation, latencySeconds: 1.23456789))
        let encoded = try Data(contentsOf: path)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        check(Set(json.keys) == ["schemaVersion", "enabled", "periodStartedAt", "usedAttempts", "summary", "configuration"],
              "Only the explicit local schema may be persisted")
        let summary = json["summary"] as! [String: Any]
        check(Set(summary.keys) == ["attempts", "outcomes", "durations", "speechRatios", "qualities", "latencies"],
              "Summary has fixed aggregate counters, no event list")
        let text = String(decoding: encoded, as: UTF8.self)
        check(!text.contains("12.3456789") && !text.contains("9.8765432") && !text.contains("1.23456789"),
              "Exact input measurements never reach persistent diagnostics")
        check(encoded.count < 16_384, "The local summary stays bounded")
        let diagnosticBackupFlag = try path.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        check(diagnosticBackupFlag == true,
              "Diagnostic directory must be excluded from backup")

        // Corrupt and malicious counter values must fail closed before arithmetic.
        var corrupt = json
        var corruptSummary = summary
        corruptSummary["outcomes"] = [Int.max]
        corrupt["summary"] = corruptSummary
        try JSONSerialization.data(withJSONObject: corrupt).write(to: path)
        let rejected = LocalDiagnosticsStore(fileURL: path, configuration: configuration, now: { now })
        check(rejected.storageUnavailable && !rejected.state.enabled && rejected.beginAttempt() == nil,
              "Malformed persisted data disables diagnostics")
        check(!FileManager.default.fileExists(atPath: path.path), "Corrupt payload must not be retained as a diagnostic attachment")

        let blocked = root.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let failed = LocalDiagnosticsStore(fileURL: blocked.appendingPathComponent("state.json"), configuration: configuration)
        failed.setEnabled(true)
        check(failed.storageUnavailable && !failed.state.enabled && failed.beginAttempt() == nil,
              "Storage errors never turn into memory-only collection")

        let library = root.appendingPathComponent("Library")
        let support = library.appendingPathComponent("Application Support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let history = support.appendingPathComponent("default.store")
        try Data("existing history".utf8).write(to: history)
        try PrivateAppStorage.prepare(libraryDirectory: library)
        let existingHistory = try String(contentsOf: history, encoding: .utf8)
        check(existingHistory == "existing history", "Backup hardening must not move or erase existing history")
        for directory in [support, library.appendingPathComponent("Preferences")] {
            let excluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
            check(excluded == true,
                  "History and preferences directories must be excluded")
        }
        let temp = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let owned = temp.appendingPathComponent("pitchee-\(UUID()).wav")
        let unrelated = temp.appendingPathComponent("pitchee-report.wav")
        let image = temp.appendingPathComponent("pitchee-\(UUID()).png")
        for file in [owned, unrelated, image] { try Data("keep".utf8).write(to: file) }
        try PrivateAppStorage.removeAbandonedRecordings(in: temp)
        check(!FileManager.default.fileExists(atPath: owned.path), "Remove abandoned app capture files")
        check(FileManager.default.fileExists(atPath: unrelated.path) && FileManager.default.fileExists(atPath: image.path),
              "Do not delete unrelated files or exported reports")
        print("Local diagnostics and private storage: \(checks) checks passed")
    }
}
