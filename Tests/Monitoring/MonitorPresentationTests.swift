//
//  MonitorPresentationTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/6.
//

import Foundation
import Observation

/// Exercises the production presentation store without a microphone, native
/// inference runtime, or SwiftUI renderer. Input and publication are separate
/// so the checks can catch lost PCM and accidental per-buffer invalidations.
@main
enum MonitorPresentationTests {
    @MainActor
    static func main() {
        var checks = 0
        var failures = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            if !condition() {
                failures += 1
                print("FAIL: \(message)")
            }
        }
        func frame(_ time: Double, magnitude: Float = -20) -> MonitorSpectrumFrame {
            .init(elapsedTime: time, magnitudesDB: [-90, magnitude], binWidthHz: 100)
        }
        let sampleRate = MonitorTimeline.sampleRate

        let capture = MonitorPresentation()
        capture.publish(cursorTime: 0, windowDuration: 5, selectedRange: nil, includesPitch: true)
        check(capture.availableRange == 0...0 && capture.duration == 0,
              "an empty store has no retained audio")
        check(capture.pitchWindow.range == 0...5 && capture.pitchWindow.samples.isEmpty,
              "an empty chart uses the selected window duration")

        let changes = PresentationChanges()
        withObservationTracking {
            _ = capture.availableRange
            _ = capture.pitchWindow
            _ = capture.currentPitchHz
            _ = capture.currentSpectrum
            _ = capture.visibleSpectrogramColumns
            _ = capture.duration
        } onChange: {
            changes.record()
        }
        let unpublishedWindow = capture.pitchWindow
        var source: [Float] = []
        var inputPitches: [LivePitchSample] = []
        for index in 0..<100 {
            let count = [31, 127, 341, 1_024][index % 4]
            let block = (0..<count).map { Float(source.count + $0) / 65_536 }
            source.append(contentsOf: block)
            let time = Double(source.count) / sampleRate
            let pitch = LivePitchSample(elapsedTime: time, pitchHz: index.isMultiple(of: 7) ? nil : Double(120 + index))
            inputPitches.append(pitch)
            capture.append(audio: block, pitch: [pitch], spectra: [frame(time)])
        }
        check(changes.count == 0, "capture appends do not invalidate observed presentation fields")
        check(capture.availableRange == 0...0 && capture.pitchWindow === unpublishedWindow,
              "capture can advance while the published snapshot remains unchanged")
        check(capture.duration == Double(source.count) / sampleRate,
              "every variable-size PCM block advances the raw sample clock")
        check(capture.audio(in: 0...capture.duration) == source,
              "display throttling preserves every received PCM sample in order")
        check(capture.currentPitchHz == nil && capture.currentSpectrum == nil,
              "readouts remain unpublished until the owner requests a display update")

        capture.publish(cursorTime: capture.duration, windowDuration: 5, selectedRange: nil, includesPitch: true)
        check(changes.count > 0, "publishing new capture state notifies an observation subscriber")
        check(capture.availableRange == 0...capture.duration && capture.pitchWindow.range == 0...capture.duration,
              "publication exposes the complete captured range")
        check(capture.pitchWindow.samples.map(\.elapsedTime) == inputPitches.map(\.elapsedTime)
              && capture.pitchWindow.samples.map(\.pitchHz) == inputPitches.map(\.pitchHz),
              "publication preserves every pitch frame and explicit silent gap")
        check(capture.pitchWindow.pitchRange == 121...219 && capture.currentPitchHz == 219,
              "the shared window provides the voiced range and current pitch")
        let validPitches = inputPitches.compactMap(\.pitchHz)
        check(capture.pitchWindow.averagePitchHz == validPitches.reduce(0, +) / Double(validPitches.count),
              "the shared window provides the average of valid voiced pitches")
        check(capture.currentSpectrum?.elapsedTime == capture.duration,
              "the spectrum readout follows the same captured clock")

        // A pause can occur between display ticks. Force publication at the
        // raw tail, then resume from that sample clock rather than the old UI.
        let tail = MonitorPresentation()
        let firstSecond = [Float](repeating: 1, count: Int(sampleRate))
        tail.append(audio: firstSecond, pitch: [.init(elapsedTime: 1, pitchHz: 180)], spectra: [])
        tail.publish(cursorTime: tail.duration, windowDuration: 5, selectedRange: nil, includesPitch: true)
        let finalBlock = [Float](repeating: 2, count: 160)
        tail.append(audio: finalBlock, pitch: [.init(elapsedTime: 1.01, pitchHz: 260)], spectra: [])
        check(tail.availableRange.upperBound == 1 && tail.duration == 1.01,
              "an unpublished final buffer is retained beyond the display cursor")
        tail.publish(cursorTime: tail.duration, windowDuration: 5, selectedRange: nil, includesPitch: true)
        check(tail.pitchWindow.range.upperBound == 1.01 && tail.currentPitchHz == 260,
              "a forced pause publication includes the final received pitch and time")
        check(tail.audio(in: tail.availableRange) == firstSecond + finalBlock,
              "a replay selected after the forced publication includes the PCM tail")
        let resumeOffset = tail.duration
        let resumedBlock = [Float](repeating: 3, count: 160)
        tail.append(audio: resumedBlock,
                    pitch: [.init(elapsedTime: resumeOffset, pitchHz: nil),
                            .init(elapsedTime: resumeOffset + 0.01, pitchHz: 280)], spectra: [])
        tail.publish(cursorTime: tail.duration, windowDuration: 5, selectedRange: nil, includesPitch: true)
        check(tail.duration == 1.02 && tail.pitchWindow.samples.last?.elapsedTime == 1.02,
              "resumed pitch and PCM use the raw duration as their shared offset")
        check(tail.audio(in: 1...1.02) == finalBlock + resumedBlock,
              "pause and resume introduce no missing or duplicated PCM boundary")
        check(tail.pitchWindow.samples.first(where: { $0.elapsedTime == resumeOffset })?.pitchHz == nil,
              "the resume boundary remains an explicit pitch gap")

        // A frozen replay selects the same curve at every cursor position.
        // Only the latest readout changes, including silence and staleness.
        let replay = MonitorPresentation()
        replay.append(audio: [Float](repeating: 0, count: Int(sampleRate * 3)), pitch: [
            .init(elapsedTime: 0.1, pitchHz: 180),
            .init(elapsedTime: 0.5, pitchHz: 220),
            .init(elapsedTime: 1, pitchHz: nil),
            .init(elapsedTime: 1.25, pitchHz: 300),
            .init(elapsedTime: 2, pitchHz: .nan),
            .init(elapsedTime: 2.5, pitchHz: -100)
        ], spectra: [frame(0.1), frame(0.5, magnitude: -10), frame(1, magnitude: -100)])
        replay.publish(cursorTime: 0.1, windowDuration: 5, selectedRange: 0...3, includesPitch: true)
        let replayWindow = replay.pitchWindow
        check(replayWindow.pitchRange == 180...300 && replay.currentPitchHz == 180,
              "window statistics exclude silent and invalid detector values")
        let cursorChecks: [(Double, Double?)] = [
            (0, nil), (0.1, 180), (0.5, 220), (0.9, 220), (0.900_001, nil),
            (1, nil), (1.25, 300), (1.6, 300), (1.7, nil), (2, nil), (2.5, nil)
        ]
        for (cursor, expected) in cursorChecks {
            replay.publish(cursorTime: cursor, windowDuration: 5, selectedRange: 0...3, includesPitch: true)
            check(replay.pitchWindow === replayWindow && replay.pitchWindow.range == 0...3,
                  "moving replay cursor \(cursor) preserves the selected curve instance")
            check(replay.currentPitchHz == expected,
                  "cursor \(cursor) selects a real pitch, silence, or the 0.4-second staleness limit")
        }
        replay.publish(cursorTime: 0.9, windowDuration: 5, selectedRange: 0...3, includesPitch: true)
        check(replay.currentSpectrum?.elapsedTime == 0.5,
              "a spectrum exactly 0.4 seconds old is still current")
        replay.publish(cursorTime: 0.900_001, windowDuration: 5, selectedRange: 0...3, includesPitch: true)
        check(replay.currentSpectrum == nil, "an older spectrum is not carried through missing input")
        replay.publish(cursorTime: 1, windowDuration: 5, selectedRange: 0...3, includesPitch: true)
        check(replay.currentSpectrum?.elapsedTime == 1 && replay.currentSpectrum?.peak == nil,
              "a silent spectrum remains a real frame with no invented peak")

        replay.append(audio: [], pitch: [.init(elapsedTime: 0.5, pitchHz: 240)], spectra: [])
        replay.publish(cursorTime: 0.5, windowDuration: 5, selectedRange: 0...3, includesPitch: true)
        check(replay.pitchWindow !== replayWindow && replay.currentPitchHz == 240,
              "new analysis invalidates a fixed-range snapshot and updates its readout")
        check(replayWindow.samples.first(where: { $0.elapsedTime == 0.5 })?.pitchHz == 220,
              "previously published curve instances remain immutable after an analysis replacement")
        let updatedWindow = replay.pitchWindow
        replay.publish(cursorTime: 0.6, windowDuration: 30, selectedRange: 0...3, includesPitch: true)
        check(replay.pitchWindow === updatedWindow,
              "an explicit playback range remains fixed if the requested default duration changes")
        replay.publish(cursorTime: 0.6, windowDuration: 5, selectedRange: 0...3, includesPitch: false)
        check(replay.pitchWindow.samples.isEmpty && replay.pitchWindow.pitchRange == nil,
              "spectrum-only publication does not collect a pitch curve or range")
        let withoutPitch = replay.pitchWindow
        replay.publish(cursorTime: 1, windowDuration: 5, selectedRange: 0...3, includesPitch: false)
        check(replay.pitchWindow === withoutPitch,
              "moving a spectrum-only replay cursor preserves its empty plotting window")
        replay.publish(cursorTime: 0.5, windowDuration: 5, selectedRange: 0...3, includesPitch: true)
        check(replay.pitchWindow !== withoutPitch && replay.pitchWindow.samples.count == 6
              && replay.currentPitchHz == 240,
              "reenabling pitch rebuilds from retained analysis without losing hidden samples")

        let retained = MonitorPresentation()
        let longAudio = (0..<Int(sampleRate * 65)).map { Float($0 % 256) / 256 }
        retained.append(audio: longAudio, pitch: [
            .init(elapsedTime: 4.99, pitchHz: 100),
            .init(elapsedTime: 5, pitchHz: 150),
            .init(elapsedTime: 5.0005, pitchHz: 155),
            .init(elapsedTime: 10, pitchHz: 200),
            .init(elapsedTime: 20, pitchHz: 220),
            .init(elapsedTime: 30, pitchHz: 240),
            .init(elapsedTime: 60, pitchHz: 260),
            .init(elapsedTime: 65, pitchHz: 280)
        ], spectra: [])
        retained.publish(cursorTime: 65, windowDuration: 5, selectedRange: nil, includesPitch: true)
        check(retained.availableRange == 5...65 && retained.pitchWindow.range == 60...65,
              "a live publication respects both the sixty-second retention and five-second window")
        check(retained.audio(in: 0...65) == Array(longAudio.suffix(Int(sampleRate * 60))),
              "long capture retains the exact newest sixty seconds of PCM")
        check(retained.pitchWindow.samples.map(\.elapsedTime) == [60, 65],
              "window samples include the exact start and end boundaries")
        retained.publish(cursorTime: 20, windowDuration: 30, selectedRange: nil, includesPitch: true)
        check(retained.pitchWindow.range == 5...20
              && retained.pitchWindow.samples.map(\.elapsedTime) == [5, 5.0005, 10, 20],
              "seeking near evicted history clips the window without moving the cursor")
        retained.publish(cursorTime: 20, windowDuration: 5, selectedRange: nil, includesPitch: true)
        check(retained.pitchWindow.range == 15...20 && retained.pitchWindow.pitchRange == 220...220,
              "a window-duration change immediately derives the newly selected curve and range")
        retained.publish(cursorTime: 5, windowDuration: 10, selectedRange: nil, includesPitch: true)
        check(retained.pitchWindow.range == 5...5.001
              && retained.pitchWindow.samples.map(\.elapsedTime) == [5, 5.0005],
              "the oldest retained cursor has a nonzero chart domain with valid edge samples")
        retained.publish(cursorTime: 100, windowDuration: 10, selectedRange: nil, includesPitch: true)
        check(retained.pitchWindow.range == 55...65,
              "a selection beyond capture clamps to the current live edge")

        // Raster columns follow the same retention and publication boundary.
        // Cursor-only replay must reuse pixels and leave the observed array alone.
        let spectral = MonitorPresentation()
        let rasterFrame = frame(0.1)
        guard let pixels = MonitorSpectrogramRasterizer.makeColumn(frame: rasterFrame) else {
            fatalError("valid spectrum fixture did not produce a raster column")
        }
        let columnChanges = PresentationChanges()
        withObservationTracking {
            _ = spectral.visibleSpectrogramColumns
        } onChange: {
            columnChanges.record()
        }
        spectral.append(audio: [Float](repeating: 0, count: Int(sampleRate * 2)),
                        pitch: [], spectra: [rasterFrame], columns: [
                            .init(elapsedTime: 0.1, image: pixels),
                            .init(elapsedTime: 1.5, image: pixels),
                            .init(elapsedTime: 1.5, image: pixels),
                            .init(elapsedTime: 3, image: pixels)
                        ])
        check(columnChanges.count == 0 && spectral.visibleSpectrogramColumns.isEmpty,
              "raster ingestion does not publish an observed column array")
        spectral.publish(cursorTime: 0.1, windowDuration: 5, selectedRange: 0...2, includesPitch: false)
        check(spectral.visibleSpectrogramColumns.map(\.elapsedTime) == [0.1, 1.5],
              "spectrogram publication sorts and deduplicates retained capture timestamps")
        check(spectral.visibleSpectrogramColumns.first?.image === pixels && columnChanges.count == 1,
              "publication reuses the worker's raster image and notifies observers")
        let replayColumnChanges = PresentationChanges()
        withObservationTracking {
            _ = spectral.visibleSpectrogramColumns
        } onChange: {
            replayColumnChanges.record()
        }
        spectral.publish(cursorTime: 1.5, windowDuration: 5, selectedRange: 0...2, includesPitch: false)
        check(replayColumnChanges.count == 0,
              "moving the replay cursor does not republish or reslice fixed spectrogram columns")
        spectral.append(audio: [Float](repeating: 0, count: Int(sampleRate * 61)),
                        pitch: [], spectra: [], columns: [
                            .init(elapsedTime: 2.9, image: pixels),
                            .init(elapsedTime: 3, image: pixels),
                            .init(elapsedTime: 63, image: pixels)
                        ])
        check(replayColumnChanges.count == 0, "raw raster retention does not notify display observers")
        spectral.publish(cursorTime: 63, windowDuration: 30, selectedRange: 3...63, includesPitch: false)
        check(spectral.visibleSpectrogramColumns.map(\.elapsedTime) == [3, 63],
              "raster eviction uses the raw PCM range even when presentation was delayed")
        spectral.reset(windowDuration: 10, includesPitch: false)
        check(spectral.visibleSpectrogramColumns.isEmpty, "leaving clears retained spectrogram pixels")

        replay.reset(windowDuration: 30, includesPitch: true)
        check(replay.duration == 0 && replay.availableRange == 0...0 && replay.audio(in: 0...3).isEmpty,
              "leaving resets both the raw PCM and published available range")
        check(replay.pitchWindow.range == 0...30 && replay.pitchWindow.samples.isEmpty
              && replay.pitchWindow.pitchRange == nil,
              "reset replaces cached analysis with an empty window of the selected duration")
        check(replay.currentPitchHz == nil && replay.currentSpectrum == nil,
              "reset clears both frequency readouts")
        replay.append(audio: [1, 2, 3], pitch: [], spectra: [])
        replay.publish(cursorTime: replay.duration, windowDuration: 5, selectedRange: nil, includesPitch: false)
        check(replay.duration == 3 / sampleRate && replay.audio(in: 0...replay.duration) == [1, 2, 3],
              "a fresh capture after reset starts at zero without previous PCM")

        print("Monitor presentation checks: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}

private final class PresentationChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var notifications = 0
    var count: Int { lock.withLock { notifications } }
    func record() { lock.withLock { notifications += 1 } }
}
