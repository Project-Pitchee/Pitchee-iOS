//
//  MonitorTimeline.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import Foundation

nonisolated struct MonitorSpectrumFrame: Sendable {
    static let frequencyRange: ClosedRange<Double> = 40...8_000

    private(set) var elapsedTime: TimeInterval
    let magnitudesDB: [Float]
    let binWidthHz: Double
    let peak: (frequencyHz: Double, amplitudeDBFS: Float)?
    let isValid: Bool

    init(elapsedTime: TimeInterval, magnitudesDB: [Float], binWidthHz: Double) {
        self.elapsedTime = elapsedTime
        self.magnitudesDB = magnitudesDB
        self.binWidthHz = binWidthHz

        guard binWidthHz.isFinite, binWidthHz > 0, !magnitudesDB.isEmpty else {
            peak = nil
            isValid = false
            return
        }
        var valid = true
        var strongest: (frequencyHz: Double, amplitudeDBFS: Float)?
        for (index, magnitude) in magnitudesDB.enumerated() {
            guard magnitude.isFinite else { valid = false; continue }
            let frequency = Double(index) * binWidthHz
            if Self.frequencyRange.contains(frequency), magnitude > (strongest?.amplitudeDBFS ?? -95) {
                strongest = (frequency, magnitude)
            }
        }
        // Validate and find the peak once when the FFT result arrives. Chart,
        // gauge, and accessibility readouts can then share the same result.
        isValid = valid
        peak = valid ? strongest : nil
    }

    func offset(by seconds: TimeInterval) -> Self {
        var shifted = self
        shifted.elapsedTime += seconds
        return shifted
    }
}

/// The microphone's captured time is the clock for both charts and replay.
/// Pausing adds no time; callers offset resumed analysis by `duration`.
nonisolated struct MonitorTimeline: Sendable {
    static let sampleRate: Double = 16_000
    static let retainedSeconds: TimeInterval = 60

    private static let sampleCapacity = Int(sampleRate * retainedSeconds)

    private(set) var duration: TimeInterval = 0
    private(set) var pitchSamples: [LivePitchSample] = []
    private(set) var spectrumFrames: [MonitorSpectrumFrame] = []

    private var storage: [Float] = []
    private var firstStorageIndex = 0
    private var retainedSampleCount = 0
    private var totalSampleCount: Int64 = 0

    var availableRange: ClosedRange<TimeInterval> {
        let firstSample = totalSampleCount - Int64(retainedSampleCount)
        return (Double(firstSample) / Self.sampleRate)...duration
    }

    mutating func appendAudio(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        if storage.isEmpty {
            storage = [Float](repeating: 0, count: Self.sampleCapacity)
        }

        totalSampleCount += Int64(samples.count)
        duration = Double(totalSampleCount) / Self.sampleRate

        if samples.count >= Self.sampleCapacity {
            // A large batch may replace the entire ring, including its partial
            // first chunk. Only copy the part that can still be replayed.
            storage.replaceSubrange(storage.indices, with: samples.suffix(Self.sampleCapacity))
            firstStorageIndex = 0
            retainedSampleCount = Self.sampleCapacity
        } else {
            let discardedCount = max(0, retainedSampleCount + samples.count - Self.sampleCapacity)
            firstStorageIndex = (firstStorageIndex + discardedCount) % Self.sampleCapacity
            retainedSampleCount -= discardedCount

            let writeIndex = (firstStorageIndex + retainedSampleCount) % Self.sampleCapacity
            let firstCount = min(samples.count, Self.sampleCapacity - writeIndex)
            storage.replaceSubrange(writeIndex..<(writeIndex + firstCount), with: samples.prefix(firstCount))
            if firstCount < samples.count {
                storage.replaceSubrange(0..<(samples.count - firstCount), with: samples.dropFirst(firstCount))
            }
            retainedSampleCount += samples.count
        }
        trimAnalysis()
    }

    mutating func appendPitch(_ samples: [LivePitchSample]) {
        guard retainedSampleCount > 0 else { return }
        let range = availableRange
        for sample in samples where sample.elapsedTime.isFinite && range.contains(sample.elapsedTime) {
            // Invalid detector values are gaps, just like unvoiced frames. Do
            // not turn silence into 0 Hz or connect its neighboring pitches.
            let pitch = sample.pitchHz.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let normalized = LivePitchSample(elapsedTime: sample.elapsedTime, pitchHz: pitch)
            Self.insert(normalized, into: &pitchSamples, time: \.elapsedTime)
        }
    }

    mutating func appendSpectra(_ frames: [MonitorSpectrumFrame]) {
        guard retainedSampleCount > 0 else { return }
        let range = availableRange
        for frame in frames where frame.elapsedTime.isFinite && range.contains(frame.elapsedTime) {
            guard frame.isValid else { continue }
            Self.insert(frame, into: &spectrumFrames, time: \.elapsedTime)
        }
    }

    /// PCM covers [start, end), despite the chart API's closed time range. This
    /// keeps adjacent replay segments sample accurate, with no duplicated edge.
    /// Non-finite or empty ranges return no audio; finite ranges are clipped to
    /// the retained recording before converting their endpoints to samples.
    func audio(in range: ClosedRange<TimeInterval>) -> [Float] {
        guard retainedSampleCount > 0,
              range.lowerBound.isFinite, range.upperBound.isFinite,
              range.upperBound > range.lowerBound else { return [] }
        let lowerTime = max(availableRange.lowerBound, range.lowerBound)
        let upperTime = min(duration, range.upperBound)
        guard upperTime > lowerTime else { return [] }

        let firstSample = totalSampleCount - Int64(retainedSampleCount)
        let lowerSample = max(firstSample, Self.sampleBoundary(at: lowerTime))
        let upperSample = min(totalSampleCount, Self.sampleBoundary(at: upperTime))
        guard upperSample > lowerSample else { return [] }

        let offset = Int(lowerSample - firstSample)
        let count = Int(upperSample - lowerSample)
        let start = (firstStorageIndex + offset) % Self.sampleCapacity
        let firstCount = min(count, Self.sampleCapacity - start)
        var result: [Float] = []
        result.reserveCapacity(count)
        result.append(contentsOf: storage[start..<(start + firstCount)])
        if firstCount < count {
            result.append(contentsOf: storage[0..<(count - firstCount)])
        }
        return result
    }

    static func clampedTime(
        _ time: TimeInterval,
        availableRange: ClosedRange<TimeInterval>
    ) -> TimeInterval {
        let range = validRange(availableRange)
        guard time.isFinite else { return range.upperBound }
        return min(range.upperBound, max(range.lowerBound, time))
    }

    /// The cursor is the end of the selected window. A short recording or a
    /// cursor near the oldest sample produces a shorter window without moving
    /// the requested cursor forward.
    static func window(
        endingAt time: TimeInterval,
        duration: TimeInterval,
        availableRange: ClosedRange<TimeInterval>
    ) -> ClosedRange<TimeInterval> {
        let range = validRange(availableRange)
        let end = clampedTime(time, availableRange: range)
        let length = duration.isFinite ? max(0, duration) : 0
        return max(range.lowerBound, end - length)...end
    }

    static func rewind(
        time: TimeInterval,
        by seconds: TimeInterval = 5,
        availableRange: ClosedRange<TimeInterval>
    ) -> TimeInterval {
        let range = validRange(availableRange)
        let current = clampedTime(time, availableRange: range)
        let distance = seconds.isFinite ? max(0, seconds) : 0
        return max(range.lowerBound, current - distance)
    }

    private mutating func trimAnalysis() {
        let lower = availableRange.lowerBound
        let pitchCount = TimelineSearch.lowerBound(in: pitchSamples, at: lower, time: \.elapsedTime)
        if pitchCount > 0 { pitchSamples.removeFirst(pitchCount) }
        let spectrumCount = TimelineSearch.lowerBound(in: spectrumFrames, at: lower, time: \.elapsedTime)
        if spectrumCount > 0 { spectrumFrames.removeFirst(spectrumCount) }
    }

    /// Normal capture appends directly. Binary insertion also handles delayed
    /// callbacks and replaces duplicate timestamps so chart identities stay
    /// unique and repeated callback delivery cannot grow the history.
    private static func insert<Element>(
        _ element: Element,
        into elements: inout [Element],
        time: KeyPath<Element, TimeInterval>
    ) {
        let timestamp = element[keyPath: time]
        if elements.last.map({ $0[keyPath: time] < timestamp }) ?? true {
            elements.append(element)
            return
        }
        let lower = TimelineSearch.lowerBound(in: elements, at: timestamp, time: time)
        if lower < elements.count, elements[lower][keyPath: time] == timestamp {
            elements[lower] = element
        } else {
            elements.insert(element, at: lower)
        }
    }

    private static func sampleBoundary(at time: TimeInterval) -> Int64 {
        let sample = time * sampleRate
        // Division by the sample rate followed by multiplication can land one
        // ULP above an exact integer. Remove only that numerical roundoff,
        // while preserving the ceiling for genuinely fractional boundaries.
        return Int64((sample - 4 * sample.ulp).rounded(.up))
    }

    private static func validRange(_ range: ClosedRange<TimeInterval>) -> ClosedRange<TimeInterval> {
        guard range.lowerBound.isFinite, range.upperBound.isFinite else { return 0...0 }
        return range
    }
}
