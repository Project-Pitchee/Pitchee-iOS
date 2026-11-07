import CPitcheeCore
import CPitcheeHNR
import Foundation

nonisolated enum PitcheeHNR {
    static func analyze(
        samples: [Float], sampleRate: Int32, channels: Int32,
        segments: [PitcheeAnalysisResult.Segment]
    ) throws -> PitcheeAnalysisResult.VoiceQuality? {
        try analyze(segments: segments) { vad, count, callback, context, summary, error, capacity in
            samples.withUnsafeBufferPointer { buffer in
                pitchee_app_hnr_analyze_pcm(
                    buffer.baseAddress, buffer.count, sampleRate, channels,
                    vad, count, callback, context, summary, error, capacity
                )
            }
        }
    }

    static func analyze(
        wavFile: URL, segments: [PitcheeAnalysisResult.Segment]
    ) throws -> PitcheeAnalysisResult.VoiceQuality? {
        try analyze(segments: segments) { vad, count, callback, context, summary, error, capacity in
            pitchee_app_hnr_analyze_wav(wavFile.path, vad, count, callback, context, summary, error, capacity)
        }
    }

    private static func analyze(
        segments: [PitcheeAnalysisResult.Segment],
        call: (
            UnsafePointer<pitchee_hnr_vad_segment_t>?, Int, pitchee_hnr_window_callback_t?,
            UnsafeMutableRawPointer?, UnsafeMutablePointer<pitchee_hnr_summary_t>?,
            UnsafeMutablePointer<CChar>?, Int
        ) -> pitchee_status_t
    ) throws -> PitcheeAnalysisResult.VoiceQuality? {
        guard !segments.isEmpty else { return nil }
        // HNR uses the original recording timeline, not concatenated speech coordinates.
        let vad = segments.map {
            pitchee_hnr_vad_segment_t(start_seconds: $0.startSeconds, end_seconds: $0.endSeconds)
        }
        var windows: [PitcheeAnalysisResult.HNRWindow] = []
        var summary = pitchee_hnr_summary_t()
        var errorBuffer = [CChar](repeating: 0, count: 1_024)
        // Core invokes callbacks synchronously and retains no borrowed pointers.
        let status = withUnsafeMutablePointer(to: &windows) { output in
            vad.withUnsafeBufferPointer { buffer in
                call(
                    buffer.baseAddress, buffer.count,
                    { frame, context in
                        guard let frame, let context else { return }
                        let value = frame.pointee
                        context.assumingMemoryBound(to: [PitcheeAnalysisResult.HNRWindow].self).pointee.append(
                            .init(startSeconds: value.start_seconds, endSeconds: value.end_seconds,
                                  hnrDb: value.has_hnr == 0 ? nil : value.hnr_db)
                        )
                    },
                    UnsafeMutableRawPointer(output), &summary, &errorBuffer, errorBuffer.count
                )
            }
        }
        guard status == PITCHEE_SUCCESS else {
            let message = String(decoding: errorBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            throw PitcheeCoreError(status: status, message: message)
        }
        guard summary.has_hnr != 0, summary.hnr_window_count > 0 else { return nil }
        return .init(
            algorithm: "autocorr-praat-v1", hnrDb: summary.hnr_db,
            hnrWindowCount: Int(summary.hnr_window_count), hnrStdDb: summary.hnr_std_db,
            windowSeconds: summary.window_seconds, windows: windows
        )
    }
}
