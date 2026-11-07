import AVFoundation
import CPitcheeCore
import CPitcheeHNR
import Foundation

/// Exercises the actual C++ analyzer, C JSON boundary and Swift decoder with
/// bundled ONNX models. The default script fixture is synthesized speech;
/// passing a WAV exercises an existing recording without accessing a microphone.
@main
enum HNRIntegrationTests {
    static func main() async throws {
        guard CommandLine.arguments.count == 4 else {
            throw TestError.invalidArguments
        }
        let modelDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let directory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        var checks = 0
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition {
                failures += 1
                print("FAIL: \(message)")
            }
        }

        // This public external-module API has no analyzer handle or F0 input.
        // Supplied VAD intervals below are explicit test fixtures, not detector
        // output. The HNR calculator itself never loads a model or accepts F0.
        let periodicPCM: [Float] = (0..<4_800).map { index in
            Float(0.2 * sin(2 * Double.pi * 200 * Double(index) / 16_000))
        }
        let allowedVAD = [pitchee_hnr_vad_segment_t(start_seconds: 0, end_seconds: 0.3)]
        let periodicHNR = try externalHNR(samples: periodicPCM, vadSegments: allowedVAD)
        check(periodicHNR.windowSeconds == 0.04 && periodicHNR.windows.count == 30,
              "standalone HNR uses its own 40 ms windows and 10 ms hop without a model")
        check(periodicHNR.hnrWindowCount > 0 && (periodicHNR.hnrDb ?? 0) > 20,
              "standalone HNR accepts VAD-allowed periodic PCM without an F0 confidence gate")
        let noVAD = try externalHNR(samples: periodicPCM, vadSegments: [])
        check(noVAD.windows.count == 30 && noVAD.windows.allSatisfy { $0.hnrDb == nil } &&
              noVAD.hnrWindowCount == 0 && noVAD.hnrDb == nil && noVAD.hnrStdDb == nil,
              "empty VAD intervals reject even strongly periodic PCM and propagate nil")
        let excluded = try externalHNR(samples: periodicPCM, vadSegments: [
            pitchee_hnr_vad_segment_t(start_seconds: 0.5, end_seconds: 1)
        ])
        check(excluded.hnrWindowCount == 0 && excluded.windows.allSatisfy { $0.hnrDb == nil },
              "VAD intervals outside PCM cannot admit strongly periodic windows")
        // With only 640 samples, clipped-window centers are 20, 25, 30, 35 ms.
        // This checks exact inclusion at start and exclusion at end, using the
        // actual clipped midpoint instead of a nominal full-window center.
        let boundary = try externalHNR(samples: Array(periodicPCM.prefix(640)), vadSegments: [
            pitchee_hnr_vad_segment_t(start_seconds: 0.025, end_seconds: 0.035)
        ])
        check(boundary.windows.map { $0.hnrDb != nil } == [false, true, true, false],
              "VAD gate uses clipped HNR midpoint with half-open source interval bounds")
        var noiseState: UInt32 = 0x12345678
        let noise: [Float] = (0..<640).map { _ in
            noiseState = 1_664_525 &* noiseState &+ 1_013_904_223
            return Float(Double(noiseState) / 4_294_967_296 - 0.5)
        }
        let gatedNoise = try externalHNR(samples: noise, vadSegments: [
            pitchee_hnr_vad_segment_t(start_seconds: 0.02, end_seconds: 0.025)
        ])
        check(gatedNoise.windows.count == 4 && gatedNoise.windows.allSatisfy { $0.hnrDb == nil } &&
              gatedNoise.hnrWindowCount == 0,
              "VAD allowance still requires reliable autocorrelation and rejects aperiodic PCM")
        let copiedValues = periodicHNR.windows.map(\.hnrDb)
        let silentHNR = try externalHNR(samples: [Float](repeating: 0, count: 640), vadSegments: allowedVAD)
        check(silentHNR.windows.count == 4 && silentHNR.windows.allSatisfy { $0.hnrDb == nil },
              "standalone silence preserves its own windows with nil HNR")
        check(silentHNR.hnrWindowCount == 0 && silentHNR.hnrDb == nil && silentHNR.hnrStdDb == nil,
              "standalone silence propagates nil aggregates")
        let emptyHNR = try externalHNR(samples: [], vadSegments: [])
        check(emptyHNR.windows.isEmpty && emptyHNR.hnrWindowCount == 0 &&
              emptyHNR.hnrDb == nil && emptyHNR.hnrStdDb == nil,
              "standalone empty PCM succeeds with no HNR windows or aggregates")
        check(periodicHNR.windows.map(\.hnrDb) == copiedValues,
              "synchronous HNR callback values remain owned after return and later calls")

        let sourceSegment = PitcheeAnalysisResult.Segment(
            startSeconds: 0, endSeconds: 0.3, speechStartSeconds: 0, speechEndSeconds: 0.3
        )
        let noSegments = try PitcheeHNR.analyze(
            samples: periodicPCM, sampleRate: 16_000, channels: 1, segments: []
        )
        check(noSegments == nil, "App leaves voiceQuality nil when VAD is empty")
        let silentQuality = try PitcheeHNR.analyze(
            samples: [Float](repeating: 0, count: 640), sampleRate: 16_000, channels: 1,
            segments: [sourceSegment]
        )
        check(silentQuality == nil, "App leaves voiceQuality nil when HNR has no valid windows")
        let quantized = periodicPCM.map { Float(max(-32_768, min(32_767, (Double($0) * 32_768).rounded())) / 32_768) }
        let quantizedHNR = try externalHNR(samples: quantized, vadSegments: allowedVAD)
        let appQuality = try PitcheeHNR.analyze(
            samples: periodicPCM, sampleRate: 16_000, channels: 1, segments: [sourceSegment]
        )
        check(nearlyEqual(appQuality?.hnrDb, quantizedHNR.hnrDb) &&
              nearlyEqual(appQuality?.hnrStdDb, quantizedHNR.hnrStdDb) &&
              appQuality?.hnrWindowCount == quantizedHNR.hnrWindowCount,
              "App HNR uses Core PCM16 quantization even for 16 kHz Float32 input")

        // Keep both recording entry points and the standalone API on identical
        // PCM. Leading silence makes source and concatenated-speech timelines
        // different. A 13-sample final tail tests clipped HNR bounds.
        var input = [Float](repeating: 0, count: 5_120)
        input.append(contentsOf: try readPCM(sourceURL))
        let paddedCount = ((input.count + 8_000 + 159) / 160) * 160 + 13
        input.append(contentsOf: repeatElement(Float.zero, count: paddedCount - input.count))
        let wavURL = directory.appendingPathComponent("hnr-fractional-window.wav")
        try writePCM16(input, to: wavURL)
        let samples = try readPCM(wavURL)
        let duration = Double(samples.count) / 16_000
        let analyzer = try PitcheeCoreAnalyzer(modelDirectory: modelDirectory)

        let wavResult = try await analyzer.analyze(wavFile: wavURL)
        validate(wavResult, sampleCount: samples.count, duration: duration, label: "WAV", check: check)
        // Reuse the actual existing VAD result, using its original source
        // coordinates. speechStart/EndSeconds are concatenated coordinates.
        let nativeVAD = wavResult.vad.segments.map {
            pitchee_hnr_vad_segment_t(start_seconds: $0.startSeconds, end_seconds: $0.endSeconds)
        }
        let standalone = try externalHNR(samples: samples, vadSegments: nativeVAD)
        let pcmResult = try await analyzer.analyze(samples: samples, sampleRate: 16_000, channels: 1)
        validate(pcmResult, sampleCount: samples.count, duration: duration, label: "PCM", check: check)
        if let wavQuality = wavResult.voiceQuality, let pcmQuality = pcmResult.voiceQuality {
            check(wavQuality.windows.count == pcmQuality.windows.count,
                  "WAV and PCM entry points emit the same window count")
            check(zip(wavQuality.windows, pcmQuality.windows).allSatisfy {
                nearlyEqual($0.hnrDb, $1.hnrDb)
            }, "WAV and PCM entry points preserve identical window HNR values and nils")
            check(nearlyEqual(wavQuality.hnrDb, pcmQuality.hnrDb),
                  "WAV and PCM entry points preserve the recording HNR mean")
            check(standalone.windows.count == wavQuality.windows.count &&
                  zip(standalone.windows, wavQuality.windows).allSatisfy {
                      $0.startSeconds == $1.startSeconds && $0.endSeconds == $1.endSeconds &&
                      nearlyEqual($0.hnrDb, $1.hnrDb)
                  }, "recording JSON matches standalone external-module HNR windows and nils")
            check(standalone.windowSeconds == wavQuality.windowSeconds &&
                  standalone.hnrWindowCount == wavQuality.hnrWindowCount &&
                  nearlyEqual(standalone.hnrDb, wavQuality.hnrDb) &&
                  nearlyEqual(standalone.hnrStdDb, wavQuality.hnrStdDb),
                  "recording JSON matches standalone external-module HNR aggregates")
        }

        // Device recordings retain the hardware sample rate. Check that the
        // App bridge keeps Core's preprocessing and both entry points aligned.
        let stereo = samples.flatMap { value in Array(repeating: value * 0.937, count: 6) }
        let stereoURL = directory.appendingPathComponent("hnr-stereo-48000.wav")
        try writePCM16(stereo, to: stereoURL, sampleRate: 48_000, channels: 2)
        let stereoPCM = stereo.map { Float(max(-32_768, min(32_767, (Double($0) * 32_768).rounded())) / 32_768) }
        let stereoWAVResult = try await analyzer.analyze(wavFile: stereoURL)
        let stereoPCMResult = try await analyzer.analyze(samples: stereoPCM, sampleRate: 48_000, channels: 2)
        check(stereoWAVResult.voiceQuality != nil && stereoPCMResult.voiceQuality != nil,
              "48 kHz stereo speech retains HNR")
        check(nearlyEqual(stereoWAVResult.voiceQuality?.hnrDb, stereoPCMResult.voiceQuality?.hnrDb) &&
              nearlyEqual(stereoWAVResult.voiceQuality?.hnrStdDb, stereoPCMResult.voiceQuality?.hnrStdDb) &&
              stereoWAVResult.voiceQuality?.hnrWindowCount == stereoPCMResult.voiceQuality?.hnrWindowCount,
              "48 kHz stereo WAV and PCM preserve HNR aggregates")
        check(stereoWAVResult.audio.sourceSampleRate == 48_000 && stereoWAVResult.audio.sourceChannels == 2,
              "App preserves source format metadata")

        // Use a real native payload, then remove only the v4 addition, as an
        // older recording would have been stored. This covers bridge decoding
        // as well as the hand-authored schema fixtures in the unit suite.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var legacy = try JSONSerialization.jsonObject(with: encoder.encode(wavResult)) as! [String: Any]
        legacy["schema_version"] = 3
        legacy.removeValue(forKey: "voice_quality")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let oldResult = try decoder.decode(
            PitcheeAnalysisResult.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        check(oldResult.schemaVersion == 3 && oldResult.voiceQuality == nil,
              "v3 payload decodes with voiceQuality nil")
        check(oldResult.f0.windows.count == wavResult.f0.windows.count &&
              oldResult.composite.finalScore == wavResult.composite.finalScore,
              "v3 decoding retains existing pitch and scoring fields")

        // Calls return complete frame arrays immediately. Repeated calls and a
        // reset exercise the existing synchronous callback context lifetime;
        // the realtime path does not request offline HNR calculations.
        try await analyzer.resetRealtimeF0()
        var frames: [PitcheeF0Frame] = []
        let tone: [Float] = (0..<12_800).map { index in
            let phase = 2 * Double.pi * 220 * Double(index) / 16_000
            return Float(0.2 * (sin(phase) + 0.5 * sin(2 * phase) + 0.25 * sin(3 * phase)))
        }
        for offset in stride(from: 0, to: tone.count, by: 1_024) {
            let chunk = Array(tone[offset..<min(offset + 1_024, tone.count)])
            frames += try await analyzer.processRealtimeF0(samples: chunk)
        }
        check(!frames.isEmpty, "realtime callbacks return frames")
        check(zip(frames, frames.dropFirst()).allSatisfy { $0.elapsedTime < $1.elapsedTime },
              "realtime callback timestamps remain ordered")
        check(frames.suffix(5).compactMap(\.pitchHz).contains { abs($0 - 220) < 5 },
              "realtime voice detection remains usable")
        let snapshot = frames.map(\.elapsedTime)
        try await analyzer.resetRealtimeF0()
        let resetFrames = try await analyzer.processRealtimeF0(samples: tone)
        check(!resetFrames.isEmpty && resetFrames.first!.elapsedTime < 0.55,
              "realtime reset starts a fresh timeline")
        check(frames.map(\.elapsedTime) == snapshot,
              "returned callback values remain valid after another native call")

        if let quality = wavResult.voiceQuality {
            print("HNR integration: schema=\(wavResult.schemaVersion), algorithm=\(quality.algorithm), " +
                  "windows=\(quality.windows.count), valid=\(quality.hnrWindowCount), " +
                  "windowSeconds=\(quality.windowSeconds), meanDb=\(quality.hnrDb.map(String.init(describing:)) ?? "nil")")
        }
        guard failures == 0 else { throw TestError.failed(failures, checks) }
        print("HNR integration: \(checks) checks passed (file-based audio; no microphone capture)")
    }

    private static func validate(
        _ result: PitcheeAnalysisResult,
        sampleCount: Int,
        duration: Double,
        label: String,
        check: (Bool, String) -> Void
    ) {
        check(result.schemaVersion == 3 || result.schemaVersion == 4, "\(label): native schema remains supported")
        check(result.voiceQuality != nil, "\(label): voiceQuality is present")
        guard let quality = result.voiceQuality else { return }
        check(quality.algorithm == "autocorr-praat-v1", "\(label): algorithm is fixed")
        check(quality.windowSeconds == 0.04 && quality.windowSeconds != result.f0.windowSeconds,
              "\(label): HNR owns its 40 ms window duration independently of F0")
        check(quality.windows.count == (sampleCount + 159) / 160,
              "\(label): HNR emits one window per 10 ms hop through the final sample")
        check(quality.windows.enumerated().allSatisfy { index, window in
            nearlyEqual(window.startSeconds, Double(index * 160) / 16_000) &&
            nearlyEqual(window.endSeconds, Double(min(index * 160 + 640, sampleCount)) / 16_000)
        }, "\(label): all HNR bounds follow its own 640-sample window and 160-sample hop")
        check(quality.windows.contains { $0.hnrDb == nil },
              "\(label): fixture exercises unreliable HNR windows")
        check(result.vad.segments.contains { $0.startSeconds != $0.speechStartSeconds },
              "\(label): VAD fixture distinguishes source and concatenated speech timelines")
        let outsideVAD = quality.windows.filter { window in
            let startSample = (window.startSeconds * 16_000).rounded()
            let endSample = (window.endSeconds * 16_000).rounded()
            let midpoint = (startSample + endSample) / 32_000
            return !result.vad.segments.contains {
                $0.startSeconds <= midpoint && midpoint < $0.endSeconds
            }
        }
        check(!outsideVAD.isEmpty && outsideVAD.allSatisfy { $0.hnrDb == nil },
              "\(label): windows outside retained source VAD intervals always have nil HNR")
        let values = quality.windows.compactMap(\.hnrDb)
        check(!values.isEmpty && values.allSatisfy(\.isFinite),
              "\(label): speech has finite valid HNR windows")
        check(quality.hnrWindowCount == values.count,
              "\(label): recording count includes only non-nil HNR windows")
        if values.isEmpty {
            check(quality.hnrDb == nil && quality.hnrStdDb == nil,
                  "\(label): empty HNR aggregates remain nil")
        } else {
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
            check(nearlyEqual(quality.hnrDb, mean), "\(label): recording HNR is the window mean")
            check(nearlyEqual(quality.hnrStdDb, sqrt(variance)),
                  "\(label): recording HNR stores the population standard deviation")
        }
        check(nearlyEqual(quality.windows.last?.endSeconds, duration),
              "\(label): fractional final window ends at the actual audio duration")
        if let tail = quality.windows.last {
            check(nearlyEqual(tail.endSeconds - tail.startSeconds, 13.0 / 16_000),
                  "\(label): final window is not expanded or padded")
            check(tail.hnrDb == nil, "\(label): short final PCM propagates nil HNR")
        }
    }

    private static func nearlyEqual(_ left: Double?, _ right: Double?, tolerance: Double = 1e-8) -> Bool {
        switch (left, right) {
        case (nil, nil): true
        case let (left?, right?): abs(left - right) <= tolerance
        default: false
        }
    }

    private struct ExternalHNR {
        let windowSeconds: Double
        let hnrWindowCount: Int
        let hnrDb: Double?
        let hnrStdDb: Double?
        let windows: [PitcheeAnalysisResult.HNRWindow]
    }

    private static func externalHNR(
        samples: [Float],
        vadSegments: [pitchee_hnr_vad_segment_t]
    ) throws -> ExternalHNR {
        var windows: [PitcheeAnalysisResult.HNRWindow] = []
        windows.reserveCapacity((samples.count + 159) / 160)
        var summary = pitchee_hnr_summary_t()
        // The C API borrows PCM, VAD intervals and context until it returns.
        // Copy each borrowed stack frame immediately; no frame/context pointer
        // escapes either withUnsafe scope or is retained in the returned value.
        let status = withUnsafeMutablePointer(to: &windows) { output in
            samples.withUnsafeBufferPointer { buffer in
                vadSegments.withUnsafeBufferPointer { segments in
                    pitchee_hnr_analyze(
                        buffer.baseAddress, buffer.count, segments.baseAddress, segments.count,
                        { frame, context in
                            guard let frame, let context else { return }
                            let value = frame.pointee
                            context.assumingMemoryBound(to: [PitcheeAnalysisResult.HNRWindow].self).pointee.append(
                                PitcheeAnalysisResult.HNRWindow(
                                    startSeconds: value.start_seconds,
                                    endSeconds: value.end_seconds,
                                    hnrDb: value.has_hnr == 0 ? nil : value.hnr_db
                                )
                            )
                        },
                        UnsafeMutableRawPointer(output), &summary
                    )
                }
            }
        }
        guard status == PITCHEE_SUCCESS else { throw TestError.nativeHNR(Int(status.rawValue)) }
        return ExternalHNR(
            windowSeconds: summary.window_seconds,
            hnrWindowCount: Int(summary.hnr_window_count),
            hnrDb: summary.has_hnr == 0 ? nil : summary.hnr_db,
            hnrStdDb: summary.has_hnr == 0 ? nil : summary.hnr_std_db,
            windows: windows
        )
    }

    private static func readPCM(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == 16_000,
              file.processingFormat.channelCount == 1,
              file.length > 0, file.length <= Int64(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                           frameCapacity: AVAudioFrameCount(file.length)) else {
            throw TestError.invalidPCM
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw TestError.invalidPCM }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private static func writePCM16(
        _ samples: [Float], to url: URL, sampleRate: Double = 16_000, channels: UInt32 = 1
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                           frameCapacity: AVAudioFrameCount(samples.count / Int(channels))),
              let channelData = buffer.floatChannelData else { throw TestError.invalidPCM }
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            for channel in 0..<Int(channels) {
                channelData[channel][frame] = samples[frame * Int(channels) + channel]
            }
        }
        try file.write(from: buffer)
    }

    private enum TestError: Error {
        case invalidArguments
        case invalidPCM
        case nativeHNR(Int)
        case failed(Int, Int)
    }
}
