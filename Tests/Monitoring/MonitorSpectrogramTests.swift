//
//  MonitorSpectrogramTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/6.
//

import CoreGraphics
import Foundation

@main
enum MonitorSpectrogramTests {
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
        func pixels(_ frame: MonitorSpectrumFrame) -> [[UInt8]] {
            guard let image = MonitorSpectrogramRasterizer.makeColumn(frame: frame),
                  let data = image.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(data) else { return [] }
            return (0..<image.height).map { row in
                Array(UnsafeBufferPointer(start: bytes + row * image.bytesPerRow, count: 4))
            }
        }
        func frame(_ magnitudes: [Float], width: Double = 7.8125) -> MonitorSpectrumFrame {
            MonitorSpectrumFrame(elapsedTime: 1, magnitudesDB: magnitudes, binWidthHz: width)
        }
        func tone(_ frequency: Double, amplitude: Double) -> [Float] {
            (0..<2_048).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / 16_000)) }
        }
        func intensity(_ pixel: [UInt8]) -> Int {
            // The palette becomes warmer and brighter as signal level rises.
            Int(pixel[0]) + Int(pixel[1])
        }
        func strongestRow(_ values: [[UInt8]], in rows: Range<Int>) -> Int? {
            rows.max { intensity(values[$0]) < intensity(values[$1]) }
        }

        let silentFrame = try MonitorSpectrumAnalyzer().process([Float](repeating: 0, count: 2_048))[0]
        let silentImage = MonitorSpectrogramRasterizer.makeColumn(frame: silentFrame)!
        let silent = pixels(silentFrame)
        check(silentImage.width == 1 && silentImage.height == 512,
              "A frame becomes one full-resolution vertical image column")
        check(silent.count == 512 && silent.allSatisfy { $0 == silent[0] },
              "Silence produces a uniform background without frequency artifacts")
        check(silent[0][2] > silent[0][0] * 3 && silent[0][2] > silent[0][1] * 3,
              "The quiet background is deep blue")
        check(silent.allSatisfy { $0[3] == 255 }, "Columns are fully opaque")

        let singleFrame = try MonitorSpectrumAnalyzer().process(tone(1_000, amplitude: 0.5))[0]
        let single = pixels(singleFrame)
        let peakRow = strongestRow(single, in: 0..<512)!
        check((197...204).contains(peakRow), "A 1 kHz tone appears at its logarithmic frequency position")
        check(intensity(single[peakRow]) > 400, "A strong tone appears in a warm bright color")
        check(intensity(single[50]) == intensity(silent[50]) && intensity(single[450]) == intensity(silent[450]),
              "A tone does not paint unrelated high or low frequencies")

        let mixedSamples = zip(tone(250, amplitude: 0.5), tone(4_000, amplitude: 0.125)).map(+)
        let mixed = pixels(try MonitorSpectrumAnalyzer().process(mixedSamples)[0])
        let lowRow = strongestRow(mixed, in: 300..<400)!
        let highRow = strongestRow(mixed, in: 30..<100)!
        check((330...341).contains(lowRow) && (65...68).contains(highRow),
              "Two tones retain their separate positions with low frequencies below high frequencies")
        check(intensity(mixed[lowRow]) > intensity(mixed[highRow]),
              "The stronger of two simultaneous tones has the brighter color")
        check(MonitorSpectrogramRasterizer.verticalFraction(for: 40) == 1
              && MonitorSpectrogramRasterizer.verticalFraction(for: 8_000) == 0,
              "Axis endpoints align with bottom 40 Hz and top 8 kHz")
        let geometricMiddle = sqrt(40.0 * 8_000.0)
        check(abs(MonitorSpectrogramRasterizer.verticalFraction(for: geometricMiddle) - 0.5) < 0.000_001,
              "Equal frequency ratios occupy equal vertical distances")

        var base = [Float](repeating: -120, count: 1_025)
        base[900] = -12
        let narrowPeak = pixels(frame(base))
        check(narrowPeak.contains { intensity($0) > 400 },
              "A single high-frequency FFT bin survives compression into the logarithmic image")
        base[0] = 0
        check(pixels(frame(base)) == narrowPeak, "A strong DC component never colors the visible range")
        var nyquistBins = [Float](repeating: -120, count: 1_025)
        nyquistBins[1_024] = 0
        check(intensity(pixels(frame(nyquistBins))[0]) > 450,
              "The Nyquist bin remains visible at the top of the column")

        let lowerSampleRate = pixels(frame([Float](repeating: -12, count: 129)))
        check(lowerSampleRate.prefix(180).allSatisfy { $0 == silent[0] },
              "A lower Nyquist limit leaves unavailable upper frequencies at the background color")
        check(lowerSampleRate.suffix(200).contains { intensity($0) > 400 },
              "A lower sample rate still renders its available frequencies")
        let dcOnly = pixels(frame([0]))
        check(dcOnly == silent, "A valid DC-only frame contains no visible signal")

        var intensities: [Int] = []
        for level: Float in [-120, -90, -70, -50, -30, -10, 0, 20] {
            var bins = [Float](repeating: -120, count: 1_025)
            bins[128] = level
            intensities.append(pixels(frame(bins)).map(intensity).max()!)
        }
        check(zip(intensities, intensities.dropFirst()).allSatisfy { $0 <= $1 },
              "Increasing amplitude never decreases the displayed brightness")
        check(intensities[0] == intensities[1] && intensities[6] == intensities[7],
              "Values below the noise floor and above full scale clamp to stable palette endpoints")

        for invalid in [
            MonitorSpectrumFrame(elapsedTime: .nan, magnitudesDB: [-10], binWidthHz: 1),
            MonitorSpectrumFrame(elapsedTime: .infinity, magnitudesDB: [-10], binWidthHz: 1),
            MonitorSpectrumFrame(elapsedTime: -1, magnitudesDB: [-10], binWidthHz: 1),
            frame([]), frame([.nan]), frame([.infinity]), frame([-120], width: 0),
            frame([-120], width: .infinity), frame([-120, -120, -120], width: .greatestFiniteMagnitude)
        ] {
            check(MonitorSpectrogramRasterizer.makeColumn(frame: invalid) == nil,
                  "Invalid timestamps, magnitudes and frequency bounds never generate an image")
        }
        check(MonitorSpectrogramRasterizer.verticalFraction(for: .nan).isFinite
              && MonitorSpectrogramRasterizer.verticalFraction(for: -.infinity) == 1
              && MonitorSpectrogramRasterizer.verticalFraction(for: .infinity) == 0,
              "Invalid and out-of-range axis values cannot create nonfinite drawing coordinates")

        let column = MonitorSpectrogramColumn(elapsedTime: 4.25, image: silentImage)
        check(column.id == 4.25 && column.image === silentImage,
              "A stored column preserves its timeline identity and reuses the rendered image")
        func rgba(_ image: CGImage, x: Int, row: Int) -> [UInt8] {
            guard let data = image.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(data) else { return [] }
            return Array(UnsafeBufferPointer(start: bytes + row * image.bytesPerRow + x * 4, count: 4))
        }
        let toneImage = MonitorSpectrogramRasterizer.makeColumn(frame: singleFrame)!
        let imageColumns = [
            MonitorSpectrogramColumn(elapsedTime: 0.128, image: toneImage),
            MonitorSpectrogramColumn(elapsedTime: 0.228, image: silentImage),
            MonitorSpectrogramColumn(elapsedTime: 0.428, image: toneImage)
        ]
        let combined = MonitorSpectrogramRasterizer.makeImage(
            columns: imageColumns, timeRange: 0.028...0.528, pixelWidth: 10
        )!
        check(combined.width == 10 && combined.height == 512,
              "The visible time window is composed into a single bitmap")
        for row in [0, peakRow, 511] {
            check(rgba(combined, x: 0, row: row) == rgba(toneImage, x: 0, row: row)
                  && rgba(combined, x: 1, row: row) == rgba(toneImage, x: 0, row: row),
                  "Each hop fills its own pixel columns without flipping frequency rows")
            check(rgba(combined, x: 2, row: row) == silent[row]
                  && rgba(combined, x: 3, row: row) == silent[row],
                  "Adjacent columns preserve their independent amplitudes")
            check([4, 5, 8, 9].allSatisfy { rgba(combined, x: $0, row: row) == [0, 0, 0, 0] },
                  "Missing frames and future time remain transparent")
            check(rgba(combined, x: 6, row: row) == rgba(toneImage, x: 0, row: row)
                  && rgba(combined, x: 7, row: row) == rgba(toneImage, x: 0, row: row),
                  "A later tone never stretches across a capture gap")
        }
        let cropped = MonitorSpectrogramRasterizer.makeImage(
            columns: imageColumns, timeRange: 0.078...0.328, pixelWidth: 5
        )!
        check(rgba(cropped, x: 0, row: peakRow) == rgba(toneImage, x: 0, row: peakRow)
              && rgba(cropped, x: 1, row: peakRow) == silent[peakRow]
              && rgba(cropped, x: 2, row: peakRow) == silent[peakRow]
              && rgba(cropped, x: 3, row: peakRow) == [0, 0, 0, 0]
              && rgba(cropped, x: 4, row: peakRow) == [0, 0, 0, 0],
              "Scrolling clips partial hops and excludes columns beyond the visible window")
        check(MonitorSpectrogramRasterizer.makeImage(columns: [], timeRange: 0...1, pixelWidth: 0) == nil
              && MonitorSpectrogramRasterizer.makeImage(columns: [], timeRange: 0...1, pixelWidth: 4_097) == nil
              && MonitorSpectrogramRasterizer.makeImage(columns: [], timeRange: 1...1, pixelWidth: 10) == nil
              && MonitorSpectrogramRasterizer.makeImage(columns: [], timeRange: 0...(.infinity), pixelWidth: 10) == nil,
              "Invalid ranges and unbounded allocations are rejected")
        let emptyImage = MonitorSpectrogramRasterizer.makeImage(columns: [], timeRange: 0...1, pixelWidth: 10)!
        check(rgba(emptyImage, x: 5, row: peakRow) == [0, 0, 0, 0],
              "An empty window clears stale image content")
        print("Monitor spectrogram: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
