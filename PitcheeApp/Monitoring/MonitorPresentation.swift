//
//  MonitorPresentation.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/6.
//

import Foundation
import Observation

/// A fixed plotting window shared by the curve, range readout and empty state.
/// Its identity stays stable while only the playback cursor moves.
nonisolated final class MonitorPitchWindow: Sendable {
    let range: ClosedRange<TimeInterval>
    let samples: [LivePitchSample]
    let pitchRange: ClosedRange<Double>?

    init(range: ClosedRange<TimeInterval>, samples: [LivePitchSample]) {
        self.range = range
        self.samples = samples
        var low: Double?
        var high: Double?
        for sample in samples {
            guard let pitch = sample.pitchHz, pitch.isFinite, pitch > 0 else { continue }
            low = min(low ?? pitch, pitch)
            high = max(high ?? pitch, pitch)
        }
        pitchRange = low.flatMap { low in high.map { low...$0 } }
    }
}

/// Capture storage is deliberately unobserved. The owner publishes at its
/// display cadence without dropping PCM or exposing the large ring to COW.
@MainActor
@Observable
final class MonitorPresentation {
    private(set) var availableRange: ClosedRange<TimeInterval> = 0...0
    private(set) var pitchWindow = MonitorPitchWindow(range: 0...10, samples: [])
    private(set) var retainedPitchRange: ClosedRange<Double>?
    private(set) var visibleSpectrogramColumns: [MonitorSpectrogramColumn] = []
    private(set) var currentPitchHz: Double?
    private(set) var currentSpectrum: MonitorSpectrumFrame?
    private(set) var smoothedSpectrumPeak: (frequencyHz: Double, amplitudeDBFS: Float)?

    @ObservationIgnored private var timeline = MonitorTimeline()
    @ObservationIgnored private var spectrogramColumns: [MonitorSpectrogramColumn] = []
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var publishedRevision: UInt64?
    @ObservationIgnored private var publishedIncludesPitch = true

    var duration: TimeInterval { timeline.duration }

    func append(audio: [Float], pitch: [LivePitchSample], spectra: [MonitorSpectrumFrame],
                columns: [MonitorSpectrogramColumn] = []) {
        timeline.appendAudio(audio)
        timeline.appendPitch(pitch)
        timeline.appendSpectra(spectra)
        appendSpectrogramColumns(columns)
        revision &+= 1
    }

    func audio(in range: ClosedRange<TimeInterval>) -> [Float] {
        timeline.audio(in: range)
    }

    func publish(cursorTime: TimeInterval, windowDuration: TimeInterval,
                 playbackRange: ClosedRange<TimeInterval>?, includesPitch: Bool) {
        let retained = timeline.availableRange
        if availableRange != retained { availableRange = retained }
        let range: ClosedRange<TimeInterval>
        if let playbackRange {
            range = playbackRange
        } else if retained.upperBound <= retained.lowerBound {
            range = 0...windowDuration
        } else {
            let selected = MonitorTimeline.window(
                endingAt: cursorTime, duration: windowDuration, availableRange: retained
            )
            range = selected.lowerBound...max(selected.lowerBound + 0.001, selected.upperBound)
        }

        let dataChanged = publishedRevision != revision
        if dataChanged || publishedIncludesPitch != includesPitch {
            let pitchRange = includesPitch
                ? MonitorPitchWindow(range: retained, samples: timeline.pitchSamples).pitchRange : nil
            if retainedPitchRange != pitchRange { retainedPitchRange = pitchRange }
        }
        if dataChanged || pitchWindow.range != range
            || publishedIncludesPitch != includesPitch {
            let samples = includesPitch ? Array(TimelineSearch.samples(
                in: timeline.pitchSamples, range: range, time: \.elapsedTime
            )) : []
            pitchWindow = MonitorPitchWindow(range: range, samples: samples)
            visibleSpectrogramColumns = includesPitch ? [] : Array(TimelineSearch.samples(
                in: spectrogramColumns, range: range, time: \.elapsedTime
            ))
            publishedRevision = revision
            publishedIncludesPitch = includesPitch
        }

        let sample = TimelineSearch.latest(in: timeline.pitchSamples, at: cursorTime, time: \.elapsedTime)
        let pitch = sample.flatMap { cursorTime - $0.elapsedTime <= 0.4 ? $0.pitchHz : nil }
        if currentPitchHz != pitch { currentPitchHz = pitch }
        let spectrum = TimelineSearch.latest(in: timeline.spectrumFrames, at: cursorTime, time: \.elapsedTime)
        let currentFrame = spectrum.flatMap { cursorTime - $0.elapsedTime <= 0.4 ? $0 : nil }
        if dataChanged || currentSpectrum?.elapsedTime != currentFrame?.elapsedTime {
            currentSpectrum = currentFrame
            smoothedSpectrumPeak = nil
            if let currentFrame, currentFrame.peak != nil {
                // Median of up to three recent raw peaks; silence starts a new group.
                let peaks = TimelineSearch.samples(
                    in: timeline.spectrumFrames,
                    range: (currentFrame.elapsedTime - 0.2)...currentFrame.elapsedTime,
                    time: \.elapsedTime
                ).reversed().prefix(while: { $0.peak != nil }).prefix(3)
                    .compactMap(\.peak).sorted { $0.frequencyHz < $1.frequencyHz }
                smoothedSpectrumPeak = peaks.isEmpty ? nil : peaks[peaks.count / 2]
            }
        }
    }

    func reset(windowDuration: TimeInterval, includesPitch: Bool) {
        timeline = MonitorTimeline()
        spectrogramColumns = []
        revision &+= 1
        publish(cursorTime: 0, windowDuration: windowDuration, playbackRange: nil, includesPitch: includesPitch)
    }

    private func appendSpectrogramColumns(_ columns: [MonitorSpectrogramColumn]) {
        let range = timeline.availableRange
        for column in columns where column.elapsedTime.isFinite && range.contains(column.elapsedTime) {
            if spectrogramColumns.last.map({ $0.elapsedTime < column.elapsedTime }) ?? true {
                spectrogramColumns.append(column)
            } else {
                let index = TimelineSearch.lowerBound(
                    in: spectrogramColumns, at: column.elapsedTime, time: \.elapsedTime
                )
                if index < spectrogramColumns.count,
                   spectrogramColumns[index].elapsedTime == column.elapsedTime {
                    spectrogramColumns[index] = column
                } else {
                    spectrogramColumns.insert(column, at: index)
                }
            }
        }
        let expiredCount = TimelineSearch.lowerBound(
            in: spectrogramColumns, at: range.lowerBound, time: \.elapsedTime
        )
        if expiredCount > 0 { spectrogramColumns.removeFirst(expiredCount) }
    }
}
