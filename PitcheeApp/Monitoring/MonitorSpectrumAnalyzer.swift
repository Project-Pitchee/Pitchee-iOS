//
//  MonitorSpectrumAnalyzer.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import Accelerate
import Foundation

/// A streaming, amplitude-calibrated spectrum for contiguous 16 kHz mono PCM.
/// Keep one instance per capture run so window overlap survives tap boundaries.
nonisolated final class MonitorSpectrumAnalyzer {
    static let sampleRate: Double = 16_000
    static let windowSize = 2_048
    static let hopSize = 1_600
    static let minimumDecibels: Float = -120

    private let fftSetup: FFTSetup
    private let log2WindowSize: vDSP_Length = 11
    private let window: [Float]
    private let windowSum: Float
    // Fixed-capacity overlap ring: every input sample is copied once. Advancing
    // a window changes indices instead of moving retained PCM with removeFirst.
    private var pendingSamples = [Float](repeating: 0, count: windowSize)
    private var pendingStart = 0
    private var pendingCount = 0
    private var windowStartSample: Int64 = 0
    private var windowedSamples = [Float](repeating: 0, count: windowSize)
    private var real = [Float](repeating: 0, count: windowSize / 2)
    private var imaginary = [Float](repeating: 0, count: windowSize / 2)

    init() throws {
        guard let setup = vDSP_create_fftsetup(log2WindowSize, FFTRadix(kFFTRadix2)) else {
            throw MonitorSpectrumAnalyzerError.allocationFailed
        }
        fftSetup = setup
        var coefficients = [Float](repeating: 0, count: Self.windowSize)
        vDSP_hann_window(&coefficients, vDSP_Length(Self.windowSize), Int32(vDSP_HANN_NORM))
        window = coefficients
        windowSum = coefficients.reduce(0, +)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Returns 1,025 bins including DC and Nyquist, spaced 7.8125 Hz apart.
    /// Time identifies the end of the FFT window; partial windows wait for more
    /// samples rather than being padded, so batching never changes the result.
    func process(_ samples: [Float]) -> [MonitorSpectrumFrame] {
        guard !samples.isEmpty else { return [] }
        var consumed = 0
        var frames: [MonitorSpectrumFrame] = []
        frames.reserveCapacity((pendingCount + samples.count) / Self.hopSize)

        samples.withUnsafeBufferPointer { source in
            guard let sourceBase = source.baseAddress else { return }
            while consumed < samples.count {
                let writeIndex = (pendingStart + pendingCount) % Self.windowSize
                let count = min(samples.count - consumed,
                                Self.windowSize - pendingCount, Self.windowSize - writeIndex)
                pendingSamples.withUnsafeMutableBufferPointer { destination in
                    destination.baseAddress?.advanced(by: writeIndex)
                        .update(from: sourceBase + consumed, count: count)
                }
                consumed += count
                pendingCount += count
                guard pendingCount == Self.windowSize else { continue }

                applyWindow()
                frames.append(MonitorSpectrumFrame(
                    elapsedTime: Double(windowStartSample + Int64(Self.windowSize)) / Self.sampleRate,
                    magnitudesDB: transformWindow(),
                    binWidthHz: Self.sampleRate / Double(Self.windowSize)
                ))
                pendingStart = (pendingStart + Self.hopSize) % Self.windowSize
                pendingCount -= Self.hopSize
                windowStartSample += Int64(Self.hopSize)
            }
        }
        return frames
    }

    private func applyWindow() {
        pendingSamples.withUnsafeBufferPointer { source in
            window.withUnsafeBufferPointer { coefficients in
                windowedSamples.withUnsafeMutableBufferPointer { destination in
                    guard let source = source.baseAddress,
                          let coefficients = coefficients.baseAddress,
                          let destination = destination.baseAddress else { return }
                    let firstCount = Self.windowSize - pendingStart
                    vDSP_vmul(source + pendingStart, 1, coefficients, 1,
                              destination, 1, vDSP_Length(firstCount))
                    if pendingStart > 0 {
                        vDSP_vmul(source, 1, coefficients + firstCount, 1,
                                  destination + firstCount, 1, vDSP_Length(pendingStart))
                    }
                }
            }
        }
    }

    private func transformWindow() -> [Float] {
        let halfSize = Self.windowSize / 2
        var decibels = [Float](repeating: Self.minimumDecibels, count: halfSize + 1)
        var absoluteSum: Float = 0
        vDSP_svemg(windowedSamples, 1, &absoluteSum, vDSP_Length(Self.windowSize))
        guard absoluteSum.isFinite else { return decibels }
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!
                )
                windowedSamples.withUnsafeBytes { source in
                    vDSP_ctoz(
                        source.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                        &split, 1, vDSP_Length(halfSize)
                    )
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2WindowSize, FFTDirection(FFT_FORWARD))

                // vDSP's real FFT returns twice the conventional DFT. Hann's
                // coherent gain is its coefficient sum; DC/Nyquist are packed
                // into bin zero and do not receive the interior-bin doubling.
                decibels.withUnsafeMutableBufferPointer { output in
                    guard let values = output.baseAddress else { return }
                    vDSP_zvabs(&split, 1, values, 1, vDSP_Length(halfSize))
                    values[0] = abs(split.realp[0]) / 2
                    values[halfSize] = abs(split.imagp[0]) / 2
                    var reference = windowSum
                    var floorAmplitude = windowSum * powf(10, Self.minimumDecibels / 20)
                    let length = vDSP_Length(halfSize + 1)
                    // Threshold before log conversion so zero stays finite.
                    vDSP_vthr(values, 1, &floorAmplitude, values, 1, length)
                    vDSP_vdbcon(values, 1, &reference, values, 1, length, 1)
                    var floorDB = Self.minimumDecibels
                    vDSP_vthr(values, 1, &floorDB, values, 1, length)
                }
            }
        }
        return decibels
    }
}

nonisolated enum MonitorSpectrumAnalyzerError: Error {
    case allocationFailed
}
