//
//  RecordingStatistics.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/19.
//

import Accelerate
import AVFoundation
import Foundation

nonisolated struct RecordingPitchStatistics: Sendable {
    let averageHz: Double?
    let medianHz: Double?
    let high95Hz: Double?
    let low5Hz: Double?
    let veryHighPercentage: Double
    let femininePercentage: Double
    let androgynousPercentage: Double
    let masculinePercentage: Double
    let veryLowPercentage: Double

    init(pitch: PitcheeAnalysisResult.Pitch) {
        let values = pitch.windows
            .compactMap(\.f0Hz)
            .filter { $0.isFinite && $0 > 0 }
            .sorted()

        averageHz = pitch.meanHz.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        medianHz = RecordingStatisticsMath.percentile(0.50, in: values)
        high95Hz = RecordingStatisticsMath.percentile(0.95, in: values)
        low5Hz = RecordingStatisticsMath.percentile(0.05, in: values)

        let count = Double(values.count)
        func percentage(where predicate: (Double) -> Bool) -> Double {
            guard count > 0 else { return 0 }
            return Double(values.filter(predicate).count) / count
        }

        // Non-overlapping conversational voice-pitch bands. These describe
        // frequency only and are not a statement about the speaker's identity.
        veryHighPercentage = percentage { $0 >= 255 }
        femininePercentage = percentage { $0 >= 165 && $0 < 255 }
        androgynousPercentage = percentage { $0 >= 145 && $0 < 165 }
        masculinePercentage = percentage { $0 >= 85 && $0 < 145 }
        veryLowPercentage = percentage { $0 < 85 }
    }
}

nonisolated enum RecordingStatisticsMath {
    static func percentile(_ fraction: Double, in values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        guard values.count > 1 else { return values[0] }

        let position = fraction * Double(values.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else { return values[lowerIndex] }

        let remainder = position - Double(lowerIndex)
        return values[lowerIndex]
            + (values[upperIndex] - values[lowerIndex]) * remainder
    }
}

nonisolated struct RecordingVolumeStatistics: Sendable {
    let environmentDBFS: Double?
    let averageDBFS: Double?
    let medianDBFS: Double?
    let high95DBFS: Double?
    let low5DBFS: Double?
    let windows: [RecordingVolumeWindow]
    var clippedSampleFraction: Double? = nil

    var measuredBackgroundDBFS: Double? {
        RecordingStatisticsMath.percentile(0.5, in: windows.compactMap(\.backgroundDBFS).sorted())
    }
}

/// A time-aligned loudness sample used by the export report. Voice and
/// background values are kept separate so the report can show both curves on
/// the same time axis without implying that silence is a voice measurement.
nonisolated struct RecordingVolumeWindow: Sendable {
    let centerSeconds: Double
    let voiceDBFS: Double?
    let backgroundDBFS: Double?
}

nonisolated enum RecordingVolumeAnalyzer {
    private static let windowSeconds = 0.05
    private static let minimumDBFS = -120.0

    static func analyze(
        wavFile: URL,
        speechSegments: [PitcheeAnalysisResult.Segment]
    ) throws -> RecordingVolumeStatistics {
        let file = try AVAudioFile(forReading: wavFile, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let framesPerWindow = AVAudioFrameCount(max(1, Int(format.sampleRate * windowSeconds)))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: framesPerWindow
        ) else {
            throw RecordingVolumeAnalyzerError.bufferCreationFailed
        }

        var speechLevels: [Double] = []
        var environmentLevels: [Double] = []
        var windows: [RecordingVolumeWindow] = []
        var sampleCount = 0
        var clippedCount = 0

        while file.framePosition < file.length {
            let startFrame = file.framePosition
            try file.read(into: buffer, frameCount: framesPerWindow)
            guard buffer.frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData, format.channelCount > 0 else {
                throw RecordingVolumeAnalyzerError.unsupportedAudioFormat
            }
            let samples = (0..<Int(buffer.frameLength)).map { frame in
                (0..<Int(format.channelCount)).reduce(Float(0)) { $0 + channels[$1][frame] } / Float(format.channelCount)
            }
            // Check each input channel before downmixing: opposite-polarity
            // clipped channels must not cancel each other out in the detector.
            if let channels = buffer.floatChannelData {
                let frameCount = Int(buffer.frameLength)
                let channelCount = Int(format.channelCount)
                for channel in 0..<channelCount {
                    for frame in 0..<frameCount {
                        let value = format.isInterleaved ? channels[0][frame * channelCount + channel] : channels[channel][frame]
                        sampleCount += 1
                        if abs(value) >= 0.999 { clippedCount += 1 }
                    }
                }
            }

            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
            let level = max(
                minimumDBFS,
                min(0, 20 * log10(Double(max(rms, 0.000_001))))
            )
            let centerSeconds = (
                Double(startFrame) + Double(buffer.frameLength) / 2
            ) / format.sampleRate
            let containsSpeech = speechSegments.contains {
                centerSeconds >= $0.startSeconds && centerSeconds <= $0.endSeconds
            }

            if containsSpeech {
                speechLevels.append(level)
                windows.append(RecordingVolumeWindow(
                    centerSeconds: centerSeconds,
                    voiceDBFS: level,
                    backgroundDBFS: nil
                ))
            } else {
                environmentLevels.append(level)
                windows.append(RecordingVolumeWindow(
                    centerSeconds: centerSeconds,
                    voiceDBFS: nil,
                    backgroundDBFS: level
                ))
            }
        }

        let sortedSpeechLevels = speechLevels.sorted()
        let sortedEnvironmentLevels = environmentLevels.sorted()
        // A continuous utterance may leave no clean non-speech window. In that
        // case the quietest voice window is the best available floor estimate.
        let environment = RecordingStatisticsMath.percentile(0.50, in: sortedEnvironmentLevels)
            ?? RecordingStatisticsMath.percentile(0.05, in: sortedSpeechLevels)

        return RecordingVolumeStatistics(
            environmentDBFS: environment,
            averageDBFS: sortedSpeechLevels.isEmpty
                ? nil
                : sortedSpeechLevels.reduce(0, +) / Double(sortedSpeechLevels.count),
            medianDBFS: RecordingStatisticsMath.percentile(0.50, in: sortedSpeechLevels),
            high95DBFS: RecordingStatisticsMath.percentile(0.95, in: sortedSpeechLevels),
            low5DBFS: RecordingStatisticsMath.percentile(0.05, in: sortedSpeechLevels),
            windows: windows,
            clippedSampleFraction: sampleCount > 0 ? Double(clippedCount) / Double(sampleCount) : nil
        )
    }
}

nonisolated enum RecordingVolumeAnalyzerError: Error {
    case bufferCreationFailed
    case unsupportedAudioFormat
}
