//
//  RecordingAssessment.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/18.
//

import Foundation
import SwiftData

/// A persisted snapshot of one completed recording assessment.
///
/// Frequently displayed values are stored as columns so that trends can be
/// queried efficiently. `resultPayload` keeps the complete engine response,
/// including VAD segments and per-window scores, for future features.
@Model
final class RecordingAssessment {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date

    var schemaVersion: Int
    var modelVersion: String

    var inputSeconds: Double
    var analyzedSeconds: Double
    var speechSeconds: Double
    var meanPitchHz: Double?

    var standardScore: Double
    var naturalnessScore: Double
    var finalScore: Double
    var scoreWasLimited: Bool

    var resultPayload: Data

    // Optional additions preserve pre-practice history without inventing a goal
    // or a quality judgement for recordings captured by older builds.
    var practicePayload: Data?
    var qualityPayload: Data?
    var recordedTargetRawValue: String?
    var scoringRulesVersion: String?
    var capturedFinalScore: Double?
    var comparedToID: UUID?
    var comparisonFeedbackRawValue: String?

    // History keeps only scalar inputs; full window/segment arrays are decoded
    // on demand for detail/export. These caches never change the store schema.
    @Transient private var summaryCache = DecodedPayloadCache<VoiceAnalysisSummary>()
    @Transient private var resultCache = DecodedPayloadCache<PitcheeAnalysisResult>()
    @Transient private var practiceCache = DecodedPayloadCache<PracticeContext>()
    @Transient private var qualityCache = DecodedPayloadCache<RecordingQuality>()

    init(
        id: UUID = UUID(),
        recordedAt: Date,
        result: PitcheeAnalysisResult,
        preference: VoicePreference? = nil,
        practice: PracticeContext? = nil,
        quality: RecordingQuality? = nil,
        comparedToID: UUID? = nil
    ) throws {
        self.id = id
        self.recordedAt = recordedAt
        schemaVersion = result.schemaVersion
        modelVersion = result.modelVersion
        inputSeconds = result.audio.inputSeconds
        analyzedSeconds = result.audio.analyzedSeconds
        speechSeconds = result.vad.speechSeconds
        meanPitchHz = result.f0.meanHz
        standardScore = result.vfp.vfpStandardScore
        naturalnessScore = result.naturalness.score
        finalScore = result.composite.finalScore
        scoreWasLimited = result.composite.limited
        resultPayload = try Self.encoder.encode(result)
        practicePayload = try practice.map { try Self.encoder.encode($0) }
        qualityPayload = try quality.map { try Self.encoder.encode($0) }
        let target = practice?.target ?? preference
        recordedTargetRawValue = target?.rawValue
        scoringRulesVersion = practice?.scoringVersion ?? target.map { _ in VoiceDirectionScore.rulesVersion }
        capturedFinalScore = target.flatMap { $0 == .undecided ? nil : $0.score(for: result).finalScore }
        self.comparedToID = comparedToID
    }

    var practice: PracticeContext? { practiceCache.value(for: practicePayload, decoder: Self.decoder) }
    var quality: RecordingQuality? { qualityCache.value(for: qualityPayload, decoder: Self.decoder) }
    var recordedTarget: VoicePreference? { recordedTargetRawValue.flatMap(VoicePreference.init(rawValue:)) }
    var isBaselineEligible: Bool { quality?.canCompare == true && cohort != nil }
    var cohort: PracticeCohort? {
        guard let practice, let quality else { return nil }
        return PracticeCohort(kind: practice.kind, target: practice.target,
                              promptID: practice.promptID, passage: practice.passage,
                              scoringVersion: practice.scoringVersion, modelVersion: modelVersion,
                              qualityVersion: quality.version)
    }

    /// The complete result as returned by PitcheeCore.
    var result: PitcheeAnalysisResult? {
        resultCache.value(for: resultPayload, decoder: Self.decoder)
    }

    var pitchVariationHz: Double? { summary?.pitchVariationHz }
    public var hnrDb: Double? { result?.voiceQuality?.hnrDb }

    // Valid summary fields remain usable even if unused window details are
    // malformed. Full-detail decoding still rejects an unreadable result.
    private var summary: VoiceAnalysisSummary? {
        summaryCache.value(for: resultPayload, decoder: Self.decoder)
    }

    /// Re-evaluate existing recordings without rewriting their raw results.
    func finalScore(for preference: VoicePreference) -> Double {
        guard preference != .undecided else { return finalScore }
        if let summary {
            return VoiceDirectionScore(preference: preference, summary: summary).finalScore
        }
        if preference == .masculine {
            return VoiceDirectionScore.masculineComposite(
                feminineScore: standardScore, naturalness: naturalnessScore, pitchHz: meanPitchHz
            ).finalScore
        }
        return finalScore
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

/// Cache successful and failed decodes, refreshing whenever persisted bytes change.
/// Keeping the source Data also detects edits made through another model context.
nonisolated private struct DecodedPayloadCache<Value: Decodable> {
    private var source: Data?
    private var decoded: Value?

    mutating func value(for payload: Data?, decoder: JSONDecoder) -> Value? {
        guard source != payload else { return decoded }
        source = payload
        decoded = payload.flatMap { try? decoder.decode(Value.self, from: $0) }
        return decoded
    }
}

/// Derived dashboard values for all successfully persisted assessments.
///
/// This intentionally stays derived instead of being stored as another
/// mutable record. Saving a new assessment therefore makes the next query
/// produce a fresh baseline automatically, without a second source of truth.
struct RecordingAssessmentAverages {
    let finalScore: Double?
    let naturalnessScore: Double?
    let meanPitchHz: Double?
    let speechSeconds: Double?

    init(assessments: [RecordingAssessment], preference: VoicePreference = .undecided) {
        finalScore = Self.average(assessments.map { $0.finalScore(for: preference) })
        naturalnessScore = Self.average(assessments.map(\.naturalnessScore))
        meanPitchHz = Self.average(assessments.compactMap(\.meanPitchHz))
        speechSeconds = Self.average(assessments.map(\.speechSeconds))
    }

    private static func average(_ values: [Double]) -> Double? {
        let finiteValues = values.filter(\.isFinite)
        guard !finiteValues.isEmpty else { return nil }
        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }
}
