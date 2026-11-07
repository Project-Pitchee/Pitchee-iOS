//
//  LivePitchAudioCapture.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/18.
//

import AVFoundation
import Foundation

/// Records microphone audio and feeds contiguous 16 kHz PCM to Core's realtime
/// SwiftF0 stream. File writes and sample conversion stay off the audio thread.
nonisolated final class LivePitchAudioCapture: @unchecked Sendable {
    typealias PitchHandler = @Sendable ([PitcheeF0Frame]) -> Void
    typealias ErrorHandler = @Sendable (Error) -> Void

    private let audioEngine = AVAudioEngine()
    private let lifecycleQueue = DispatchQueue(
        label: "com.lvyzhan.Pitchee.capture-lifecycle",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var stopRequested = false
    private var cancellationRequested = false
    private var run: LivePitchRecordingRun?
    private var teardownTask: Task<Error?, Never>?
    // Engine and tap state are confined to lifecycleQueue.
    private var hasStarted = false
    private var hasInputTap = false
    private var didTeardown = false
    private var teardownError: Error?

    func start(
        writingTo url: URL,
        analyzer: PitcheeCoreAnalyzer,
        onPitch: @escaping PitchHandler,
        onError: @escaping ErrorHandler,
        onRecordingError: ErrorHandler? = nil
    ) throws {
        try lifecycleQueue.sync {
            guard !stateLock.withLock({ stopRequested }), !hasStarted else {
                throw CancellationError()
            }
            hasStarted = true
            do {
                try startEngine(writingTo: url, analyzer: analyzer, onPitch: onPitch,
                                onError: onError, onRecordingError: onRecordingError)
            } catch {
                requestStop(discardingPendingWrites: true)
                _ = stopEngineAndDrain()
                throw error
            }
        }
    }

    private func startEngine(
        writingTo url: URL,
        analyzer: PitcheeCoreAnalyzer,
        onPitch: @escaping PitchHandler,
        onError: @escaping ErrorHandler,
        onRecordingError: ErrorHandler?
    ) throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate.isFinite, inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0, inputFormat.commonFormat == .pcmFormatFloat32 else {
            throw LivePitchAudioCaptureError.inputUnavailable
        }

        // Hardware formats vary between devices. Passing `inputFormat.settings`
        // through can produce WAVE_FORMAT_EXTENSIBLE, while PitcheeCore accepts
        // canonical PCM16/PCM32/Float32 WAV files. Keep the engine-side client
        // format as Float32 for pitch tracking, but always encode a PCM16 WAV.
        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: fileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
        let run = try LivePitchRecordingRun(
            file: file,
            sampleRate: inputFormat.sampleRate,
            inputFormat: inputFormat,
            processPitch: { try await analyzer.processRealtimeF0(samples: $0) },
            onPitch: onPitch,
            onError: onError,
            onRecordingError: onRecordingError
        )
        let shouldStop = stateLock.withLock {
            self.run = run
            return stopRequested
        }
        guard !shouldStop else { throw CancellationError() }
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: inputFormat
        ) { buffer, _ in
            run.enqueue(buffer)
        }
        hasInputTap = true
        audioEngine.prepare()
        guard !stateLock.withLock({ stopRequested }) else { throw CancellationError() }
        try audioEngine.start()
    }

    /// Terminal graceful stop. WAV writes finish and the file closes before
    /// returning, without blocking the caller's actor on engine or disk work.
    func finish() async -> Error? {
        await scheduleTeardown(discardingPendingWrites: false).value
    }

    /// Terminal cancellation is immediate; teardown happens off the caller's
    /// actor. Await this task before deleting the recording's temporary file.
    @discardableResult
    func cancel() -> Task<Error?, Never> {
        scheduleTeardown(discardingPendingWrites: true)
    }

    private func requestStop(discardingPendingWrites: Bool) {
        let state = stateLock.withLock {
            stopRequested = true
            cancellationRequested = cancellationRequested || discardingPendingWrites
            return (run, cancellationRequested)
        }
        state.0?.close(discardingPendingWrites: state.1)
    }

    private func scheduleTeardown(discardingPendingWrites: Bool) -> Task<Error?, Never> {
        requestStop(discardingPendingWrites: discardingPendingWrites)
        return stateLock.withLock {
            if let teardownTask { return teardownTask }
            let task = Task.detached(priority: .userInitiated) {
                self.lifecycleQueue.sync { self.stopEngineAndDrain() }
            }
            teardownTask = task
            return task
        }
    }

    private func stopEngineAndDrain() -> Error? {
        guard !didTeardown else { return teardownError }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        if hasStarted {
            audioEngine.stop()
            audioEngine.reset()
        }
        teardownError = stateLock.withLock { run }?.drainAndCloseFile()
        didTeardown = true
        return teardownError
    }

    deinit {
        let engine = audioEngine
        let run = run
        let removeTap = hasInputTap
        let stopEngine = hasStarted && !didTeardown
        run?.close(discardingPendingWrites: true)
        lifecycleQueue.async {
            if removeTap { engine.inputNode.removeTap(onBus: 0) }
            if stopEngine { engine.stop(); engine.reset() }
            _ = run?.drainAndCloseFile()
        }
    }

    static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channels = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }
        if buffer.format.channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channels[0], count: frameCount))
        }
        var samples = [Float](repeating: 0, count: frameCount)
        let copied = samples.withUnsafeMutableBufferPointer { destination in
            copyMonoSamples(from: buffer, to: destination)
        }
        return copied ? samples : nil
    }

    /// Shares the downmix with the converter without allocating an intermediate
    /// mono array for every hardware buffer.
    static func copyMonoSamples(
        from buffer: AVAudioPCMBuffer,
        to destination: UnsafeMutableBufferPointer<Float>
    ) -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0, destination.count >= frameCount,
              let output = destination.baseAddress else { return false }
        if channelCount == 1 {
            output.update(from: channels[0], count: frameCount)
            return true
        }
        let scale = 1 / Float(channelCount)
        let stride = buffer.format.isInterleaved ? channelCount : 1
        for frameIndex in 0..<frameCount {
            output[frameIndex] = channels[0][frameIndex * stride] * scale
        }
        for channelIndex in 1..<channelCount {
            let channel = buffer.format.isInterleaved ? channels[0] + channelIndex : channels[channelIndex]
            for frameIndex in 0..<frameCount {
                output[frameIndex] += channel[frameIndex * stride] * scale
            }
        }
        return true
    }
}

/// Admission is reserved before copying PCM, and includes the item currently
/// being processed. Closing a budget is terminal: overload never drops a chunk
/// and then resumes on a compressed sample clock.
nonisolated final class AudioCaptureBufferBudget: @unchecked Sendable {
    enum Admission: Equatable { case accepted, closed, overrun }

    private let lock = NSLock()
    private let maximumFrameCount: Int
    private let maximumBufferCount: Int
    private var accepting = true
    private var retainedFrameCount = 0
    private var retainedBufferCount = 0

    init(maximumFrameCount: Int, maximumBufferCount: Int = 128) {
        self.maximumFrameCount = maximumFrameCount
        self.maximumBufferCount = maximumBufferCount
    }

    func reserve(frameCount: Int) -> Admission {
        lock.withLock {
            guard accepting else { return .closed }
            guard frameCount > 0, frameCount <= maximumFrameCount - retainedFrameCount,
                  retainedBufferCount < maximumBufferCount else {
                accepting = false
                return .overrun
            }
            retainedFrameCount += frameCount
            retainedBufferCount += 1
            return .accepted
        }
    }

    func release(frameCount: Int) {
        lock.withLock {
            retainedFrameCount -= frameCount
            retainedBufferCount -= 1
        }
    }

    func close() {
        lock.withLock { accepting = false }
    }

    var retainedFrames: Int { lock.withLock { retainedFrameCount } }
}

/// Uses wall-clock time rather than detector timestamps: inference may replay
/// several captured buffers at once after a stall. Every frame stays in order.
nonisolated struct LivePitchFrameBatcher {
    static let deliveryInterval: TimeInterval = 1.0 / 30

    private var pendingFrames: [PitcheeF0Frame] = []
    private var nextDeliveryTime: TimeInterval = -.infinity

    mutating func append(_ frames: [PitcheeF0Frame]) {
        pendingFrames.append(contentsOf: frames)
    }

    func deliveryDelay(at uptime: TimeInterval) -> TimeInterval? {
        guard !pendingFrames.isEmpty else { return nil }
        return max(0, nextDeliveryTime - uptime)
    }

    mutating func takeIfDue(at uptime: TimeInterval) -> [PitcheeF0Frame]? {
        guard deliveryDelay(at: uptime) == 0 else { return nil }
        let frames = pendingFrames
        pendingFrames.removeAll(keepingCapacity: true)
        nextDeliveryTime = uptime + Self.deliveryInterval
        return frames
    }

    mutating func discardPendingFrames() {
        pendingFrames.removeAll(keepingCapacity: false)
    }
}

/// A one-shot delivery exists only while frames are pending, so a trailing
/// silent frame is delivered even when the detector has no next output batch.
nonisolated final class LivePitchFrameDelivery: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let onPitch: LivePitchAudioCapture.PitchHandler
    private var batcher = LivePitchFrameBatcher()
    private var scheduledDelivery: DispatchWorkItem?
    private var active = true

    init(onPitch: @escaping LivePitchAudioCapture.PitchHandler) {
        self.onPitch = onPitch
    }

    func append(_ frames: [PitcheeF0Frame]) {
        lock.withLock {
            guard active else { return }
            batcher.append(frames)
            schedulePendingDelivery()
        }
    }

    func cancel() {
        lock.withLock {
            active = false
            scheduledDelivery?.cancel()
            scheduledDelivery = nil
            batcher.discardPendingFrames()
        }
    }

    /// Caller holds the lock; at most one delayed work item retains pending
    /// frames. Silence without new frames never creates recurring work.
    private func schedulePendingDelivery() {
        guard scheduledDelivery == nil,
              let delay = batcher.deliveryDelay(at: ProcessInfo.processInfo.systemUptime) else { return }
        let delivery = DispatchWorkItem { [weak self] in self?.deliverPendingFrames() }
        scheduledDelivery = delivery
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: delivery)
    }

    private func deliverPendingFrames() {
        lock.withLock {
            guard active else { return }
            scheduledDelivery = nil
            if let frames = batcher.takeIfDue(at: ProcessInfo.processInfo.systemUptime) {
                // The handler only enqueues its MainActor update. Serializing
                // this call with cancel prevents delivery after cancel returns.
                // A recursive lock also permits a handler to cancel itself.
                onPitch(frames)
            }
            if active { schedulePendingDelivery() }
        }
    }
}

/// The lossless WAV writer and optional realtime detector have independent
/// budgets. An overloaded detector is disabled while the original audio keeps
/// recording; an overloaded writer explicitly invalidates the entire take.
nonisolated final class LivePitchRecordingRun: @unchecked Sendable {
    typealias PitchProcessor = @Sendable ([Float]) async throws -> [PitcheeF0Frame]

    private let writerQueue = DispatchQueue(label: "com.lvyzhan.Pitchee.live-pitch", qos: .userInitiated)
    private let lock = NSLock()
    private let rawInput: RealtimeAudioBufferRing
    private var writerTimer: DispatchSourceTimer?
    private let pitchBudget = AudioCaptureBufferBudget(maximumFrameCount: 32_000)
    private let converter: LivePitchPCMConverter
    private let pitchInput: AsyncStream<[Float]>.Continuation
    private let pitchDelivery: LivePitchFrameDelivery
    private let onError: LivePitchAudioCapture.ErrorHandler
    private let onRecordingError: LivePitchAudioCapture.ErrorHandler?
    private var pitchTask: Task<Void, Never>?
    private var cancelled = false
    private var pitchActive = true
    private var recordingError: Error?
    // Only writerQueue accesses the file after initialization.
    private var file: AVAudioFile?

    init(
        file: AVAudioFile,
        sampleRate: Double,
        inputFormat: AVAudioFormat? = nil,
        processPitch: @escaping PitchProcessor,
        onPitch: @escaping LivePitchAudioCapture.PitchHandler,
        onError: @escaping LivePitchAudioCapture.ErrorHandler,
        onRecordingError: LivePitchAudioCapture.ErrorHandler? = nil
    ) throws {
        self.file = file
        converter = try LivePitchPCMConverter(sampleRate: sampleRate)
        guard sampleRate <= 384_000 else { throw LivePitchAudioCaptureError.inputUnavailable }
        rawInput = try RealtimeAudioBufferRing(format: inputFormat ?? file.processingFormat,
                                              maximumFrameCount: Int(ceil(sampleRate * 2)))
        self.onError = onError
        self.onRecordingError = onRecordingError
        let delivery = LivePitchFrameDelivery(onPitch: onPitch)
        pitchDelivery = delivery
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingOldest(128))
        pitchInput = continuation
        let budget = pitchBudget
        pitchTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                for await samples in stream {
                    defer { budget.release(frameCount: samples.count) }
                    guard !Task.isCancelled, self?.isPitchActive == true else { return }
                    let frames = try await processPitch(samples)
                    guard !Task.isCancelled, self?.isPitchActive == true else { return }
                    delivery.append(frames)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.stopPitch(reporting: error)
            }
        }
        // The worker polls a preallocated ring; the audio callback never needs
        // to wake a queue, allocate a block, or enter an AsyncStream lock.
        let timer = DispatchSource.makeTimerSource(queue: writerQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.consumePendingBuffers() }
        writerTimer = timer
        timer.resume()
    }

    private var isPitchActive: Bool { lock.withLock { pitchActive } }
    var pendingWriteFrameCount: Int { rawInput.pendingFrameCount }

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        rawInput.enqueue(buffer)
    }

    private func consumePendingBuffers() {
        while let buffer = rawInput.nextBuffer() {
            write(buffer)
            rawInput.releaseBuffer()
        }
        if rawInput.isDrained, let failure = rawInput.failure {
            failRecording(failure == .overrun ? LivePitchAudioCaptureError.recordingOverrun :
                          LivePitchAudioCaptureError.copyFailed)
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard lock.withLock({ !cancelled && recordingError == nil }) else { return }
        do {
            try file?.write(from: buffer)
        } catch {
            failRecording(error)
            return
        }
        guard isPitchActive else { return }
        do {
            let samples = try converter.convert(buffer)
            guard !samples.isEmpty else { return }
            switch pitchBudget.reserve(frameCount: samples.count) {
            case .closed: return
            case .overrun:
                stopPitch(reporting: LivePitchAudioCaptureError.pitchProcessingOverrun)
                return
            case .accepted: break
            }
            switch pitchInput.yield(samples) {
            case .enqueued: break
            case .dropped:
                pitchBudget.release(frameCount: samples.count)
                stopPitch(reporting: LivePitchAudioCaptureError.pitchProcessingOverrun)
            case .terminated:
                pitchBudget.release(frameCount: samples.count)
                stopPitch(reporting: nil)
            @unknown default:
                pitchBudget.release(frameCount: samples.count)
                stopPitch(reporting: LivePitchAudioCaptureError.pitchProcessingOverrun)
            }
        } catch {
            stopPitch(reporting: error)
        }
    }

    private func stopPitch(reporting error: Error?) {
        let state = lock.withLock {
            let shouldReport = pitchActive && error != nil
            pitchActive = false
            let task = pitchTask
            pitchTask = nil
            return (shouldReport, task)
        }
        pitchDelivery.cancel()
        pitchBudget.close()
        pitchInput.finish()
        state.1?.cancel()
        if state.0, let error {
            let handler = onError
            Task.detached { handler(error) }
        }
    }

    private func failRecording(_ error: Error) {
        let shouldReport = lock.withLock {
            guard recordingError == nil, !cancelled else { return false }
            recordingError = error
            return true
        }
        guard shouldReport else { return }
        rawInput.close()
        stopPitch(reporting: nil)
        if let handler = onRecordingError {
            Task.detached { handler(error) }
        }
    }

    func close(discardingPendingWrites: Bool) {
        rawInput.close()
        lock.withLock {
            cancelled = cancelled || discardingPendingWrites
        }
        stopPitch(reporting: nil)
    }

    /// Call only after close. The queue still owns the file until all accepted
    /// writes either complete or observe terminal cancellation.
    func drainAndCloseFile() -> Error? {
        writerQueue.sync {
            repeat {
                consumePendingBuffers()
                if rawInput.isDrained { break }
                // Only an already admitted callback can still be copying.
                // Waiting is confined to this disk worker, never the tap.
                Thread.sleep(forTimeInterval: 0.001)
            } while true
            writerTimer?.cancel()
            writerTimer = nil
            file = nil
        }
        return lock.withLock { recordingError }
    }

    deinit {
        rawInput.close()
        writerTimer?.cancel()
        pitchDelivery.cancel()
        pitchInput.finish()
        pitchTask?.cancel()
    }
}

/// One converter per recording preserves resampling state across tap buffers.
/// This adapter only prepares PCM; Core performs all pitch calculations.
nonisolated final class LivePitchPCMConverter {
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private var inputBuffer: AVAudioPCMBuffer?
    private var outputBuffer: AVAudioPCMBuffer?
    init(sampleRate: Double) throws {
        guard sampleRate.isFinite, sampleRate > 0,
              let input = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let output = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw LivePitchAudioCaptureError.inputUnavailable
        }
        inputFormat = input
        outputFormat = output
        if sampleRate == 16_000 {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: output) else {
                throw LivePitchAudioCaptureError.conversionFailed
            }
            converter.primeMethod = .none
            self.converter = converter
        }
    }

    func convert(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard let converter else { return samples }
        let input = try prepareInput(frameCount: samples.count)
        guard let channels = input.floatChannelData else { throw LivePitchAudioCaptureError.conversionFailed }
        try samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { throw LivePitchAudioCaptureError.conversionFailed }
            channels[0].update(from: baseAddress, count: source.count)
        }
        return try resample(input, using: converter)
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard buffer.frameLength > 0 else { return [] }
        guard buffer.format.sampleRate == inputFormat.sampleRate else {
            throw LivePitchAudioCaptureError.conversionFailed
        }
        guard let converter else {
            guard let samples = LivePitchAudioCapture.monoSamples(from: buffer) else {
                throw LivePitchAudioCaptureError.conversionFailed
            }
            return samples
        }
        let input = try prepareInput(frameCount: Int(buffer.frameLength))
        guard let channels = input.floatChannelData, LivePitchAudioCapture.copyMonoSamples(
            from: buffer,
            to: UnsafeMutableBufferPointer(start: channels[0], count: Int(input.frameLength))
        ) else {
            throw LivePitchAudioCaptureError.conversionFailed
        }
        return try resample(input, using: converter)
    }

    /// The converter is confined to a single capture worker. Its scratch PCM
    /// can grow for larger taps and be reused for all smaller subsequent taps.
    private func prepareInput(frameCount: Int) throws -> AVAudioPCMBuffer {
        let capacity = AVAudioFrameCount(frameCount)
        if (inputBuffer?.frameCapacity ?? 0) < capacity {
            inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: capacity)
        }
        guard let inputBuffer else { throw LivePitchAudioCaptureError.conversionFailed }
        inputBuffer.frameLength = capacity
        return inputBuffer
    }

    private func resample(_ input: AVAudioPCMBuffer, using converter: AVAudioConverter) throws -> [Float] {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / inputFormat.sampleRate)) + 256
        if (outputBuffer?.frameCapacity ?? 0) < capacity {
            outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        }
        guard let output = outputBuffer else {
            throw LivePitchAudioCaptureError.conversionFailed
        }
        output.frameLength = 0
        var suppliedInput = false
        var result: [Float] = []
        while true {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if suppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return input
            }
            if let error { throw error }
            guard status != .error else { throw LivePitchAudioCaptureError.conversionFailed }
            if let data = output.floatChannelData, output.frameLength > 0 {
                result.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
            }
            if status != .haveData { return result }
            output.frameLength = 0
        }
    }
}

nonisolated enum LivePitchAudioCaptureError: Error {
    case inputUnavailable
    case conversionFailed
    case copyFailed
    case recordingOverrun
    case pitchProcessingOverrun
}
