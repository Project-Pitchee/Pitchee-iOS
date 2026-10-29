//
//  PracticeData.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation

nonisolated enum PracticeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case pitchObservation, pitchStability, dailyReading
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pitchObservation: String(localized: "practice.kind.pitchObservation.title")
        case .pitchStability: String(localized: "practice.kind.pitchStability.title")
        case .dailyReading: String(localized: "practice.kind.dailyReading.title")
        }
    }
    var instruction: String {
        switch self {
        case .pitchObservation: String(localized: "practice.kind.pitchObservation.instruction")
        case .pitchStability: String(localized: "practice.kind.pitchStability.instruction")
        case .dailyReading: String(localized: "practice.kind.dailyReading.instruction")
        }
    }
}

/// Frozen before microphone permission, including the rendered passage. A locale
/// or settings change between A and B must not change the comparison task.
nonisolated struct PracticeContext: Codable, Equatable, Sendable {
    let sessionID: UUID
    let kind: PracticeKind
    let target: VoicePreference
    let promptID: String
    let passage: String
    let scoringVersion: String

    init(kind: PracticeKind, target: VoicePreference) {
        sessionID = UUID()
        self.kind = kind
        self.target = target
        promptID = "short-reading-v1"
        passage = String(localized: "practice.passage.v1")
        scoringVersion = VoiceDirectionScore.rulesVersion
    }
}

nonisolated enum PracticeMetric: String, CaseIterable, Identifiable {
    case pitch, variation, speech
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pitch: String(localized: "practice.metric.pitch")
        case .variation: String(localized: "practice.metric.variation")
        case .speech: String(localized: "practice.metric.speech")
        }
    }
}

nonisolated enum PracticeFeedback: String, Codable, CaseIterable, Identifiable {
    case closer, similar, unsure
    var id: String { rawValue }
    var title: String {
        switch self {
        case .closer: String(localized: "practice.feedback.closer")
        case .similar: String(localized: "practice.feedback.similar")
        case .unsure: String(localized: "practice.feedback.unsure")
        }
    }
}

/// Conservative recording checks, independent of VFP/naturalness/model scores.
/// These thresholds are provisional capture heuristics, not clinical judgements.
nonisolated struct RecordingQuality: Codable, Equatable, Sendable {
    static let minimumSpeechSeconds = 5.0

    static func hasMinimumSpeech(_ seconds: Double) -> Bool {
        seconds.isFinite && seconds >= minimumSpeechSeconds
    }

    enum Issue: String, Codable, CaseIterable {
        case shortSpeech, lowLevel, background, clipping, unavailable
        var advice: String {
            switch self {
            case .shortSpeech: String(localized: "practice.quality.shortSpeech")
            case .lowLevel: String(localized: "practice.quality.lowLevel")
            case .background: String(localized: "practice.quality.background")
            case .clipping: String(localized: "practice.quality.clipping")
            case .unavailable: String(localized: "practice.quality.unavailable")
            }
        }
    }
    static let rulesVersion = "capture-quality-v1"
    let version: String
    let issues: [Issue]
    let backgroundMeasured: Bool
    var canCompare: Bool { version == Self.rulesVersion && issues.isEmpty }

    init(speechSeconds: Double, speechDBFS: Double?, backgroundDBFS: Double?, clippedFraction: Double?) {
        version = Self.rulesVersion
        var issues: [Issue] = []
        if !Self.hasMinimumSpeech(speechSeconds) {
            issues.append(.shortSpeech)
        }
        if let speechDBFS, speechDBFS.isFinite, (-120...0).contains(speechDBFS) {
            if speechDBFS < -45 { issues.append(.lowLevel) }
        } else { issues.append(.unavailable) }
        backgroundMeasured = backgroundDBFS.map { $0.isFinite && (-120...0).contains($0) } ?? false
        if backgroundMeasured, let speechDBFS, speechDBFS.isFinite, let backgroundDBFS,
           speechDBFS - backgroundDBFS < 10 { issues.append(.background) }
        if let clippedFraction, clippedFraction.isFinite, (0...1).contains(clippedFraction) {
            if clippedFraction >= 0.01 { issues.append(.clipping) }
        } else if !issues.contains(.unavailable) { issues.append(.unavailable) }
        self.issues = issues
    }
}

/// Separate cohorts even when display names match: exact material, target,
/// scoring rules, quality rules, and model all influence comparability.
nonisolated struct PracticeCohort: Hashable, Identifiable {
    let kind: PracticeKind
    let target: VoicePreference
    let promptID: String
    let passage: String
    let scoringVersion: String
    let modelVersion: String
    let qualityVersion: String
    var id: Self { self }
}

nonisolated struct DailyPracticeSummary: Identifiable {
    let date: Date
    let median: Double
    let minimum: Double
    let maximum: Double
    let count: Int
    var id: Date { date }

    init?(date: Date, values: [Double]) {
        let sorted = values.filter(\.isFinite).sorted()
        guard let minimum = sorted.first, let maximum = sorted.last else { return nil }
        self.date = date
        self.minimum = minimum
        self.maximum = maximum
        count = sorted.count
        let middle = count / 2
        median = count.isMultiple(of: 2) ? sorted[middle - 1] / 2 + sorted[middle] / 2 : sorted[middle]
    }
}
