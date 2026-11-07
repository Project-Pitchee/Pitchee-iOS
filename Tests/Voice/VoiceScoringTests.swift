//
//  VoiceScoringTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation

@main
enum VoiceScoringTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        func close(_ left: Double, _ right: Double) -> Bool {
            abs(left - right) < 0.000_001
        }
        // Golden contract cases cover every rule and all flags. The app now
        // invokes Core directly, so comparing two copies of its formula is no
        // longer useful; validate the bridge and immutable-history behavior.
        let cases: [(Double, Double, Double?, Double, String, Double?, Bool, Bool)] = [
            (90, 100, 200, 100, "pass_boost", nil, false, true),
            (70, 20, 180, 30, "high_f0_stylized_cap", 30, true, false),
            (100, 100, 165, 59, "low_f0_natural_cap", 59, true, false),
            (70, 20, 120, 20, "low_f0_stylized_cap", 20, true, false),
            (49, 80, 200, 59, "high_f0_male_cap", 59, true, false),
            (50, 50, 180, 41.83333333333333, "continuous", nil, false, false),
            (63, 90, nil, 63, "f0_unavailable", nil, false, false)
        ]
        for (standard, naturalness, pitch, final, rule, cap, limited, boosted) in cases {
            let score = VoiceDirectionScore.feminineComposite(
                standardScore: standard, naturalness: naturalness, pitchHz: pitch
            )
            check(close(score.finalScore, final), "Feminine golden score: \(rule)")
            check(score.rule == rule && score.cap == cap, "C string and optional cap: \(rule)")
            check(score.limited == limited && score.boosted == boosted, "C flags: \(rule)")
        }
        for (standard, pitch, expected) in [(50.0, 165.0, 60.0), (30, 120, 81), (0, 40, 100), (100, 400, 20)] {
            let score = VoiceDirectionScore.masculineComposite(
                feminineScore: standard, naturalness: 0, pitchHz: pitch
            )
            check(close(score.finalScore, expected) && score.baseScore == score.finalScore,
                  "Masculine golden score and base")
            check(score.rule == "continuous" && score.cap == nil && !score.boosted && !score.limited,
                  "Masculine bridge preserves flags")
        }

        func result(
            pitch: Double? = 120,
            scoreProfile: String? = nil,
            composite: PitcheeAnalysisResult.CompositeScore = .init(
                baseScore: 24, finalScore: 23, cap: 23, rule: "stored-rule", limited: true, boosted: false
            ),
            naturalness: Double = 100
        ) -> PitcheeAnalysisResult {
            .init(
                schemaVersion: 2, modelVersion: "voice-scoring-tests",
                scoreProfile: scoreProfile,
                audio: .init(sourceSampleRate: 16_000, sourceChannels: 1, inputSeconds: 12, analyzedSeconds: 12),
                vad: .init(segmentCount: 0, speechSeconds: 10, sileroSegmentCount: 0, discardedBreathLikeCount: 0, trimmedSegmentCount: 0, segments: []),
                f0: .init(windowSeconds: 0.5, meanHz: pitch, standardDeviationHz: nil, voicedFrameCount: 0, voicedWindowCount: 0, windows: []),
                vfp: .init(vfpStandardScore: 20, windowCount: 0, windowDurationSeconds: 1, windows: []),
                naturalness: .init(score: naturalness, windowCount: 0, windowDurationSeconds: 1, windows: []),
                composite: composite
            )
        }
        let raw = result()
        let payload = try JSONEncoder().encode(raw)
        let masculine = VoicePreference.masculine.score(for: raw)
        check(masculine.standardScore == 80, "Masculine alignment complements feminine tendency")
        check(masculine.naturalnessScore == 100, "Naturalness does not change direction")
        check(masculine.finalScore == 84 && masculine.baseScore == 84, "Masculinization uses the Core continuous score")
        check(raw.composite.finalScore == 23 && raw.vfp.vfpStandardScore == 20, "Raw result remains unchanged")
        for preference in [VoicePreference.feminine, .undecided] {
            let score = preference.score(for: raw)
            check(score.standardScore == 20 && score.naturalnessScore == 100, "Other preferences preserve metrics")
            check(score.baseScore == 24 && score.finalScore == 23 && score.rule == "stored-rule", "Preserve the engine result verbatim")
            check(score.composite.cap == 23 && score.composite.limited && !score.composite.boosted, "Preserve engine flags")
        }
        let coreResult = result(
            scoreProfile: "masculinization",
            composite: .init(baseScore: 81, finalScore: 81, cap: nil, rule: "continuous", limited: false, boosted: false)
        )
        check(VoicePreference.masculine.score(for: coreResult).finalScore == 81,
              "Use the backend composite when the result declares masculinization")
        let switchedToFeminine = VoicePreference.feminine.score(for: coreResult)
        check(close(switchedToFeminine.finalScore, 32) && switchedToFeminine.rule == "low_f0_natural_cap",
              "Switching a masculinization result to feminine recomputes the matching Core profile")
        let exportScoreAfterSwitch = VoiceDirectionScore(preference: .feminine, result: coreResult)
        check(exportScoreAfterSwitch.standardScore == switchedToFeminine.standardScore
                && close(exportScoreAfterSwitch.finalScore, switchedToFeminine.finalScore),
              "Export and result page share the resolved preference after a recording-time switch")
        let decoded = try JSONDecoder().decode(PitcheeAnalysisResult.self, from: payload)
        check(VoicePreference.masculine.score(for: decoded).finalScore == masculine.finalScore, "Persisted raw results reproduce the displayed score")

        for profile: String? in [nil, "feminization", "masculinization", "future-profile"] {
            for pitch: Double? in [nil, 0, -1, 120, 200] {
                for naturalness in [0.0, 100.0] {
                    let full = result(pitch: pitch, scoreProfile: profile, naturalness: naturalness)
                    let summary = try JSONDecoder().decode(VoiceAnalysisSummary.self, from: JSONEncoder().encode(full))
                    for preference in VoicePreference.allCases {
                        let expected = preference.score(for: full)
                        let actual = VoiceDirectionScore(preference: preference, summary: summary)
                        check(actual.standardScore == expected.standardScore && actual.naturalnessScore == expected.naturalnessScore,
                              "History projections preserve metrics for every profile and direction")
                        check(close(actual.baseScore, expected.baseScore) && close(actual.finalScore, expected.finalScore)
                                && actual.rule == expected.rule && actual.composite.cap == expected.composite.cap
                                && actual.composite.limited == expected.composite.limited
                                && actual.composite.boosted == expected.composite.boosted,
                              "History projections share all scoring rules and engine flags with full results")
                    }
                }
            }
        }

        for pitch: Double? in [nil, 0, -1, .nan, .infinity, -.infinity] {
            let score = VoicePreference.masculine.score(for: result(pitch: pitch))
            check(score.finalScore == 69 && score.baseScore == 69, "Missing or invalid pitch removes only the F0 contribution")
            check(score.rule == "continuous" && score.composite.cap == nil, "Fallback uses Core's continuous masculinization rule")
        }
        for value in [Double.nan, .infinity, -.infinity] {
            let missingMetrics = VoiceDirectionScore.feminineComposite(
                standardScore: value, naturalness: value, pitchHz: nil
            )
            check(missingMetrics.finalScore == 0 && missingMetrics.rule == "f0_unavailable",
                  "Nonfinite scores retain the legacy zero-value normalization")
            let feminine = VoiceDirectionScore.feminineComposite(
                standardScore: 63, naturalness: 90, pitchHz: value
            )
            check(feminine.finalScore == 63 && feminine.rule == "f0_unavailable",
                  "Nonfinite feminine pitch retains the missing-pitch fallback")
        }
        let atBoundary = VoiceDirectionScore.feminineComposite(
            standardScore: 70, naturalness: 80, pitchHz: 165
        )
        let pastBoundary = VoiceDirectionScore.feminineComposite(
            standardScore: 70, naturalness: 80, pitchHz: 165.001
        )
        check(atBoundary.rule == "low_f0_natural_cap" && pastBoundary.rule == "continuous",
              "The 165 Hz boundary keeps its inclusive lower-pitch rule")
        let belowNaturalness = VoiceDirectionScore.feminineComposite(
            standardScore: 70, naturalness: 49.999, pitchHz: 180
        )
        let atNaturalness = VoiceDirectionScore.feminineComposite(
            standardScore: 70, naturalness: 50, pitchHz: 180
        )
        check(belowNaturalness.rule == "high_f0_stylized_cap" && atNaturalness.rule == "continuous",
              "The naturalness 50 boundary does not apply the stylized cap")
        let naturalnessIndependent = VoicePreference.masculine.score(for: result(naturalness: 0)).finalScore
        check(naturalnessIndependent == masculine.finalScore, "Masculinization ignores naturalness")
        for (stored, expected) in [("男性向声音", VoicePreference.masculine), ("女性向声音", .feminine), ("暂不确定", .undecided), ("masculine", .masculine), ("feminine", .feminine), ("undecided", .undecided)] {
            check(VoicePreference(legacyStoredValue: stored) == expected, "Restore both legacy and semantic preferences")
        }
        check(VoicePreference(legacyStoredValue: "invalid") == nil, "Unknown preferences are rejected")
        print("Voice scoring: \(checks) checks passed using the stateless Core C API")
    }
}
