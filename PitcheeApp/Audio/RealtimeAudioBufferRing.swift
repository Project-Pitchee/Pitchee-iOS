import AVFoundation
import Foundation
import CPitcheeAudioAtomics

/// One serialized audio tap produces PCM; one background worker consumes it.
/// All sample storage, descriptors, and the consumer's PCM buffer are allocated
/// before installing the tap. The producer only uses atomics and bounded copies:
/// it never locks, allocates a PCM buffer, dispatches work, or invokes a handler.
///
/// Release/acquire publication protects both the descriptors and their samples.
/// A slot remains reserved until releaseBuffer(), including asynchronous work
/// and UI delivery. Closing admission does not discard an in-flight producer:
/// isDrained becomes true only after its final publication has been consumed.
nonisolated final class RealtimeAudioBufferRing: @unchecked Sendable {
    enum Failure: UInt64 { case overrun = 1, invalidBuffer = 2 }

    private struct Descriptor {
        var offset = 0
        var frameCount = 0
    }

    private let maximumFrameCount: Int
    private let maximumBufferCount: Int
    private let channelCount: Int
    private let interleaved: Bool
    private let samples: UnsafeMutablePointer<Float>
    private let descriptors: UnsafeMutablePointer<Descriptor>
    private let consumerBuffer: AVAudioPCMBuffer
    // Bit 0: a producer is copying; bit 1: admission is permanently closed.
    private let admission: AudioCaptureAtomicUInt64
    private let failureCode: AudioCaptureAtomicUInt64
    private let publishedSequence: AudioCaptureAtomicUInt64
    private let releasedSequence: AudioCaptureAtomicUInt64
    private let admittedFrames: AudioCaptureAtomicUInt64
    private let releasedFrames: AudioCaptureAtomicUInt64
    // Producer-only cursors; protected from re-entry by admission's busy bit.
    private var writeSequence: UInt64 = 0
    private var writeFrames: UInt64 = 0
    // Consumer-only cursors.
    private var readSequence: UInt64 = 0
    private var readFrames: UInt64 = 0
    private var activeFrameCount = 0

    init(format: AVAudioFormat, maximumFrameCount: Int, maximumBufferCount: Int = 128) throws {
        let channels = Int(format.channelCount)
        guard format.commonFormat == .pcmFormatFloat32,
              format.sampleRate.isFinite, format.sampleRate > 0,
              channels > 0, maximumFrameCount > 0,
              maximumFrameCount <= Int(UInt32.max), maximumBufferCount > 0,
              channels <= 32, maximumFrameCount <= 768_000,
              let outputFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate,
                                              channels: format.channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                           frameCapacity: AVAudioFrameCount(maximumFrameCount)) else {
            throw LivePitchAudioCaptureError.inputUnavailable
        }
        admission = try AudioCaptureAtomicUInt64(0)
        failureCode = try AudioCaptureAtomicUInt64(0)
        publishedSequence = try AudioCaptureAtomicUInt64(0)
        releasedSequence = try AudioCaptureAtomicUInt64(0)
        admittedFrames = try AudioCaptureAtomicUInt64(0)
        releasedFrames = try AudioCaptureAtomicUInt64(0)
        self.maximumFrameCount = maximumFrameCount
        self.maximumBufferCount = maximumBufferCount
        channelCount = channels
        interleaved = format.isInterleaved
        consumerBuffer = buffer
        samples = .allocate(capacity: maximumFrameCount * channels)
        samples.initialize(repeating: 0, count: maximumFrameCount * channels)
        descriptors = .allocate(capacity: maximumBufferCount)
        descriptors.initialize(repeating: Descriptor(), count: maximumBufferCount)
    }

    deinit {
        samples.deinitialize(count: maximumFrameCount * channelCount)
        samples.deallocate()
        descriptors.deinitialize(count: maximumBufferCount)
        descriptors.deallocate()
    }

    /// Realtime producer entry point. A concurrent/reentrant producer is a
    /// terminal overrun, never a silent gap followed by a compressed clock.
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        let original = admission.compareExchangeAcqRel(expected: 0, desired: 1)
        guard original == 0 else {
            if original == 1 { fail(.overrun) }
            return
        }
        defer { admission.bitwiseAndRelease(~UInt64(1)) }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let retainedFrames = writeFrames &- releasedFrames.loadAcquire()
        guard frameCount <= maximumFrameCount,
              retainedFrames <= UInt64(maximumFrameCount - frameCount),
              writeSequence &- releasedSequence.loadAcquire() < UInt64(maximumBufferCount) else {
            fail(.overrun)
            return
        }

        // AVAudioEngine supplies the Float32 format checked before installing
        // its tap. Inspect its borrowed AudioBufferList directly, without an
        // AVAudioPCMBuffer allocation or an AVAudioFormat getter on this path.
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        guard source.count == (interleaved ? 1 : channelCount) else {
            fail(.invalidBuffer)
            return
        }
        let sourceChannels = interleaved ? channelCount : 1
        let byteCount = frameCount * sourceChannels * MemoryLayout<Float>.stride
        for item in source {
            guard item.mData != nil, Int(item.mNumberChannels) == sourceChannels,
                  Int(item.mDataByteSize) >= byteCount else {
                fail(.invalidBuffer)
                return
            }
        }
        admittedFrames.storeRelease(writeFrames &+ UInt64(frameCount))
        let offset = Int(writeFrames % UInt64(maximumFrameCount))
        let firstCount = min(frameCount, maximumFrameCount - offset)
        for channel in 0..<channelCount {
            // The complete list was validated above. No source pointer or
            // AVAudioPCMBuffer escapes this call; only owned sample bytes do.
            guard let data = source[interleaved ? 0 : channel].mData else { continue }
            let input = data.assumingMemoryBound(to: Float.self)
            let destination = samples + channel * maximumFrameCount
            if interleaved {
                for frame in 0..<firstCount { destination[offset + frame] = input[frame * channelCount + channel] }
                for frame in firstCount..<frameCount { destination[frame - firstCount] = input[frame * channelCount + channel] }
            } else {
                (destination + offset).update(from: input, count: firstCount)
                destination.update(from: input + firstCount, count: frameCount - firstCount)
            }
        }
        descriptors[Int(writeSequence % UInt64(maximumBufferCount))] = Descriptor(offset: offset, frameCount: frameCount)
        writeFrames &+= UInt64(frameCount)
        writeSequence &+= 1
        publishedSequence.storeRelease(writeSequence)
    }

    /// Worker-only. The returned scratch buffer is valid until releaseBuffer;
    /// callers must finish processing it before requesting another buffer.
    func nextBuffer() -> AVAudioPCMBuffer? {
        precondition(activeFrameCount == 0)
        guard readSequence != publishedSequence.loadAcquire(),
              let channels = consumerBuffer.floatChannelData else { return nil }
        let descriptor = descriptors[Int(readSequence % UInt64(maximumBufferCount))]
        let firstCount = min(descriptor.frameCount, maximumFrameCount - descriptor.offset)
        for channel in 0..<channelCount {
            let source = samples + channel * maximumFrameCount
            channels[channel].update(from: source + descriptor.offset, count: firstCount)
            (channels[channel] + firstCount).update(from: source, count: descriptor.frameCount - firstCount)
        }
        activeFrameCount = descriptor.frameCount
        consumerBuffer.frameLength = AVAudioFrameCount(descriptor.frameCount)
        return consumerBuffer
    }

    func releaseBuffer() {
        precondition(activeFrameCount > 0)
        readFrames &+= UInt64(activeFrameCount)
        readSequence &+= 1
        activeFrameCount = 0
        releasedFrames.storeRelease(readFrames)
        releasedSequence.storeRelease(readSequence)
    }

    func close() { admission.bitwiseOrAcqRel(2) }

    /// Worker-only; acquire closure before publication so a final producer
    /// cannot be mistaken for an empty queue while it is still copying.
    var isDrained: Bool {
        admission.loadAcquire() == 2 &&
            readSequence == publishedSequence.loadAcquire() && activeFrameCount == 0
    }

    var pendingFrameCount: Int {
        let released = releasedFrames.loadAcquire()
        return Int(admittedFrames.loadAcquire() &- released)
    }

    var failure: Failure? { Failure(rawValue: failureCode.loadAcquire()) }

    private func fail(_ failure: Failure) {
        _ = failureCode.compareExchangeAcqRel(expected: 0, desired: failure.rawValue)
        close()
    }
}

/// C11 atomics support the app's iOS 17 deployment target. Each operation uses
/// its named memory ordering and the C module statically requires lock freedom.
/// Allocation and destruction happen with the owning ring, outside the tap.
private nonisolated final class AudioCaptureAtomicUInt64: @unchecked Sendable {
    private let pointer: OpaquePointer

    init(_ value: UInt64) throws {
        guard let pointer = pitchee_audio_atomic_create(value) else {
            throw LivePitchAudioCaptureError.inputUnavailable
        }
        self.pointer = pointer
    }

    deinit { pitchee_audio_atomic_destroy(pointer) }

    func loadAcquire() -> UInt64 { pitchee_audio_atomic_load_acquire(pointer) }
    func storeRelease(_ value: UInt64) { pitchee_audio_atomic_store_release(pointer, value) }
    func compareExchangeAcqRel(expected: UInt64, desired: UInt64) -> UInt64 {
        pitchee_audio_atomic_compare_exchange_acq_rel(pointer, expected, desired)
    }
    func bitwiseOrAcqRel(_ mask: UInt64) { pitchee_audio_atomic_or_acq_rel(pointer, mask) }
    func bitwiseAndRelease(_ mask: UInt64) { pitchee_audio_atomic_and_release(pointer, mask) }
}
