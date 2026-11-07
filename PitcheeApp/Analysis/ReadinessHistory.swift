import Foundation
import SwiftData

/// Beijing 04:00, independent of the device calendar, locale and time zone.
nonisolated enum ReadinessPracticeDay {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        return calendar
    }

    static func start(containing date: Date) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-4 * 3_600))
            .addingTimeInterval(4 * 3_600)
    }

    static func adding(days: Int, to day: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: day)!
    }

    static func distance(from earlier: Date, to later: Date) -> Int {
        calendar.dateComponents([.day], from: earlier, to: later).day ?? 0
    }
}

/// Reads the same history as Insights, without its all-history detail decoding.
/// SwiftData models and their context never leave the main actor.
@MainActor
struct ReadinessHistory {
    let modelContext: ModelContext

    func input(at now: Date) throws -> ReadinessInput {
        let day = ReadinessPracticeDay.start(containing: now)
        let start = ReadinessPracticeDay.adding(days: -29, to: day)
        let weekStart = ReadinessPracticeDay.adding(days: -6, to: day)
        let decoder = JSONDecoder()

        var windowFetch = FetchDescriptor<RecordingAssessment>(
            predicate: #Predicate { $0.recordedAt >= start && $0.recordedAt <= now },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        windowFetch.propertiesToFetch = [\.id, \.recordedAt, \.finalScore, \.naturalnessScore,
                                         \.speechSeconds, \.qualityPayload, \.resultPayload]
        let window = try modelContext.fetch(windowFetch).map { Record($0, decoder: decoder) }

        // These are recording slots, not daily representatives. Never discard
        // an invalid/missing latest slot to pull an older observation forward.
        var recentFetch = FetchDescriptor<RecordingAssessment>(
            predicate: #Predicate { $0.recordedAt <= now },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        recentFetch.fetchLimit = 5
        recentFetch.propertiesToFetch = windowFetch.propertiesToFetch
        let byID = Dictionary(uniqueKeysWithValues: window.map { ($0.id, $0) })
        let recent = try modelContext.fetch(recentFetch).map { record in
            byID[record.id] ?? Record(record, decoder: decoder)
        }

        // Cold-start eligibility is a lifetime *recording* count. Only old
        // scalar/quality columns are visited in bounded batches, never their
        // resultPayload or window/segment arrays. No second history store.
        var validCount = window.filter(\.isValidAssessment).count
        var olderFetch = FetchDescriptor<RecordingAssessment>(
            predicate: #Predicate { $0.recordedAt < start },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        olderFetch.propertiesToFetch = [\.finalScore, \.qualityPayload]
        try modelContext.enumerate(olderFetch, batchSize: 128) { record in
            if record.finalScore.isFinite, record.quality?.canCompare == true { validCount += 1 }
        }

        let daily = Dictionary(grouping: window) { ReadinessPracticeDay.start(containing: $0.date) }
        let lastDay = recent.first.map { ReadinessPracticeDay.start(containing: $0.date) }
        let gap = lastDay.map { max(0, ReadinessPracticeDay.distance(from: $0, to: day)) } ?? 0
        var input = ReadinessInput()
        input.practiceDaysLast7 = daily.keys.filter { $0 >= weekStart }.count
        input.gapDays = gap
        input.isHabitualUser = daily.count >= 12
        input.consecutiveAbsenceDays = gap
        input.validAssessments = validCount

        // P90 uses qualified practice samples. Today's measured speech is
        // actual load, including recordings that failed comparison quality.
        // Missing-value days remain absent, never zero-filled.
        let speechByDay = daily.compactMapValues { records -> Double? in
            Self.totalSpeech(records.filter(\.canCompare))
        }
        input.speechSecondsToday = daily[day].flatMap(Self.totalSpeech)
        input.speechSecondsP90 = Self.percentile90(Array(speechByDay.values))
        input.recentFinalScores = recent.map {
            ScoredAssessment(finalScore: $0.finalScore, canCompare: $0.canCompare)
        }

        // Match DailyPracticeSummary's median convention, with independent
        // quality/missing gates per feature before practiceDay deduplication.
        func dailyMedians(_ value: (Record) -> Double?) -> [Double] {
            daily.values.compactMap { Self.median($0.compactMap(value)) }
        }
        input.finalScoreBaseline = Self.baseline(dailyMedians { $0.isValidAssessment ? $0.finalScore : nil })
        input.hnrBaseline = Self.baseline(dailyMedians { $0.hnr }, floor: 0.5)
        input.natBaseline = Self.baseline(dailyMedians { $0.naturalness })
        input.pvBaseline = Self.baseline(dailyMedians { $0.pitchVariation })
        // The spec asks for a reliable v baseline even though the engine takes
        // only its mean: zero/nonfinite sample SD must still exclude C4.
        input.vBaselineMean = Self.baseline(dailyMedians { $0.voicedRatio })?.mean

        func slots(_ value: (Record) -> Double?) -> [Double?] {
            let values = recent.prefix(3).map(value)
            return values + Array(repeating: nil, count: 3 - values.count)
        }
        input.hnrRecent3 = slots { $0.hnr }
        input.natRecent3 = slots { $0.naturalness }
        input.pvRecent3 = slots { $0.pitchVariation }
        input.vRecent3 = slots { $0.voicedRatio }
        return input
    }

    private static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? sorted[middle - 1] / 2 + sorted[middle] / 2 : sorted[middle]
    }

    private static func baseline(_ values: [Double], floor: Double? = nil) -> BaselineStats? {
        guard values.count >= 5, values.allSatisfy(\.isFinite) else { return nil }
        // Welford retains an exact zero for constant samples; summing x/n
        // first can manufacture a tiny positive SD through rounding.
        var mean = values[0]
        var sumSquares = 0.0
        for (index, value) in values.enumerated().dropFirst() {
            let delta = value - mean
            mean += delta / Double(index + 1)
            sumSquares += delta * (value - mean)
        }
        let deviation = sqrt(sumSquares / Double(values.count - 1))
        guard mean.isFinite, deviation.isFinite else { return nil }
        let stdev = floor.map { max($0, deviation) } ?? deviation
        guard stdev > 0 else { return nil }
        return BaselineStats(mean: mean, stdev: stdev)
    }

    private static func totalSpeech(_ records: [Record]) -> Double? {
        let values = records.compactMap(\.speech)
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total.isFinite ? total : nil
    }

    private static func percentile90(_ values: [Double]) -> Double? {
        guard values.count >= 5 else { return nil }
        let sorted = values.sorted()
        let position = Double(sorted.count - 1) * 0.9
        let lower = Int(position)
        let fraction = position - Double(lower)
        let result = sorted[lower] * (1 - fraction) + sorted[min(lower + 1, sorted.count - 1)] * fraction
        return result.isFinite ? result : nil
    }

    private struct Record {
        let id: UUID
        let date: Date
        let finalScore: Double
        let canCompare: Bool
        let speech: Double?
        let hnr: Double?
        let naturalness: Double?
        let pitchVariation: Double?
        let voicedRatio: Double?
        var isValidAssessment: Bool { canCompare && finalScore.isFinite }

        init(_ record: RecordingAssessment, decoder: JSONDecoder) {
            id = record.id
            date = record.recordedAt
            finalScore = record.finalScore
            canCompare = record.quality?.canCompare == true
            speech = Self.nonnegative(record.speechSeconds)
            naturalness = canCompare ? Self.finite(record.naturalnessScore) : nil
            // Avoid even projecting acoustic payloads for failed quality gates.
            let features = canCompare ? try? decoder.decode(AcousticSummary.self, from: record.resultPayload) : nil
            hnr = (features?.voiceQuality?.hnrWindowCount ?? 0) >= 10
                ? Self.finite(features?.voiceQuality?.hnrDb) : nil
            pitchVariation = Self.nonnegative(features?.f0?.standardDeviationHz)
            if let voiced = features?.f0?.voicedFrameCount, let total = features?.f0?.totalFrames,
               total > 0, voiced >= 0, voiced <= total {
                voicedRatio = Double(voiced) / Double(total)
            } else {
                voicedRatio = nil
            }
        }

        private static func finite(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite ? $0 : nil }
        }

        private static func nonnegative(_ value: Double?) -> Double? {
            finite(value).flatMap { $0 >= 0 ? $0 : nil }
        }
    }
}

/// The persisted payload uses camelCase. Omitted keys and malformed individual
/// features stay missing without dropping other valid features or reading arrays.
nonisolated private struct AcousticSummary: Decodable {
    let voiceQuality: HNR?
    let f0: Pitch?
    private enum CodingKeys: String, CodingKey { case voiceQuality, f0 }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        voiceQuality = try? values.decode(HNR.self, forKey: .voiceQuality)
        f0 = try? values.decode(Pitch.self, forKey: .f0)
    }

    struct HNR: Decodable {
        let hnrDb: Double?
        let hnrWindowCount: Int?
        private enum CodingKeys: String, CodingKey { case hnrDb, hnrWindowCount }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            hnrDb = try? values.decode(Double.self, forKey: .hnrDb)
            hnrWindowCount = try? values.decode(Int.self, forKey: .hnrWindowCount)
        }
    }

    struct Pitch: Decodable {
        let standardDeviationHz: Double?
        let voicedFrameCount: Int?
        // Current persisted schema has no denominator. Decode it only if
        // explicitly present; never infer frames from seconds or window counts.
        let totalFrames: Int?
        private enum CodingKeys: String, CodingKey { case standardDeviationHz, voicedFrameCount, totalFrames }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            standardDeviationHz = try? values.decode(Double.self, forKey: .standardDeviationHz)
            voicedFrameCount = try? values.decode(Int.self, forKey: .voicedFrameCount)
            totalFrames = try? values.decode(Int.self, forKey: .totalFrames)
        }
    }
}
