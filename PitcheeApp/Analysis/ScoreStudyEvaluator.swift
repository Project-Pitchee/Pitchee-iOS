//
//  ScoreStudyEvaluator.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation

enum ScoreStudyEvaluator {
    /// The candidate is the already-computed continuous base score. Production
    /// scores/rules and stored history are neither edited nor replaced.
    static func pair(for result: PitcheeAnalysisResult, direction: ScoreStudyDirection) -> ScoreStudyPair? {
        guard let pitch = result.f0.meanHz, pitch.isFinite, pitch > 0,
              result.vfp.vfpStandardScore.isFinite, (0...100).contains(result.vfp.vfpStandardScore),
              result.naturalness.score.isFinite, (0...100).contains(result.naturalness.score) else { return nil }
        let preference: VoicePreference = direction == .feminine ? .feminine : .masculine
        let score = preference.score(for: result)
        return ScoreStudyPair(baseline: score.finalScore, candidate: score.baseScore)
    }

    static func direction(for preference: VoicePreference) -> ScoreStudyDirection? {
        switch preference {
        case .feminine: .feminine
        case .masculine: .masculine
        case .undecided: nil
        }
    }
}
