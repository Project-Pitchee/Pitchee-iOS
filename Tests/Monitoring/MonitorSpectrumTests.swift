//
//  MonitorSpectrumTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import Foundation

@main
enum MonitorSpectrumTests {
    static func main() throws {
        var checks = 0
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition {
                failures += 1
                print("FAIL: \(message)")
            }
        }
        func tone(_ frequency: Double, amplitude: Double, count: Int) -> [Float] {
            (0..<count).map {
                Float(amplitude * sin(2 * .pi * frequency * Double($0) / 16_000))
            }
        }

        let silence = try MonitorSpectrumAnalyzer()
        check(silence.process([]).isEmpty, "empty input emits no frame")
        check(silence.process([Float](repeating: 0, count: 2_047)).isEmpty,
              "incomplete FFT windows wait for the next tap")
        let silentFrames = silence.process([0])
        check(silentFrames.count == 1, "a completed window emits exactly once")
        let silent = silentFrames[0]
        check(silent.magnitudesDB.count == 1_025, "spectrum includes DC and Nyquist")
        check(silent.binWidthHz == 7.8125, "bins span the 16 kHz sample rate")
        check(abs(silent.elapsedTime - 0.128) < 0.000_000_1,
              "first timestamp is the end of the first FFT window")
        check(silent.magnitudesDB.allSatisfy { $0 == -120 },
              "silence produces finite -120 dBFS bins")
        check(silent.isValid && silent.peak == nil, "A silent frame has no cached visible peak")

        let signal = tone(1_000, amplitude: 0.5, count: 16_000)
        let whole = try MonitorSpectrumAnalyzer().process(signal)
        check(whole.count == 9, "one second yields 10 Hz spectra after the first full window")
        check(zip(whole, whole.dropFirst()).allSatisfy {
            abs($1.elapsedTime - $0.elapsedTime - 0.1) < 0.000_000_1
        }, "spectrum timestamps advance by the fixed hop duration")
        let frame = whole[0]
        let peak = frame.magnitudesDB.indices.max { frame.magnitudesDB[$0] < frame.magnitudesDB[$1] }!
        check(peak == 128, "1 kHz input peaks at the correct frequency bin")
        check(frame.peak?.frequencyHz == 1_000 && frame.peak?.amplitudeDBFS == frame.magnitudesDB[128],
              "The cached peak matches the strongest visible FFT bin")
        check(abs(frame.magnitudesDB[128] - (-6.020_6)) < 0.01,
              "Hann coherent gain preserves half-scale sine amplitude")
        check(frame.magnitudesDB[110] < -90 && frame.magnitudesDB[150] < -90,
              "a coherent tone does not leak into distant bins")

        let quieter = try MonitorSpectrumAnalyzer().process(tone(1_000, amplitude: 0.25, count: 2_048))[0]
        check(abs(frame.magnitudesDB[128] - quieter.magnitudesDB[128] - 6.020_6) < 0.01,
              "halving input amplitude lowers the peak by 6.02 dB")

        let dc = try MonitorSpectrumAnalyzer().process([Float](repeating: 0.5, count: 2_048))[0]
        check(abs(dc.magnitudesDB[0] - (-6.020_6)) < 0.01,
              "packed DC receives the correct amplitude scaling")
        let nyquistSignal = (0..<2_048).map { Float($0.isMultiple(of: 2) ? 0.5 : -0.5) }
        let nyquist = try MonitorSpectrumAnalyzer().process(nyquistSignal)[0]
        check(abs(nyquist.magnitudesDB[1_024] - (-6.020_6)) < 0.01,
              "packed Nyquist receives the correct amplitude scaling")
        check(nyquist.magnitudesDB[0] < -90 && dc.magnitudesDB[1_024] < -90,
              "DC and Nyquist are distinct spectrum bins")
        let endpointPeak = MonitorSpectrumFrame(elapsedTime: 1, magnitudesDB: [0, -60], binWidthHz: 8_000)
        check(endpointPeak.peak?.frequencyHz == 8_000,
              "Visible peak selection excludes DC and includes the Nyquist endpoint")

        let boundedPeak = MonitorSpectrumFrame(elapsedTime: 1,
                                               magnitudesDB: [0, -95, -40, -40, -10], binWidthHz: 2_500)
        check(boundedPeak.peak?.frequencyHz == 5_000 && boundedPeak.peak?.amplitudeDBFS == -40,
              "Peak selection ignores inaudible bins and keeps the first strongest visible bin on ties")
        let shiftedPeak = boundedPeak.offset(by: 60)
        check(shiftedPeak.elapsedTime == 61 && shiftedPeak.magnitudesDB == boundedPeak.magnitudesDB
              && shiftedPeak.peak?.frequencyHz == boundedPeak.peak?.frequencyHz
              && shiftedPeak.peak?.amplitudeDBFS == boundedPeak.peak?.amplitudeDBFS,
              "Resuming capture offsets the frame clock without changing its cached spectrum")
        let threshold = MonitorSpectrumFrame(elapsedTime: 1, magnitudesDB: [-10, -95], binWidthHz: 100)
        check(threshold.peak == nil, "A peak at the silence threshold stays hidden")
        for invalid in [
            MonitorSpectrumFrame(elapsedTime: 1, magnitudesDB: [], binWidthHz: 1),
            MonitorSpectrumFrame(elapsedTime: 1, magnitudesDB: [-20, .nan], binWidthHz: 100),
            MonitorSpectrumFrame(elapsedTime: 1, magnitudesDB: [-20], binWidthHz: .infinity),
            MonitorSpectrumFrame(elapsedTime: 1, magnitudesDB: [-20], binWidthHz: 0)
        ] {
            check(!invalid.isValid && invalid.peak == nil, "Invalid spectrum data cannot populate cached readouts")
        }

        let secondTone = tone(2_500, amplitude: 0.125, count: 2_048)
        let mixedSignal = zip(signal.prefix(2_048), secondTone).map(+)
        let mixed = try MonitorSpectrumAnalyzer().process(mixedSignal)[0]
        check(abs(mixed.magnitudesDB[128] - (-6.020_6)) < 0.01 &&
              abs(mixed.magnitudesDB[320] - (-18.061_8)) < 0.01,
              "two simultaneous tones retain their independent frequencies and levels")

        for batchSize in [1, 317, 1_024, 4_096] {
            let chunkedAnalyzer = try MonitorSpectrumAnalyzer()
            var chunked: [MonitorSpectrumFrame] = []
            for offset in stride(from: 0, to: signal.count, by: batchSize) {
                chunked += chunkedAnalyzer.process(Array(signal[offset..<min(offset + batchSize, signal.count)]))
            }
            check(chunked.count == whole.count, "batch size \(batchSize) preserves frame count")
            check(zip(chunked, whole).allSatisfy {
                $0.elapsedTime == $1.elapsedTime && $0.magnitudesDB == $1.magnitudesDB
            }, "batch size \(batchSize) preserves overlap, time, and every spectrum bin")
        }

        for invalid: Float in [.nan, .infinity, -.infinity] {
            var invalidWindow = [Float](repeating: 0, count: 2_048)
            invalidWindow[100] = invalid
            let invalidFrame = try MonitorSpectrumAnalyzer().process(invalidWindow)[0]
            check(invalidFrame.magnitudesDB.allSatisfy { $0 == -120 },
                  "Nonfinite input cannot propagate NaN or infinity into displayed FFT bins")
        }
        let restarted = try MonitorSpectrumAnalyzer().process(signal)
        check(restarted[0].elapsedTime == 0.128,
              "a fresh capture starts a fresh spectrum timeline")
        check(restarted[0].magnitudesDB == whole[0].magnitudesDB,
              "a fresh capture does not retain earlier audio")
        print("Monitor spectrum: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
