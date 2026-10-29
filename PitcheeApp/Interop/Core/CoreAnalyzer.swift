//
//  CoreAnalyzer.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/13.
//

import CPitcheeCore
import Foundation

public enum PitcheeScoreProfile: Sendable {
    case feminization
    case masculinization

    nonisolated fileprivate var cValue: pitchee_score_profile_t {
        switch self {
        case .feminization: PITCHEE_SCORE_PROFILE_FEMINIZATION
        case .masculinization: PITCHEE_SCORE_PROFILE_MASCULINIZATION
        }
    }
}

/// Owns one native analyzer and serializes access to its C++ inference sessions.
public actor PitcheeCoreAnalyzer {
    private let resources: NativeAnalyzerResources
    private let decoder: JSONDecoder

    init(modelDirectory: URL? = nil, settings: AnalyzerSettings = .current) throws {
        let resolvedModelDirectory = try modelDirectory ?? PitcheeCore.bundledModelDirectory()
        var errorBuffer = [CChar](repeating: 0, count: 1_024)
        var createdHandle: OpaquePointer?

        let status = pitchee_analyzer_create(
            resolvedModelDirectory.path,
            Int32(settings.threads),
            1,
            Float(settings.minF0Hz),
            Float(settings.maxF0Hz),
            Float(settings.minConfidence),
            &createdHandle,
            &errorBuffer,
            errorBuffer.count
        )
        guard status == PITCHEE_SUCCESS, let createdHandle else {
            throw PitcheeCoreError(
                status: status,
                message: Self.errorMessage(errorBuffer)
            )
        }

        resources = NativeAnalyzerResources(handle: createdHandle)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// Starts a new microphone timeline while reusing the loaded SwiftF0 model.
    public func resetRealtimeF0() throws {
        try Task.checkCancellation()
        if let realtimeF0 = resources.realtimeF0 {
            pitchee_realtime_f0_reset(realtimeF0)
            return
        }
        let handle = resources.handle

        var stream: OpaquePointer?
        var errorBuffer = [CChar](repeating: 0, count: 1_024)
        let status = pitchee_realtime_f0_create(
            handle, 0, 0, &stream, &errorBuffer, errorBuffer.count
        )
        guard status == PITCHEE_SUCCESS, let stream else {
            throw PitcheeCoreError(status: status, message: Self.errorMessage(errorBuffer))
        }
        resources.realtimeF0 = stream
    }

    /// Consumes contiguous 16 kHz mono Float32 PCM. Core owns F0 estimation,
    /// voicing decisions and timestamps; all native inference stays serialized.
    /// The independent HNR module is used only by completed-recording analysis.
    public func processRealtimeF0(samples: [Float]) throws -> [PitcheeF0Frame] {
        try Task.checkCancellation()
        guard let realtimeF0 = resources.realtimeF0 else {
            throw PitcheeCoreError(message: "The realtime F0 stream has not been started.")
        }
        var frames: [PitcheeF0Frame] = []
        var errorBuffer = [CChar](repeating: 0, count: 1_024)
        // The C API invokes every callback synchronously before returning and
        // retains neither context nor PCM. Both borrows stay within this scope;
        // copy the callback's stack-backed frame before it returns as well.
        let status = withUnsafeMutablePointer(to: &frames) { output in
            samples.withUnsafeBufferPointer { buffer in
                pitchee_realtime_f0_process(
                    realtimeF0, buffer.baseAddress, buffer.count,
                    { frame, context in
                        guard let frame, let context else { return }
                        let value = frame.pointee
                        context.assumingMemoryBound(to: [PitcheeF0Frame].self).pointee.append(
                            PitcheeF0Frame(
                                elapsedTime: value.timestamp_seconds,
                                pitchHz: value.voiced == 0 ? nil : Double(value.f0_hz)
                            )
                        )
                    },
                    UnsafeMutableRawPointer(output),
                    &errorBuffer, errorBuffer.count
                )
            }
        }
        guard status == PITCHEE_SUCCESS else {
            throw PitcheeCoreError(status: status, message: Self.errorMessage(errorBuffer))
        }
        return frames
    }

    public func analyze(
        samples: [Float],
        sampleRate: Int32,
        channels: Int32,
        scoreProfile: PitcheeScoreProfile = .feminization
    ) throws -> PitcheeAnalysisResult {
        let handle = resources.handle

        var output: UnsafeMutablePointer<CChar>?
        var errorBuffer = [CChar](repeating: 0, count: 1_024)
        let status = samples.withUnsafeBufferPointer { buffer in
            pitchee_analyze_pcm(
                handle,
                buffer.baseAddress,
                buffer.count,
                sampleRate,
                channels,
                scoreProfile.cValue,
                nil,
                nil,
                &output,
                &errorBuffer,
                errorBuffer.count
            )
        }

        return try decodeOutput(
            status: status,
            output: output,
            errorMessage: Self.errorMessage(errorBuffer)
        )
    }

    public func analyze(
        wavFile: URL,
        scoreProfile: PitcheeScoreProfile = .feminization
    ) throws -> PitcheeAnalysisResult {
        let handle = resources.handle

        var output: UnsafeMutablePointer<CChar>?
        var errorBuffer = [CChar](repeating: 0, count: 1_024)
        let status = pitchee_analyze_wav_file(
            handle,
            wavFile.path,
            scoreProfile.cValue,
            nil,
            nil,
            &output,
            &errorBuffer,
            errorBuffer.count
        )

        return try decodeOutput(
            status: status,
            output: output,
            errorMessage: Self.errorMessage(errorBuffer)
        )
    }

    nonisolated private static func errorMessage(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func decodeOutput(
        status: pitchee_status_t,
        output: UnsafeMutablePointer<CChar>?,
        errorMessage: String
    ) throws -> PitcheeAnalysisResult {
        guard status == PITCHEE_SUCCESS, let output else {
            throw PitcheeCoreError(status: status, message: errorMessage)
        }
        defer { pitchee_string_free(output) }

        let json = String(cString: output)
        let data = Data(json.utf8)
        do {
            // Schema v4 carries the external HNR module's independent windows,
            // gated by the recording's existing VAD intervals. Preserve nils
            // and timestamps; v3 omits the section and yields voiceQuality nil.
            return try decoder.decode(PitcheeAnalysisResult.self, from: data)
        } catch {
            throw PitcheeCoreError(
                message: "Unable to decode analysis schema: \(error)"
            )
        }
    }
}

nonisolated public struct PitcheeF0Frame: Sendable {
    public let elapsedTime: TimeInterval
    public let pitchHz: Double?
}

/// Actor-confined ownership. This object never escapes PitcheeCoreAnalyzer;
/// regular class destruction can release the non-Sendable C pointers without
/// accessing actor-isolated state from the actor's nonisolated deinitializer.
nonisolated private final class NativeAnalyzerResources {
    let handle: OpaquePointer
    var realtimeF0: OpaquePointer?

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        // The realtime stream borrows the analyzer's model, so release it first.
        if let realtimeF0 { pitchee_realtime_f0_destroy(realtimeF0) }
        pitchee_analyzer_destroy(handle)
    }
}
