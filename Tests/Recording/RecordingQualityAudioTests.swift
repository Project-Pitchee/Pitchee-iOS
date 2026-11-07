//
//  RecordingQualityAudioTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import AVFoundation
import Foundation

@main
enum RecordingQualityAudioTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func write(_ name: String, channels: [[Float]]) throws -> URL {
            let url = directory.appendingPathComponent(name).appendingPathExtension("wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: AVAudioChannelCount(channels.count))!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(channels[0].count))!
            buffer.frameLength = buffer.frameCapacity
            for (index, channel) in channels.enumerated() {
                for (frame, value) in channel.enumerated() { buffer.floatChannelData![index][frame] = value }
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        }
        let speech = PitcheeAnalysisResult.Segment(startSeconds: 0, endSeconds: 1, speechStartSeconds: 0, speechEndSeconds: 1)
        let angularStep = 2.0 * Double.pi * 200.0 / 16000.0
        let tone: [Float] = (0..<16000).map { frame in Float(0.1 * sin(Double(frame) * angularStep)) }
        let normal = try write("normal", channels: [tone + Array(repeating: 0.001, count: 16000)])
        let levels = try RecordingVolumeAnalyzer.analyze(wavFile: normal, speechSegments: [speech])
        precondition(abs(levels.medianDBFS! + 23.0103) < 0.02, "Known sine-wave RMS")
        precondition(abs(levels.measuredBackgroundDBFS! + 60) < 0.02, "Actual non-speech windows provide background level")
        precondition(levels.clippedSampleFraction == 0, "Unclipped input")
        let continuous = try write("continuous", channels: [tone])
        let noBackground = try RecordingVolumeAnalyzer.analyze(wavFile: continuous, speechSegments: [speech])
        precondition(noBackground.measuredBackgroundDBFS == nil && noBackground.environmentDBFS != nil,
                     "Quietest voice fallback must never be treated as measured background")
        let clipped = try write("stereo-clipped", channels: [Array(repeating: 1, count: 16000), Array(repeating: -1, count: 16000)])
        let clipLevels = try RecordingVolumeAnalyzer.analyze(wavFile: clipped, speechSegments: [speech])
        precondition(clipLevels.clippedSampleFraction == 1, "Opposite-polarity clipped channels cannot cancel the clipping detector")
        print("Recording quality audio: 5 checks passed")
    }
}
