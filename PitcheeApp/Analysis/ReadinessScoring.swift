// Readiness v0.8 (2026-10-10). Business rules only; no Core, storage, clock or UI.
// All G-grade numbers are UNCALIBRATED (未校准), including B2 -10 (decision #29, 2026-10-10).

/// The caller supplies a quality-gated, 30-practiceDay baseline (at least five
/// samples, sample SD with n-1). Only HNR has a specified SD floor: 0.5 dB.
/// For other features, an unreliable SD must be represented by a nil baseline;
/// this engine neither invents a floor nor estimates a baseline from recent data.
nonisolated struct BaselineStats: Sendable, Equatable {
    let mean: Double
    let stdev: Double
}

nonisolated struct ScoredAssessment: Sendable, Equatable {
    let finalScore: Double
    let canCompare: Bool
}

/// Values are snapshots prepared by the caller. Counts are practiceDay-deduped.
/// All recent arrays are newest first. In the spec, [n-2,n-1,n] denotes time
/// chronology, despite being described as descending; means are order invariant.
/// C arrays must retain exactly three aligned slots: quality failures, missing
/// features and legacy voiceQuality == nil become nil, never removed/refilled.
nonisolated struct ReadinessInput: Sendable, Equatable {
    var practiceDaysLast7: Int = 0
    var gapDays: Int = 0
    var isHabitualUser: Bool = false
    var speechSecondsToday: Double? = nil
    /// Caller passes nil for fewer than five qualified P90 samples.
    var speechSecondsP90: Double? = nil
    var heavyYesterday: Bool = false
    var consecutiveAbsenceDays: Int = 0
    var validAssessments: Int = 0
    var recentFinalScores: [ScoredAssessment] = []
    /// Caller-prepared 30-day finalScore baseline for B3; nil skips the factor.
    var finalScoreBaseline: BaselineStats? = nil
    var hnrRecent3: [Double?] = []
    var hnrBaseline: BaselineStats? = nil
    var natRecent3: [Double?] = []
    var natBaseline: BaselineStats? = nil
    var pvRecent3: [Double?] = []
    var pvBaseline: BaselineStats? = nil
    var vRecent3: [Double?] = []
    var vBaselineMean: Double? = nil
}

nonisolated enum ReadinessReason: String, Sendable {
    case voiceTired, welcomeBack, heavyYesterday
}

nonisolated struct FactorContribution: Sendable, Equatable {
    let factorId: String
    let contribution: Double
    let formulaVersion: String
    /// A level-only decision or already-satisfied cap can fire with delta zero.
    /// This distinguishes that evidence from missing or non-triggering factors.
    let isTriggered: Bool
    /// C1 only: +1 above or -1 below baseline, without a good/bad interpretation.
    let direction: Int?
}

nonisolated struct ReadinessResult: Sendable, Equatable {
    let score: Double
    /// "S" / "A" / "B" / "C". Deliberately not a level enum.
    let level: String
    let reason: ReadinessReason?
    let contributions: [FactorContribution]
    let formulaVersion: String
    /// Caller persists this for the next practiceDay, never for today's cap.
    let markHeavyYesterday: Bool
    /// Cold start is a placeholder, not a scored assessment. Caller owns copy
    /// and the guidedFirstRecording action; no UI strings/actions in the engine.
    let isColdStart: Bool
}

/// Numerical sensitivity catalog. Defaults reproduce v0.8 without calibration.
/// In addition to explicitly G-grade values, the harness scans the global
/// score/grade/cold-start/return thresholds conservatively. The aligned C window
/// and B2's three-point pattern are structural rules, not tunable parameters.
/// Caller-owned 30-day selection, >=12 habitual days, >=5 baseline/P90 samples,
/// w>=10 quality gate and HNR's 0.5 dB floor are not engine parameters.
nonisolated enum ReadinessParameter: String, CaseIterable, Sendable {
    case initialScore, coldStartAssessments
    case a1MaximumDays, a1PointsPerDay
    case a2ExemptGapDays, a2MaximumGapDays, a2PointsPerDay
    case a4HeavyRatio, a4NextDayCap
    case b1WindowSize, b1MinimumSamples, b1SlopeThreshold, b1Reward
    case b2DropThreshold, b2Penalty
    case b3ZThreshold, b3Penalty
    case c1AbsoluteZThreshold, c1Penalty
    case c2ZThreshold, c2Penalty
    case c3ZThreshold, c3Penalty
    case c4DropThreshold, c4Penalty
    case dualAnomalyCap, returnAbsenceDays
    case levelSMinimum, levelAMinimum, levelBMinimum

    var calibrationNote: String {
        switch self {
        case .initialScore, .coldStartAssessments, .returnAbsenceDays,
             .levelSMinimum, .levelAMinimum, .levelBMinimum:
            "未校准；规格未单列置信度，额外扫描"
        case .b2Penalty:
            "G / 未校准；误伤减害，#29 已于 2026-10-10 裁决"
        case .b2DropThreshold:
            "G / 未校准；误伤风险最高"
        default:
            "G / 未校准"
        }
    }

    var currentValue: Double {
        switch self {
        case .initialScore: 70
        case .coldStartAssessments: 3
        case .a1MaximumDays: 5
        case .a1PointsPerDay: 4
        case .a2ExemptGapDays: 3
        case .a2MaximumGapDays: 5
        case .a2PointsPerDay: -5
        case .a4HeavyRatio: 2
        case .a4NextDayCap: 64
        case .b1WindowSize: 5
        case .b1MinimumSamples: 3
        case .b1SlopeThreshold: 1
        case .b1Reward: 5
        case .b2DropThreshold: 2
        case .b2Penalty: -10
        case .b3ZThreshold: -1.5
        case .b3Penalty: -5
        case .c1AbsoluteZThreshold: 1
        case .c1Penalty: -10
        case .c2ZThreshold: -1.5
        case .c2Penalty: -6
        case .c3ZThreshold: 1.5
        case .c3Penalty: -4
        case .c4DropThreshold: 0.20
        case .c4Penalty: -2
        case .dualAnomalyCap: 59
        case .returnAbsenceDays: 14
        case .levelSMinimum: 85
        case .levelAMinimum: 65
        case .levelBMinimum: 40
        }
    }
}

/// Immutable, explicit overrides exist for synthetic experiments only. No
/// global configuration or mutable defaults: production calls use .current.
nonisolated struct ReadinessParameters: Sendable {
    static let current = ReadinessParameters()
    private let overrides: [ReadinessParameter: Double]

    init(overrides: [ReadinessParameter: Double] = [:]) {
        precondition(overrides.values.allSatisfy(\.isFinite), "Parameters must be finite")
        self.overrides = overrides
    }

    func value(_ parameter: ReadinessParameter) -> Double {
        overrides[parameter] ?? parameter.currentValue
    }
}

nonisolated enum ReadinessScoring: Sendable {
    static let formulaVersion = "c1-bidirectional-v1"
    static let dualAnomalyVersion = "dual-anomaly-v1"
    static let rulesVersion = "readiness-v0.8-r2-uncalibrated"
    private static let factorIds = ["A1", "A2", "A4", "B1", "B2", "B3", "C1", "C2", "C3", "C4"]

    static func evaluate(
        _ input: ReadinessInput,
        parameters p: ReadinessParameters = .current
    ) -> ReadinessResult {
        var score = p.value(.initialScore)
        // Keep absent/skipped factors visible as zero, without making them fire.
        var evidence = factorIds.map { factor($0) }
        if Double(input.validAssessments) < p.value(.coldStartAssessments) {
            evidence.append(factor("coldStart", triggered: true))
            return result(score, level: "A", evidence: evidence, isColdStart: true)
        }

        let a1 = min(Double(max(0, input.practiceDaysLast7)), p.value(.a1MaximumDays))
            * p.value(.a1PointsPerDay)
        score += a1
        evidence[0] = factor("A1", delta: a1, triggered: a1 != 0)

        let exempt = input.isHabitualUser && Double(input.gapDays) <= p.value(.a2ExemptGapDays)
        let a2 = exempt ? 0 : min(Double(max(0, input.gapDays)), p.value(.a2MaximumGapDays))
            * p.value(.a2PointsPerDay)
        score += a2
        evidence[1] = factor("A2", delta: a2, triggered: a2 != 0)
        if exempt { evidence.append(factor("decision.5", triggered: true)) }

        let tomorrow = markHeavyYesterday(for: input, parameters: p)
        evidence[2] = factor("A4", triggered: tomorrow || input.heavyYesterday)

        // B1: select the prefix before quality checks. Never skip an invalid
        // assessment to pull an older one into the recent window.
        let b1Window = p.value(.b1WindowSize).rounded()
        let windowCount = Int(max(0, min(Double(input.recentFinalScores.count), b1Window)))
        let recent = Array(input.recentFinalScores.prefix(windowCount))
        if Double(recent.count) >= p.value(.b1MinimumSamples),
           let slope = chronologicalSlope(newestFirst: recent), slope > p.value(.b1SlopeThreshold) {
            score += p.value(.b1Reward)
            evidence[3] = factor("B1", delta: p.value(.b1Reward), triggered: true)
        }

        let last3 = Array(input.recentFinalScores.prefix(3))
        if last3.count == 3, last3.allSatisfy({ $0.canCompare && $0.finalScore.isFinite }) {
            let olderDrop = last3[2].finalScore - last3[1].finalScore
            let latestDrop = last3[1].finalScore - last3[0].finalScore
            if olderDrop.isFinite, latestDrop.isFinite,
               olderDrop > p.value(.b2DropThreshold), latestDrop > p.value(.b2DropThreshold) {
                // G: highest known false-positive risk, decision #29. Do not tune.
                score += p.value(.b2Penalty)
                evidence[4] = factor("B2", delta: p.value(.b2Penalty), triggered: true)
            }
        }

        if let latest = input.recentFinalScores.first, latest.canCompare,
           let z = zScore(latest.finalScore, baseline: input.finalScoreBaseline),
           z < p.value(.b3ZThreshold) {
            score += p.value(.b3Penalty)
            evidence[5] = factor("B3", delta: p.value(.b3Penalty), triggered: true)
        }

        let hnrZ = mean3(input.hnrRecent3).flatMap { zScore($0, baseline: input.hnrBaseline) }
        let natZ = mean3(input.natRecent3).flatMap { zScore($0, baseline: input.natBaseline) }
        let pvZ = mean3(input.pvRecent3).flatMap { zScore($0, baseline: input.pvBaseline) }
        let c1 = hnrZ.map { abs($0) > p.value(.c1AbsoluteZThreshold) } ?? false
        let c2 = natZ.map { $0 < p.value(.c2ZThreshold) } ?? false
        let c3 = pvZ.map { $0 > p.value(.c3ZThreshold) } ?? false

        if c1, let hnrZ {
            score += p.value(.c1Penalty)
            evidence[6] = factor("C1", delta: p.value(.c1Penalty), triggered: true,
                                 direction: hnrZ > 0 ? 1 : -1)
        }
        if c2 {
            score += p.value(.c2Penalty)
            evidence[7] = factor("C2", delta: p.value(.c2Penalty), triggered: true)
        }
        if c3 {
            score += p.value(.c3Penalty)
            evidence[8] = factor("C3", delta: p.value(.c3Penalty), triggered: true)
        }
        if let mean = mean3(input.vRecent3), let baseline = input.vBaselineMean,
           baseline.isFinite, baseline > 0 {
            let drop = 1 - mean / baseline
            if drop.isFinite, drop > p.value(.c4DropThreshold) {
                score += p.value(.c4Penalty)
                evidence[9] = factor("C4", delta: p.value(.c4Penalty), triggered: true)
            }
        }

        // Only the highest-priority applicable decision supplies the override
        // and its reason: #7 > #4 > #6. Caps never add points.
        if Double(input.consecutiveAbsenceDays) >= p.value(.returnAbsenceDays) {
            evidence.append(factor("decision.7", triggered: true))
            return result(score, level: "C", reason: .welcomeBack, evidence: evidence,
                          markHeavyYesterday: tomorrow)
        }
        if c1 && (c2 || c3) {
            let capped = min(score, p.value(.dualAnomalyCap))
            evidence.append(factor("decision.4", delta: capped - score, triggered: true))
            return result(capped, level: "B", reason: .voiceTired, evidence: evidence,
                          markHeavyYesterday: tomorrow)
        }
        if input.heavyYesterday {
            let capped = min(score, p.value(.a4NextDayCap))
            evidence.append(factor("decision.6", delta: capped - score, triggered: true))
            return result(capped, level: level(for: capped, parameters: p), reason: .heavyYesterday,
                          evidence: evidence, markHeavyYesterday: tomorrow)
        }
        return result(score, level: level(for: score, parameters: p), evidence: evidence,
                      markHeavyYesterday: tomorrow)
    }

    /// Pure A4 predicate, available separately when a caller needs the flag even
    /// on days where evaluation short-circuits for cold start.
    static func markHeavyYesterday(
        for input: ReadinessInput,
        parameters p: ReadinessParameters = .current
    ) -> Bool {
        guard let today = input.speechSecondsToday, let p90 = input.speechSecondsP90,
              today.isFinite, p90.isFinite, today >= 0, p90 >= 0 else { return false }
        return today > p.value(.a4HeavyRatio) * p90
    }

    static func level(for score: Double, parameters p: ReadinessParameters = .current) -> String {
        if score >= p.value(.levelSMinimum) { return "S" }
        if score >= p.value(.levelAMinimum) { return "A" }
        if score >= p.value(.levelBMinimum) { return "B" }
        return "C"
    }

    private static func mean3(_ samples: [Double?]) -> Double? {
        guard samples.count == 3 else { return nil }
        var mean = 0.0
        for sample in samples {
            guard let sample, sample.isFinite else { return nil }
            mean += sample / 3
        }
        return mean.isFinite ? mean : nil
    }

    private static func zScore(_ value: Double, baseline: BaselineStats?) -> Double? {
        guard value.isFinite, let baseline, baseline.mean.isFinite,
              baseline.stdev.isFinite, baseline.stdev > 0 else { return nil }
        let z = (value - baseline.mean) / baseline.stdev
        return z.isFinite ? z : nil
    }

    private static func chronologicalSlope(newestFirst samples: [ScoredAssessment]) -> Double? {
        guard samples.count >= 2, samples.allSatisfy({ $0.canCompare && $0.finalScore.isFinite })
        else { return nil }
        let count = Double(samples.count)
        let meanX = (count - 1) / 2
        let meanY = samples.reduce(0.0) { $0 + $1.finalScore / count }
        var numerator = 0.0
        var denominator = 0.0
        for (index, assessment) in samples.reversed().enumerated() {
            let x = Double(index) - meanX
            numerator += x * (assessment.finalScore - meanY)
            denominator += x * x
        }
        let slope = numerator / denominator
        return slope.isFinite ? slope : nil
    }

    private static func factor(
        _ id: String, delta: Double = 0, triggered: Bool = false, direction: Int? = nil
    ) -> FactorContribution {
        let version = id == "C1" ? formulaVersion : id == "decision.4" ? dualAnomalyVersion : rulesVersion
        return .init(factorId: id, contribution: delta, formulaVersion: version,
                     isTriggered: triggered, direction: direction)
    }

    private static func result(
        _ score: Double, level: String, reason: ReadinessReason? = nil,
        evidence: [FactorContribution], markHeavyYesterday: Bool = false, isColdStart: Bool = false
    ) -> ReadinessResult {
        .init(score: score, level: level, reason: reason, contributions: evidence,
              formulaVersion: formulaVersion, markHeavyYesterday: markHeavyYesterday, isColdStart: isColdStart)
    }
}
