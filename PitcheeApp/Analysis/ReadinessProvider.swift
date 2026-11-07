import Foundation
import SwiftData

/// Readiness-page entry point. The daily result and next-day marker are written
/// together, so reopening the page/app cannot consume yesterday's marker twice.
@MainActor
final class ReadinessProvider {
    private let history: ReadinessHistory
    private let defaults: UserDefaults
    private var cached: DailyCache?
    private(set) var evaluationCount = 0
    private static let cacheKey = "readiness.daily.cache.v1"

    init(modelContext: ModelContext, defaults: UserDefaults = .standard) {
        history = ReadinessHistory(modelContext: modelContext)
        self.defaults = defaults
    }

    func result(at now: Date = .now) throws -> ReadinessResult {
        let day = ReadinessPracticeDay.start(containing: now)
        if let cached, cached.day == day { return cached.result.value }
        let persisted = defaults.data(forKey: Self.cacheKey)
            .flatMap { try? JSONDecoder().decode(DailyCache.self, from: $0) }
        if let persisted, persisted.day == day, persisted.rulesVersion == ReadinessScoring.rulesVersion {
            cached = persisted
            return persisted.result.value
        }

        var input = try history.input(at: now)
        input.heavyYesterday = persisted?.heavyDay == day
        let result = ReadinessScoring.evaluate(input)
        // No storage mutation until fetching and evaluation have succeeded.
        // Stale/consumed markers disappear; a new heavy result schedules only
        // tomorrow. Cache hits above never read history or reschedule the flag.
        let next = DailyCache(
            day: day, result: StoredResult(result),
            heavyDay: result.markHeavyYesterday ? ReadinessPracticeDay.adding(days: 1, to: day) : nil,
            rulesVersion: ReadinessScoring.rulesVersion
        )
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Self.cacheKey)
        cached = next
        evaluationCount += 1
        return result
    }
}

// Storage DTOs keep serialization out of the delivered pure engine. These are
// derived cache data only; RecordingAssessment remains the source of history.
nonisolated private struct DailyCache: Codable {
    let day: Date
    let result: StoredResult
    let heavyDay: Date?
    let rulesVersion: String
}

nonisolated private struct StoredResult: Codable {
    let score: Double
    let level: String
    let reason: String?
    let contributions: [StoredContribution]
    let formulaVersion: String
    let markHeavyYesterday: Bool
    let isColdStart: Bool

    init(_ result: ReadinessResult) {
        score = result.score
        level = result.level
        reason = result.reason?.rawValue
        contributions = result.contributions.map(StoredContribution.init)
        formulaVersion = result.formulaVersion
        markHeavyYesterday = result.markHeavyYesterday
        isColdStart = result.isColdStart
    }

    var value: ReadinessResult {
        ReadinessResult(score: score, level: level, reason: reason.flatMap(ReadinessReason.init(rawValue:)),
                        contributions: contributions.map(\.value), formulaVersion: formulaVersion,
                        markHeavyYesterday: markHeavyYesterday, isColdStart: isColdStart)
    }
}

nonisolated private struct StoredContribution: Codable {
    let factorId: String
    let contribution: Double
    let formulaVersion: String
    let isTriggered: Bool
    let direction: Int?

    init(_ factor: FactorContribution) {
        factorId = factor.factorId
        contribution = factor.contribution
        formulaVersion = factor.formulaVersion
        isTriggered = factor.isTriggered
        direction = factor.direction
    }

    var value: FactorContribution {
        FactorContribution(factorId: factorId, contribution: contribution, formulaVersion: formulaVersion,
                           isTriggered: isTriggered, direction: direction)
    }
}
