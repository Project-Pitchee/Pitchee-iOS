//
//  LocalDiagnostics.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation

// Local inspection only. This is not an upload payload or a privacy protocol.
// No recording IDs, timestamps, scores, voice features, or arbitrary strings.
nonisolated enum DiagnosticOutcome: Int, CaseIterable, Codable, Sendable {
    case success, noSpeech, unreadableAudio, modelUnavailable, analysisFailed
    case historySaveFailed, cancelled, interrupted
}

nonisolated enum DiagnosticDuration: Int, CaseIterable, Codable, Sendable {
    case under5, from5To10, from10To20, from20To60, atLeast60, unavailable

    init(seconds: Double?) {
        guard let seconds, seconds.isFinite, seconds > 0 else { self = .unavailable; return }
        switch seconds {
        case ..<5: self = .under5
        case ..<10: self = .from5To10
        case ..<20: self = .from10To20
        case ..<60: self = .from20To60
        default: self = .atLeast60
        }
    }
}

nonisolated enum DiagnosticSpeechRatio: Int, CaseIterable, Codable, Sendable {
    case underQuarter, quarterToHalf, halfToThreeQuarters, atLeastThreeQuarters, unavailable

    init(speechSeconds: Double?, inputSeconds: Double?) {
        guard let speechSeconds, let inputSeconds,
              speechSeconds.isFinite, inputSeconds.isFinite,
              inputSeconds > 0, speechSeconds >= 0, speechSeconds <= inputSeconds else {
            self = .unavailable
            return
        }
        switch speechSeconds / inputSeconds {
        case ..<0.25: self = .underQuarter
        case ..<0.5: self = .quarterToHalf
        case ..<0.75: self = .halfToThreeQuarters
        default: self = .atLeastThreeQuarters
        }
    }
}

nonisolated enum DiagnosticLatency: Int, CaseIterable, Codable, Sendable {
    case under1, from1To3, from3To10, from10To30, atLeast30, unavailable

    init(seconds: Double?) {
        guard let seconds, seconds.isFinite, seconds >= 0 else { self = .unavailable; return }
        switch seconds {
        case ..<1: self = .under1
        case ..<3: self = .from1To3
        case ..<10: self = .from3To10
        case ..<30: self = .from10To30
        default: self = .atLeast30
        }
    }
}

nonisolated enum DiagnosticQuality: Int, CaseIterable, Codable, Sendable {
    case lowLevel, lowSeparation, sufficientSeparation, unavailable

    /// A VAD-dependent level proxy, not SNR, clipping detection, or a voice score.
    init(speechDBFS: Double?, backgroundDBFS: Double?) {
        guard let speechDBFS, speechDBFS.isFinite, (-120...0).contains(speechDBFS) else {
            self = .unavailable
            return
        }
        if speechDBFS < -45 { self = .lowLevel; return }
        guard let backgroundDBFS, backgroundDBFS.isFinite, (-120...0).contains(backgroundDBFS) else {
            self = .unavailable
            return
        }
        self = speechDBFS - backgroundDBFS < 10 ? .lowSeparation : .sufficientSeparation
    }
}

nonisolated struct DiagnosticObservation: Sendable {
    let duration: DiagnosticDuration
    let speechRatio: DiagnosticSpeechRatio
    let quality: DiagnosticQuality
    let latency: DiagnosticLatency

    init(inputSeconds: Double? = nil, speechSeconds: Double? = nil,
         quality: DiagnosticQuality = .unavailable, latencySeconds: Double? = nil) {
        duration = DiagnosticDuration(seconds: inputSeconds)
        speechRatio = DiagnosticSpeechRatio(speechSeconds: speechSeconds, inputSeconds: inputSeconds)
        self.quality = quality
        latency = DiagnosticLatency(seconds: latencySeconds)
    }
}

nonisolated struct DiagnosticSummary: Codable, Equatable, Sendable {
    private(set) var attempts = 0
    private(set) var outcomes = Array(repeating: 0, count: DiagnosticOutcome.allCases.count)
    private(set) var durations = Array(repeating: 0, count: DiagnosticDuration.allCases.count)
    private(set) var speechRatios = Array(repeating: 0, count: DiagnosticSpeechRatio.allCases.count)
    private(set) var qualities = Array(repeating: 0, count: DiagnosticQuality.allCases.count)
    private(set) var latencies = Array(repeating: 0, count: DiagnosticLatency.allCases.count)

    var completed: Int { outcomes.reduce(0, +) }
    var pending: Int { attempts - completed }

    mutating func begin() { attempts += 1 }

    mutating func finish(_ outcome: DiagnosticOutcome, observation: DiagnosticObservation) {
        outcomes[outcome.rawValue] += 1
        durations[observation.duration.rawValue] += 1
        speechRatios[observation.speechRatio.rawValue] += 1
        qualities[observation.quality.rawValue] += 1
        latencies[observation.latency.rawValue] += 1
    }

    var isValid: Bool {
        let arrays = [(outcomes, DiagnosticOutcome.allCases.count),
                      (durations, DiagnosticDuration.allCases.count),
                      (speechRatios, DiagnosticSpeechRatio.allCases.count),
                      (qualities, DiagnosticQuality.allCases.count),
                      (latencies, DiagnosticLatency.allCases.count)]
        guard (0...LocalDiagnosticState.attemptLimit).contains(attempts),
              arrays.allSatisfy({ values, size in
                  values.count == size && values.allSatisfy { (0...attempts).contains($0) }
              }) else { return false }
        // Validate before summing untrusted decoded integers.
        return completed <= attempts && pending <= 1
            && [durations, speechRatios, qualities, latencies].allSatisfy { $0.reduce(0, +) == completed }
    }
}

nonisolated struct DiagnosticConfiguration: Codable, Equatable, Sendable {
    let appVersion: String
    let appBuild: String
    let manifestSHA256: String
    let measurementRevision: Int

    var isValid: Bool {
        !appVersion.isEmpty && appVersion.utf8.count <= 80
            && !appBuild.isEmpty && appBuild.utf8.count <= 80
            && manifestSHA256.count == 64
            && manifestSHA256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && measurementRevision == 1
    }
}

/// The only date is a local retention/quota boundary, never a recording time.
/// Clearing or withdrawing deletes the summary but preserves this period's quota.
nonisolated struct LocalDiagnosticState: Codable, Sendable {
    static let attemptLimit = 5
    static let retentionSeconds: TimeInterval = 7 * 24 * 60 * 60
    private(set) var schemaVersion = 1
    private(set) var enabled = false
    private(set) var periodStartedAt: Date
    private(set) var usedAttempts = 0
    private(set) var summary = DiagnosticSummary()
    private(set) var configuration: DiagnosticConfiguration

    init(now: Date, configuration: DiagnosticConfiguration) {
        periodStartedAt = now
        self.configuration = configuration
    }

    var isValid: Bool {
        schemaVersion == 1 && periodStartedAt.timeIntervalSince1970.isFinite
            && configuration.isValid && (0...Self.attemptLimit).contains(usedAttempts)
            && summary.isValid && summary.attempts <= usedAttempts
            && (enabled || summary.attempts == 0)
    }

    /// Returns true when in-flight tokens must be invalidated.
    mutating func refresh(now: Date, configuration: DiagnosticConfiguration) -> Bool {
        let expired = now.timeIntervalSince(periodStartedAt) >= Self.retentionSeconds
        let clockMovedBack = now < periodStartedAt
        let changed = self.configuration != configuration
        guard expired || clockMovedBack || changed else { return false }
        summary = DiagnosticSummary()
        self.configuration = configuration
        if expired {
            periodStartedAt = now
            usedAttempts = 0
        }
        // Clock rollback/config changes must not silently replenish the quota.
        return true
    }

    mutating func setEnabled(_ value: Bool) {
        enabled = value
        if !value { clearSummary() }
    }

    mutating func clearSummary() { summary = DiagnosticSummary() }

    mutating func begin() -> Bool {
        guard enabled, usedAttempts < Self.attemptLimit, summary.pending == 0 else { return false }
        usedAttempts += 1
        summary.begin()
        return true
    }

    mutating func finish(_ outcome: DiagnosticOutcome, observation: DiagnosticObservation) {
        guard enabled, summary.pending == 1 else { return }
        summary.finish(outcome, observation: observation)
    }

    mutating func recoverInterruptedAttempt() {
        if enabled, summary.pending == 1 {
            summary.finish(.interrupted, observation: DiagnosticObservation())
        }
    }
}
