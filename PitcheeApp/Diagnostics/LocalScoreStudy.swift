//
//  LocalScoreStudy.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation

nonisolated enum ScoreStudyDirection: Int, CaseIterable, Codable, Sendable {
    case feminine, masculine
}

/// Self-reported goal alignment, not gender identity or an acoustic ground truth.
nonisolated enum ScoreStudyRating: Int, CaseIterable, Sendable {
    case notAtAll, slightly, partly, mostly, fully
}

nonisolated enum ScoreStudyResponse: Int, CaseIterable, Codable, Sendable {
    case rated, unableToJudge, skipped, timedOut, interrupted
}

nonisolated enum ScoreStudyAnalysis: Int, CaseIterable, Codable, Sendable {
    case comparable, unavailable, failed, interrupted
}

nonisolated enum ScoreStudyFeedback: Sendable {
    case rating(ScoreStudyRating), unableToJudge, skipped, timedOut

    var response: ScoreStudyResponse {
        switch self {
        case .rating: .rated
        case .unableToJudge: .unableToJudge
        case .skipped: .skipped
        case .timedOut: .timedOut
        }
    }

    var rating: ScoreStudyRating? {
        if case .rating(let rating) = self { return rating }
        return nil
    }
}

/// Only coarse ordinal predictions may cross into the study accumulator.
/// The production evaluator is in ScoreStudyEvaluator; no scores are persisted.
nonisolated struct ScoreStudyPair: Sendable {
    private let baseline: Int
    private let candidate: Int

    init?(baseline: Double, candidate: Double) {
        guard baseline.isFinite, candidate.isFinite,
              (0...100).contains(baseline), (0...100).contains(candidate) else { return nil }
        self.baseline = Int((baseline / 25).rounded())
        self.candidate = Int((candidate / 25).rounded())
    }

    /// Candidate ordinal absolute error minus baseline error, in -4...4.
    /// Negative values mean closer to this self-rating, not a better model.
    func lossDifference(from rating: ScoreStudyRating) -> Int {
        abs(candidate - rating.rawValue) - abs(baseline - rating.rawValue)
    }
}

nonisolated struct ScoreStudySummary: Codable, Equatable, Sendable {
    private(set) var screened = 0
    private(set) var invited = 0
    private(set) var responses = Array(repeating: 0, count: ScoreStudyResponse.allCases.count)
    private(set) var analyses = Array(repeating: 0, count: ScoreStudyAnalysis.allCases.count)
    private(set) var lossDifferences = Array(repeating: 0, count: 9)

    var responded: Int { responses.reduce(0, +) }
    var finished: Int { analyses.reduce(0, +) }
    var paired: Int { lossDifferences.reduce(0, +) }
    var candidateCloser: Int { lossDifferences.prefix(4).reduce(0, +) }
    var equalDistance: Int { lossDifferences[4] }
    var baselineCloser: Int { lossDifferences.suffix(4).reduce(0, +) }

    mutating func screen(selected: Bool) {
        screened += 1
        if selected { invited += 1 }
    }

    mutating func respond(_ response: ScoreStudyResponse) { responses[response.rawValue] += 1 }

    mutating func finish(_ outcome: ScoreStudyAnalysis, lossDifference: Int?) {
        analyses[outcome.rawValue] += 1
        if let lossDifference { lossDifferences[lossDifference + 4] += 1 }
    }

    mutating func recover() {
        if responded < invited { respond(.interrupted) }
        if finished < invited { finish(.interrupted, lossDifference: nil) }
    }

    var isValid: Bool {
        guard (0...LocalScoreStudyState.screenLimit).contains(screened),
              (0...LocalScoreStudyState.invitationLimit).contains(invited), invited <= screened,
              responses.count == ScoreStudyResponse.allCases.count,
              analyses.count == ScoreStudyAnalysis.allCases.count, lossDifferences.count == 9,
              (responses + analyses + lossDifferences).allSatisfy({ (0...invited).contains($0) }) else { return false }
        return responded <= invited && finished <= responded
            && invited - responded <= 1 && invited - finished <= 1
            && paired <= responses[ScoreStudyResponse.rated.rawValue]
            && paired <= analyses[ScoreStudyAnalysis.comparable.rawValue]
    }
}

nonisolated struct LocalScoreStudyState: Codable, Sendable {
    static let invitationLimit = 5
    static let screenLimit = 100
    static let feedbackSeconds: TimeInterval = 30
    static let retentionSeconds: TimeInterval = 7 * 24 * 60 * 60
    static let currentCandidate = "continuous-base-v1"
    static let currentBaseline = "direction-score-v1"

    private(set) var schemaVersion = 1
    private(set) var candidateID = currentCandidate
    private(set) var baselineID = currentBaseline
    private(set) var enabled = false
    private(set) var periodStartedAt: Date
    private(set) var usedInvitations = 0
    private(set) var usedScreens = 0
    private(set) var summaries = Array(repeating: ScoreStudySummary(), count: 2)
    private(set) var configuration: DiagnosticConfiguration

    init(now: Date, configuration: DiagnosticConfiguration) {
        periodStartedAt = now
        self.configuration = configuration
    }

    var isValid: Bool {
        guard schemaVersion == 1, candidateID == Self.currentCandidate, baselineID == Self.currentBaseline,
              configuration.isValid, periodStartedAt.timeIntervalSince1970.isFinite,
              (0...Self.invitationLimit).contains(usedInvitations),
              (0...Self.screenLimit).contains(usedScreens), usedInvitations <= usedScreens,
              summaries.count == 2, summaries.allSatisfy(\.isValid) else { return false }
        return summaries.map(\.screened).reduce(0, +) <= usedScreens
            && summaries.map(\.invited).reduce(0, +) <= usedInvitations
            && summaries.map { $0.invited - $0.finished }.reduce(0, +) <= 1
            && (enabled || summaries.allSatisfy { $0 == ScoreStudySummary() })
    }

    mutating func refresh(now: Date, configuration: DiagnosticConfiguration) -> Bool {
        let expired = now.timeIntervalSince(periodStartedAt) >= Self.retentionSeconds
        guard expired || now < periodStartedAt || self.configuration != configuration else { return false }
        clear()
        self.configuration = configuration
        if expired {
            periodStartedAt = now
            usedInvitations = 0
            usedScreens = 0
        }
        return true
    }

    mutating func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        clear()
    }

    mutating func clear() { summaries = Array(repeating: ScoreStudySummary(), count: 2) }

    mutating func screen(direction: ScoreStudyDirection, selected: Bool) -> Bool {
        guard enabled, usedInvitations < Self.invitationLimit, usedScreens < Self.screenLimit,
              summaries.allSatisfy({ $0.invited == $0.finished }) else { return false }
        usedScreens += 1
        summaries[direction.rawValue].screen(selected: selected)
        if selected { usedInvitations += 1 }
        return selected
    }

    mutating func respond(direction: ScoreStudyDirection, response: ScoreStudyResponse) {
        let summary = summaries[direction.rawValue]
        guard enabled, summary.responded < summary.invited else { return }
        summaries[direction.rawValue].respond(response)
    }

    mutating func finish(direction: ScoreStudyDirection, outcome: ScoreStudyAnalysis, lossDifference: Int?) {
        let summary = summaries[direction.rawValue]
        guard enabled, summary.finished < summary.responded,
              lossDifference.map({ (-4...4).contains($0) }) ?? true else { return }
        summaries[direction.rawValue].finish(outcome, lossDifference: lossDifference)
    }

    mutating func recover() {
        for index in summaries.indices { summaries[index].recover() }
    }
}
