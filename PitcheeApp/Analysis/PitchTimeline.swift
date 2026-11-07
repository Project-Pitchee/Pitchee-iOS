//
//  PitchTimeline.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/19.
//

import Foundation

nonisolated struct LivePitchSample: Identifiable, Sendable {
    let elapsedTime: TimeInterval
    let pitchHz: Double?

    var id: TimeInterval { elapsedTime }
}

/// Searches the finite, ascending timestamps produced by capture and analysis.
/// The returned slice shares storage with its source; selecting a short chart
/// window does not scan or copy the complete recording.
nonisolated enum TimelineSearch {
    static func lowerBound<Element>(
        in elements: [Element],
        at timestamp: TimeInterval,
        time: KeyPath<Element, TimeInterval>
    ) -> Int {
        boundary(in: elements, at: timestamp, time: time, includingEqual: false)
    }

    static func upperBound<Element>(
        in elements: [Element],
        at timestamp: TimeInterval,
        time: KeyPath<Element, TimeInterval>
    ) -> Int {
        boundary(in: elements, at: timestamp, time: time, includingEqual: true)
    }

    static func samples<Element>(
        in elements: [Element],
        range: ClosedRange<TimeInterval>,
        time: KeyPath<Element, TimeInterval>,
        includingNeighbors: Bool = false
    ) -> ArraySlice<Element> {
        guard range.lowerBound.isFinite, range.upperBound.isFinite else { return elements[0..<0] }
        var lower = lowerBound(in: elements, at: range.lowerBound, time: time)
        var upper = upperBound(in: elements, at: range.upperBound, time: time)
        if includingNeighbors {
            lower = max(0, lower - 1)
            upper = min(elements.count, upper + 1)
        }
        return elements[lower..<upper]
    }

    static func latest<Element>(
        in elements: [Element],
        at timestamp: TimeInterval,
        time: KeyPath<Element, TimeInterval>
    ) -> Element? {
        guard timestamp.isFinite else { return nil }
        let end = upperBound(in: elements, at: timestamp, time: time)
        return end > 0 ? elements[end - 1] : nil
    }

    private static func boundary<Element>(
        in elements: [Element],
        at timestamp: TimeInterval,
        time: KeyPath<Element, TimeInterval>,
        includingEqual: Bool
    ) -> Int {
        // Most live queries target the newest frame or the oldest retained
        // boundary. Keep these cases constant-time as the history grows.
        guard let first = elements.first else { return 0 }
        let firstTime = first[keyPath: time]
        if includingEqual ? firstTime > timestamp : firstTime >= timestamp { return 0 }
        let lastTime = elements[elements.count - 1][keyPath: time]
        if includingEqual ? lastTime <= timestamp : lastTime < timestamp { return elements.count }

        var lower = 0
        var upper = elements.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let candidate = elements[middle][keyPath: time]
            if includingEqual ? candidate <= timestamp : candidate < timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

/// A display-sized snapshot of the scoring page's latest ten seconds. Capture
/// keeps every detector frame; only this plotting copy is reduced.
nonisolated struct ScoringPitchSnapshot: Sendable {
    private static let visibleSeconds: TimeInterval = 10
    private static let maximumPointCount = 640

    let samples: [LivePitchSample]
    let timeRange: ClosedRange<TimeInterval>
    let cursorTime: TimeInterval
    let currentPitch: Double?

    init(samples source: [LivePitchSample]) {
        let latestTime = source.last?.elapsedTime ?? 0
        cursorTime = latestTime.isFinite ? max(0, latestTime) : 0
        let end = max(Self.visibleSeconds, cursorTime)
        timeRange = (end - Self.visibleSeconds)...end
        currentPitch = Self.currentPitch(in: source)
        samples = Self.plotSamples(in: TimelineSearch.samples(
            in: source, range: timeRange, time: \.elapsedTime
        ))
    }

    /// The readout uses real detector samples, including pitches outside the
    /// chart's vertical range, without rebuilding the plotting snapshot.
    static func currentPitch(in samples: [LivePitchSample]) -> Double? {
        guard let latestTime = samples.last?.elapsedTime, latestTime.isFinite else { return nil }
        let recent = TimelineSearch.samples(
            in: samples, range: (latestTime - 0.6)...latestTime, time: \.elapsedTime
        )
        return recent.last { sample in
            guard let pitch = sample.pitchHz else { return false }
            return pitch.isFinite && pitch > 0
        }?.pitchHz
    }

    private static func plotSamples(in visible: ArraySlice<LivePitchSample>) -> [LivePitchSample] {
        guard visible.count > maximumPointCount else { return Array(visible) }

        // Each bucket retains its endpoints and both extrema in timestamp
        // order. At most three gap markers separate those four selected points,
        // so the output stays below 640 even for rapidly alternating voicing.
        let bucketCount = maximumPointCount / 7
        var output: [LivePitchSample] = []
        output.reserveCapacity(maximumPointCount)
        for bucket in 0..<bucketCount {
            let start = visible.startIndex + bucket * visible.count / bucketCount
            let end = visible.startIndex + (bucket + 1) * visible.count / bucketCount
            var minimum: (index: Int, pitch: Double)?
            var maximum: (index: Int, pitch: Double)?
            for index in start..<end {
                guard isDrawable(visible[index]), let pitch = visible[index].pitchHz else { continue }
                if minimum.map({ pitch < $0.pitch }) ?? true { minimum = (index, pitch) }
                if maximum.map({ pitch > $0.pitch }) ?? true { maximum = (index, pitch) }
            }

            let selected = [start, minimum?.index, maximum?.index, end - 1].compactMap { $0 }.sorted()
            var previous: Int?
            for index in selected where index != previous {
                if let previous, isDrawable(visible[previous]), isDrawable(visible[index]),
                   let gap = ((previous + 1)..<index).first(where: { !isDrawable(visible[$0]) }) {
                    // Keep an actual missing/invalid frame. Removing it would
                    // fabricate a voiced line through a short silent interval.
                    output.append(visible[gap])
                }
                output.append(visible[index])
                previous = index
            }
        }
        return output
    }

    private static func isDrawable(_ sample: LivePitchSample) -> Bool {
        guard let pitch = sample.pitchHz else { return false }
        return pitch.isFinite && (50...1_000).contains(pitch)
    }
}

nonisolated struct PitchTimeline: Sendable {
    static let visibleSeconds: TimeInterval = 3

    let samples: [LivePitchSample]
    let duration: TimeInterval

    init(samples: [LivePitchSample], duration: TimeInterval) {
        self.samples = samples
        self.duration = max(duration, samples.last?.elapsedTime ?? 0)
    }

    init(result: PitcheeAnalysisResult) {
        self.init(
            samples: result.f0.windows.map {
                LivePitchSample(elapsedTime: ($0.startSeconds + $0.endSeconds) / 2, pitchHz: $0.f0Hz)
            },
            duration: result.audio.analyzedSeconds
        )
    }

    /// Bound image dimensions for long recordings without dropping any time.
    /// Each row includes its neighboring samples so lines join at row boundaries.
    var imageRows: [Row] {
        let secondsPerRow = max(15, ceil(duration / 24 / 15) * 15)
        let rowCount = max(1, Int(ceil(duration / secondsPerRow)))
        var rows: [Row] = []
        var startIndex = 0
        var endIndex = 0
        for index in 0..<rowCount {
            let start = Double(index) * secondsPerRow
            let end = min(duration, start + secondsPerRow)
            while startIndex < samples.count, samples[startIndex].elapsedTime < start {
                startIndex += 1
            }
            while endIndex < samples.count, samples[endIndex].elapsedTime <= end {
                endIndex += 1
            }
            rows.append(Row(
                range: start...max(start + 0.001, end),
                samples: Array(samples[max(0, startIndex - 1)..<min(samples.count, endIndex + 1)])
            ))
        }
        return rows
    }

    nonisolated struct Row: Identifiable {
        let range: ClosedRange<TimeInterval>
        let samples: [LivePitchSample]
        var id: TimeInterval { range.lowerBound }
    }
}
