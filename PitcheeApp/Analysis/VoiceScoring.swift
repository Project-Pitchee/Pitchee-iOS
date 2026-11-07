//
//  VoiceScoring.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import CPitcheeCore
import Foundation

nonisolated enum VoicePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case masculine
    case feminine
    case undecided

    var id: String { rawValue }

    /// Accept the display strings persisted by builds before semantic keys.
    init?(legacyStoredValue: String) {
        switch legacyStoredValue {
        case "男性向声音": self = .masculine
        case "女性向声音": self = .feminine
        case "暂不确定": self = .undecided
        default:
            guard let value = Self(rawValue: legacyStoredValue) else { return nil }
            self = value
        }
    }

    func score(for result: PitcheeAnalysisResult) -> VoiceDirectionScore {
        VoiceDirectionScore(preference: self, result: result)
    }
}

/// Scalar fields needed by history and scoring. Window/segment arrays belong to
/// detail views and are deliberately not decoded or retained by this projection.
nonisolated struct VoiceAnalysisSummary: Decodable, Sendable {
    let scoreProfile: String?
    let standardScore: Double
    let naturalnessScore: Double
    let pitchHz: Double?
    let pitchVariationHz: Double?
    let composite: PitcheeAnalysisResult.CompositeScore

    init(result: PitcheeAnalysisResult) {
        scoreProfile = result.scoreProfile
        standardScore = result.vfp.vfpStandardScore
        naturalnessScore = result.naturalness.score
        pitchHz = result.f0.meanHz
        pitchVariationHz = result.f0.standardDeviationHz
        composite = result.composite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scoreProfile = try container.decodeIfPresent(String.self, forKey: .scoreProfile)
        let pitch = try container.nestedContainer(keyedBy: PitchKeys.self, forKey: .f0)
        pitchHz = try pitch.decodeIfPresent(Double.self, forKey: .meanHz)
        pitchVariationHz = try pitch.decodeIfPresent(Double.self, forKey: .standardDeviationHz)
        let voice = try container.nestedContainer(keyedBy: VoiceKeys.self, forKey: .vfp)
        standardScore = try voice.decode(Double.self, forKey: .vfpStandardScore)
        let naturalness = try container.nestedContainer(keyedBy: NaturalnessKeys.self, forKey: .naturalness)
        naturalnessScore = try naturalness.decode(Double.self, forKey: .score)
        composite = try container.decode(PitcheeAnalysisResult.CompositeScore.self, forKey: .composite)
    }

    private enum CodingKeys: String, CodingKey { case scoreProfile, f0, vfp, naturalness, composite }
    private enum PitchKeys: String, CodingKey { case meanHz, standardDeviationHz }
    private enum VoiceKeys: String, CodingKey { case vfpStandardScore }
    private enum NaturalnessKeys: String, CodingKey { case score }
}

/// A presentation of the immutable engine result for the current practice goal.
/// VFP remains a feminine reference score in storage and in the two-sided chart.
/// New analyses request Core's explicit masculinization profile. The stateless
/// Core scoring API also provides the compatibility path for older stored
/// results that do not contain `score_profile` in their JSON payload.
nonisolated struct VoiceDirectionScore {
    static let rulesVersion = "core-score-profile-v1"
    let standardScore: Double
    let naturalnessScore: Double
    let composite: PitcheeAnalysisResult.CompositeScore

    var baseScore: Double { composite.baseScore }
    var finalScore: Double { composite.finalScore }
    var rule: String { composite.rule }

    init(preference: VoicePreference, result: PitcheeAnalysisResult) {
        self.init(preference: preference, summary: VoiceAnalysisSummary(result: result))
    }

    init(preference: VoicePreference, summary: VoiceAnalysisSummary) {
        naturalnessScore = summary.naturalnessScore
        if preference == .masculine {
            standardScore = 100 - Self.clamp(summary.standardScore, to: 100)
            if summary.scoreProfile == "masculinization" {
                composite = summary.composite
            } else {
                composite = Self.masculineComposite(
                    feminineScore: summary.standardScore,
                    naturalness: summary.naturalnessScore,
                    pitchHz: summary.pitchHz
                )
            }
        } else if preference == .feminine, summary.scoreProfile == "masculinization" {
            standardScore = Self.clamp(summary.standardScore, to: 100)
            composite = Self.feminineComposite(
                standardScore: summary.standardScore,
                naturalness: summary.naturalnessScore,
                pitchHz: summary.pitchHz
            )
        } else {
            // Preserve the engine's original result for feminine/undecided
            // results that already use the matching profile or an older schema.
            standardScore = summary.standardScore
            composite = summary.composite
        }
    }

    static func masculineComposite(
        feminineScore: Double, naturalness: Double, pitchHz: Double?
    ) -> PitcheeAnalysisResult.CompositeScore {
        coreComposite(profile: PITCHEE_SCORE_PROFILE_MASCULINIZATION,
                      standardScore: feminineScore, naturalness: naturalness, pitchHz: pitchHz)
    }

    /// Recompute a stored recording for the current direction without loading
    /// models or changing the immutable persisted analysis.
    static func feminineComposite(
        standardScore: Double, naturalness: Double, pitchHz: Double?
    ) -> PitcheeAnalysisResult.CompositeScore {
        coreComposite(profile: PITCHEE_SCORE_PROFILE_FEMINIZATION,
                      standardScore: standardScore, naturalness: naturalness, pitchHz: pitchHz)
    }

    private static func coreComposite(
        profile: pitchee_score_profile_t,
        standardScore: Double, naturalness: Double, pitchHz: Double?
    ) -> PitcheeAnalysisResult.CompositeScore {
        var score = pitchee_score_result_t()
        let pitch = pitchHz.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let status = pitchee_score(
            profile, clamp(standardScore, to: 100), clamp(naturalness, to: 100),
            pitch ?? .nan, &score
        )
        guard status == PITCHEE_SUCCESS else {
            // A native allocation failure must not crash history rendering or
            // silently reuse a score calculated for the opposite direction.
            return .init(baseScore: 0, finalScore: 0, cap: nil,
                         rule: "score_unavailable", limited: false, boosted: false)
        }
        let rule = withUnsafeBytes(of: score.score_rule) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return .init(baseScore: score.base_score, finalScore: score.final_score,
                     cap: score.has_score_cap == 0 ? nil : score.score_cap,
                     rule: rule, limited: score.score_limited != 0, boosted: score.score_boosted != 0)
    }

    private static func clamp(_ value: Double, to upper: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), upper)
    }
}
