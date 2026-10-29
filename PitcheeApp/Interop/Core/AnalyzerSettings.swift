//
//  AnalyzerSettings.swift
//  Pitchee
//
//  User-tunable Core thresholds and display preferences.
//

import Foundation

nonisolated enum AnalyzerSettingsKey {
    static let minF0Hz = "analysis.f0.minHz"
    static let maxF0Hz = "analysis.f0.maxHz"
    static let minConfidence = "analysis.f0.minConfidence"
    static let threads = "analysis.f0.threads"
    static let threadsDefaultMigration = "analysis.f0.threadsDefaultMigration"
    static let pitchChartStyle = "monitor.pitch.chartStyle"
    static let pitchGapMilliseconds = "monitor.pitch.gapMilliseconds"
    static let f0SampleRate = "monitor.pitch.sampleRate"
}

enum PitchChartStyle: String, CaseIterable, Identifiable, Sendable {
    case curve
    case dots

    var id: Self { self }
}

/// The values handed to `pitchee_analyzer_create`. Stored values are clamped
/// here so a stale or manually edited preference can never create an invalid
/// analyzer.
nonisolated struct AnalyzerSettings: Equatable, Sendable {
    static let defaultMinF0Hz = 75.0
    static let defaultMaxF0Hz = 600.0
    static let defaultMinConfidence = 0.9
    static let maximumThreads = max(1, ProcessInfo.processInfo.activeProcessorCount)
    static let defaultThreads = maximumThreads
    private static let previousDefaultThreads = 2
    static let minF0HzRange = 50.0...980.0
    static let maxF0HzRange = 70.0...1_000.0
    static let confidenceRange = 0.3...0.99
    static let minimumF0GapHz = 20.0
    static let realtimeChartHeadroomLowHz = 30.0
    static let realtimeChartHeadroomHighHz = 50.0

    static let `default` = AnalyzerSettings(
        minF0Hz: defaultMinF0Hz,
        maxF0Hz: defaultMaxF0Hz,
        minConfidence: defaultMinConfidence,
        threads: defaultThreads
    )

    let minF0Hz: Double
    let maxF0Hz: Double
    let minConfidence: Double
    let threads: Int

    /// Preserve deliberate thread choices while moving installs that still use
    /// the previous default of two threads onto every available CPU core.
    static func migrateThreadDefaultIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: AnalyzerSettingsKey.threadsDefaultMigration) else { return }
        let storedThreads = defaults.object(forKey: AnalyzerSettingsKey.threads) as? Int
        if storedThreads == nil || storedThreads == previousDefaultThreads {
            defaults.set(defaultThreads, forKey: AnalyzerSettingsKey.threads)
        }
        defaults.set(true, forKey: AnalyzerSettingsKey.threadsDefaultMigration)
    }

    static var current: AnalyzerSettings {
        let defaults = UserDefaults.standard
        let minF0 = clamp(
            defaults.object(forKey: AnalyzerSettingsKey.minF0Hz) as? Double ?? defaultMinF0Hz,
            to: minF0HzRange
        )
        let storedMax = clamp(
            defaults.object(forKey: AnalyzerSettingsKey.maxF0Hz) as? Double ?? defaultMaxF0Hz,
            to: maxF0HzRange
        )
        let maxF0 = clamp(storedMax, to: (minF0 + minimumF0GapHz)...maxF0HzRange.upperBound)
        let confidence = clamp(
            defaults.object(forKey: AnalyzerSettingsKey.minConfidence) as? Double ?? defaultMinConfidence,
            to: confidenceRange
        )
        let storedThreads = defaults.object(forKey: AnalyzerSettingsKey.threads) as? Int ?? defaultThreads
        return AnalyzerSettings(
            minF0Hz: minF0,
            maxF0Hz: maxF0,
            minConfidence: confidence,
            threads: min(Self.maximumThreads, max(1, storedThreads))
        )
    }

    /// The realtime chart shows the configured detector range with enough
    /// headroom that values on either limit remain visibly inside the plot.
    static func realtimeChartRange(minF0Hz: Double, maxF0Hz: Double) -> ClosedRange<Double> {
        let lower = max(1, minF0Hz - realtimeChartHeadroomLowHz)
        let upper = max(lower + 1, maxF0Hz + realtimeChartHeadroomHighHz)
        return lower...upper
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
