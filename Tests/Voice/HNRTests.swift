import Foundation
import SwiftData

@main
enum HNRTests {
    // Frozen v3 wire format: voiceQuality did not exist in older recordings.
    static let v3Payload = Data("""
    {
      "schemaVersion": 3,
      "modelVersion": "hnr-tests",
      "scoreProfile": "feminization",
      "audio": { "sourceSampleRate": 16000, "sourceChannels": 1,
                 "inputSeconds": 0.15, "analyzedSeconds": 0.15 },
      "vad": { "segmentCount": 1, "speechSeconds": 0.15,
               "sileroSegmentCount": 1, "discardedBreathLikeCount": 0,
               "trimmedSegmentCount": 0,
               "segments": [{ "startSeconds": 0, "endSeconds": 0.15,
                              "speechStartSeconds": 0, "speechEndSeconds": 0.15 }] },
      "f0": { "windowSeconds": 0.05, "meanHz": 200,
              "standardDeviationHz": 0, "voicedFrameCount": 2,
              "voicedWindowCount": 2,
              "windows": [{ "startSeconds": 0, "endSeconds": 0.05, "f0Hz": 200 },
                          { "startSeconds": 0.05, "endSeconds": 0.1, "f0Hz": null },
                          { "startSeconds": 0.1, "endSeconds": 0.15, "f0Hz": 200 }] },
      "vfp": { "vfpStandardScore": 70, "windowCount": 0,
               "windowDurationSeconds": 1, "windows": [] },
      "naturalness": { "score": 80, "windowCount": 0,
                       "windowDurationSeconds": 1, "windows": [] },
      "composite": { "baseScore": 75, "finalScore": 75, "cap": null,
                     "rule": "stored-rule", "limited": false, "boosted": false }
    }
    """.utf8)

    @MainActor static func main() throws {
        if CommandLine.arguments.count == 3 {
            let url = URL(fileURLWithPath: CommandLine.arguments[2])
            switch CommandLine.arguments[1] {
            case "--write-store":
                try writeStore(to: url)
            case "--read-store":
                try readStore(from: url)
            default:
                preconditionFailure("Unknown HNR test mode")
            }
            return
        }

        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }

        let decoder = JSONDecoder()
        let legacy = try decoder.decode(PitcheeAnalysisResult.self, from: v3Payload)
        check(legacy.schemaVersion == 3 && legacy.voiceQuality == nil,
              "A v3 recording without voiceQuality decodes as unknown")
        let recording = try RecordingAssessment(recordedAt: .distantPast, result: legacy)
        check(recording.hnrDb == nil, "Legacy recording accessor preserves nil")

        let current = try resultWithHNR()
        let encoded = try JSONEncoder().encode(current)
        let decoded = try decoder.decode(PitcheeAnalysisResult.self, from: encoded)
        let quality = try requireQuality(decoded)
        check(decoded.schemaVersion == 4 && quality.algorithm == "autocorr-praat-v1",
              "Schema v4 carries the locked algorithm identifier")
        check(quality.hnrDb == 5 && quality.hnrWindowCount == 2 && quality.hnrStdDb == 7,
              "Recording-level HNR mean, count, and standard deviation round-trip")
        check(quality.windowSeconds == 0.04 && decoded.f0.windowSeconds == 0.05,
              "HNR preserves its own 40 ms window independently of the 50 ms F0 grid")
        check(quality.windows.count == 15 && decoded.f0.windows.count == 3,
              "HNR and F0 preserve independently sized timelines")
        for (index, hnr) in quality.windows.enumerated() {
            check(hnr.startSeconds == Double(index) * 0.01
                    && hnr.endSeconds == min(0.15, hnr.startSeconds + 0.04),
                  "HNR preserves 10 ms hops, overlapping windows, and partial tails")
        }
        check(quality.windows.compactMap(\.hnrDb) == [-2, 12]
                && quality.windows[1].hnrDb == nil,
              "Negative HNR remains valid and unreliable windows retain nil")
        check(quality.windows[7].hnrDb == 12 && decoded.f0.windows[1].f0Hz == nil,
              "Reliable HNR inside VAD survives even where the model's F0 window is unavailable")
        check(decoded.vad.segments[0].startSeconds == 0.03
                && decoded.vad.segments[0].endSeconds == 0.1
                && quality.windows[2].hnrDb == -2 && quality.windows[7].hnrDb == 12,
              "Valid HNR windows remain inside the recorded source VAD interval")
        check(quality.windows[0].hnrDb == nil
                && quality.windows[8...].allSatisfy { $0.hnrDb == nil },
              "HNR before or after source VAD retains nil on the independent timeline")
        check(decoded.composite.finalScore == legacy.composite.finalScore
                && decoded.composite.rule == legacy.composite.rule
                && decoded.vfp.vfpStandardScore == legacy.vfp.vfpStandardScore
                && decoded.naturalness.score == legacy.naturalness.score,
              "Adding HNR preserves recorded scores")

        let previousV4 = try resultWithHNR(
            voiceQuality: .init(
                algorithm: "autocorr-praat-v1", hnrDb: 5, hnrWindowCount: 2,
                hnrStdDb: 7, windowSeconds: 0.05,
                windows: [.init(startSeconds: 0, endSeconds: 0.05, hnrDb: -2),
                          .init(startSeconds: 0.05, endSeconds: 0.1, hnrDb: nil),
                          .init(startSeconds: 0.1, endSeconds: 0.15, hnrDb: 12)]
            ),
            vad: legacy.vad
        )
        let previousDecoded = try decoder.decode(
            PitcheeAnalysisResult.self, from: JSONEncoder().encode(previousV4)
        )
        let previousQuality = try requireQuality(previousDecoded)
        check(previousQuality.windowSeconds == 0.05 && previousQuality.windows.count == 3
                && previousQuality.windows[2].startSeconds == 0.1
                && previousQuality.hnrDb == 5,
              "Previously stored v4 HNR windows decode unchanged without recomputation")

        recording.resultPayload = encoded
        check(recording.hnrDb == 5, "Accessor decodes the new payload after an earlier nil")
        recording.resultPayload = Data()
        check(recording.result == nil && recording.hnrDb == nil,
              "An empty result payload propagates nil")
        recording.resultPayload = Data("unreadable-result".utf8)
        check(recording.result == nil && recording.hnrDb == nil,
              "An unreadable result payload propagates nil without crashing")
        recording.resultPayload = encoded
        check(recording.hnrDb == 5, "A valid replacement clears a cached decoding failure")

        var explicitNull = try JSONSerialization.jsonObject(with: v3Payload) as! [String: Any]
        explicitNull["schemaVersion"] = 4
        explicitNull["voiceQuality"] = NSNull()
        recording.resultPayload = try JSONSerialization.data(withJSONObject: explicitNull)
        check(recording.result?.schemaVersion == 4 && recording.hnrDb == nil,
              "An explicit null voiceQuality segment stays nil")

        for windows in [
            [PitcheeAnalysisResult.HNRWindow](),
            quality.windows.map {
                .init(startSeconds: $0.startSeconds, endSeconds: $0.endSeconds, hnrDb: nil)
            }
        ] {
            let unavailable = try resultWithHNR(voiceQuality: .init(
                algorithm: "autocorr-praat-v1", hnrDb: nil, hnrWindowCount: 0,
                hnrStdDb: nil, windowSeconds: 0.04, windows: windows
            ))
            recording.resultPayload = try JSONEncoder().encode(unavailable)
            let unavailableQuality = try requireQuality(recording.result!)
            check(recording.hnrDb == nil && unavailableQuality.hnrStdDb == nil
                    && unavailableQuality.hnrWindowCount == 0,
                  "Empty or wholly unreliable HNR data propagates nil, never zero")
            check(unavailableQuality.windows.count == windows.count
                    && unavailableQuality.windows.allSatisfy { $0.hnrDb == nil },
                  "Unavailable HNR windows survive JSON persistence")
        }

        let outsideVAD = try resultWithHNR(
            voiceQuality: .init(
                algorithm: "autocorr-praat-v1", hnrDb: nil, hnrWindowCount: 0,
                hnrStdDb: nil, windowSeconds: 0.04,
                windows: quality.windows.map {
                    .init(startSeconds: $0.startSeconds, endSeconds: $0.endSeconds, hnrDb: nil)
                }
            ),
            vad: .init(segmentCount: 0, speechSeconds: 0, sileroSegmentCount: 0,
                       discardedBreathLikeCount: 0, trimmedSegmentCount: 0, segments: [])
        )
        recording.resultPayload = try JSONEncoder().encode(outsideVAD)
        check(recording.result?.vad.segments.isEmpty == true && recording.hnrDb == nil
                && recording.result?.voiceQuality?.windows.count == 15,
              "Empty VAD retains all HNR windows and propagates nil aggregates")
        print("HNR Swift schema and nil propagation: \(checks) checks passed")
    }

    nonisolated private static func resultWithHNR(
        voiceQuality: PitcheeAnalysisResult.VoiceQuality = .init(
            algorithm: "autocorr-praat-v1", hnrDb: 5, hnrWindowCount: 2,
            hnrStdDb: 7, windowSeconds: 0.04,
            windows: (0..<15).map { index in
                let start = Double(index) * 0.01
                return .init(
                    startSeconds: start, endSeconds: min(0.15, start + 0.04),
                    hnrDb: index == 2 ? -2 : (index == 7 ? 12 : nil)
                )
            }
        ),
        vad: PitcheeAnalysisResult.VoiceActivity = .init(
            segmentCount: 1, speechSeconds: 0.07, sileroSegmentCount: 1,
            discardedBreathLikeCount: 0, trimmedSegmentCount: 0,
            segments: [.init(startSeconds: 0.03, endSeconds: 0.1,
                             speechStartSeconds: 0, speechEndSeconds: 0.07)]
        )
    ) throws -> PitcheeAnalysisResult {
        let old = try JSONDecoder().decode(PitcheeAnalysisResult.self, from: v3Payload)
        return .init(
            schemaVersion: 4, modelVersion: old.modelVersion, scoreProfile: old.scoreProfile,
            audio: old.audio, vad: vad, f0: old.f0, vfp: old.vfp,
            naturalness: old.naturalness, composite: old.composite, voiceQuality: voiceQuality
        )
    }

    nonisolated private static func requireQuality(
        _ result: PitcheeAnalysisResult
    ) throws -> PitcheeAnalysisResult.VoiceQuality {
        guard let voiceQuality = result.voiceQuality else {
            throw CocoaError(.coderValueNotFound)
        }
        return voiceQuality
    }

    @MainActor private static func writeStore(to url: URL) throws {
        let container = try ModelContainer(
            for: RecordingAssessment.self, configurations: ModelConfiguration(url: url)
        )
        let old = try RecordingAssessment(
            recordedAt: Date(timeIntervalSince1970: 1),
            result: JSONDecoder().decode(PitcheeAnalysisResult.self, from: v3Payload)
        )
        // Retain the original bytes, including the absence of the new field.
        old.resultPayload = v3Payload
        let current = try RecordingAssessment(
            recordedAt: Date(timeIntervalSince1970: 2), result: resultWithHNR()
        )
        container.mainContext.insert(old)
        container.mainContext.insert(current)
        try container.mainContext.save()
        print("HNR persistence: wrote v3 and v4 recordings")
    }

    @MainActor private static func readStore(from url: URL) throws {
        let container = try ModelContainer(
            for: RecordingAssessment.self, configurations: ModelConfiguration(url: url)
        )
        let records = try container.mainContext.fetch(FetchDescriptor<RecordingAssessment>(
            sortBy: [SortDescriptor(\.recordedAt)]
        ))
        precondition(records.count == 2)
        let old = records[0]
        precondition(old.schemaVersion == 3 && old.resultPayload == v3Payload)
        precondition(old.result?.voiceQuality == nil && old.hnrDb == nil)
        let current = records[1]
        precondition(current.schemaVersion == 4 && current.hnrDb == 5)
        precondition(current.result?.voiceQuality?.algorithm == "autocorr-praat-v1")
        precondition(current.result?.voiceQuality?.windows.count == 15)
        precondition(current.result?.f0.windows.count == 3)
        precondition(current.result?.voiceQuality?.windowSeconds == 0.04)
        precondition(current.result?.f0.windowSeconds == 0.05)
        precondition(current.result?.voiceQuality?.windows[1].startSeconds == 0.01)
        precondition(current.result?.voiceQuality?.windows[1].endSeconds == 0.05)
        precondition(current.result?.voiceQuality?.windows[0].hnrDb == nil)
        precondition(current.result?.voiceQuality?.windows[2].hnrDb == -2)
        precondition(current.result?.vad.segments[0].startSeconds == 0.03)
        print("HNR persistence: reopened v3 and v4 recordings with independent optional HNR")
    }
}
