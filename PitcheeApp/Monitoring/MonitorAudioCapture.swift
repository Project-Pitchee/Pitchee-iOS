//
//  MonitorAudioCapture.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import AVFoundation
import Foundation

nonisolated struct MonitorCaptureUpdate: Sendable {
    let samples: [Float]
    let pitchFrames: [PitcheeF0Frame]
    let spectrumFrames: [MonitorSpectrumFrame]
}

/// Owns the microphone engine, but leaves AVAudioSession policy to the page.
/// Each instance supplies one fresh local timeline. Engine setup/teardown,
/// conversion, FFT, and Core F0 run off the caller's actor and realtime tap.
nonisolated final class MonitorAudioCapture: @unchecked Sendable {
    private let lifecycleQueue = DispatchQueue(
        label: "com.lvyzhan.Pitchee.monitor-capture-lifecycle",
        qos: .userInitiated
    )
    private let makeEngine: @Sendable () -> any MonitorCaptureEngine
    private let stateLock = NSLock()
    private var cancellationRequested = false
    private var currentRun: MonitorCaptureIngress?
    private var workerTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    // Only lifecycleQueue creates or accesses the engine and these flags.
    private var engine: (any MonitorCaptureEngine)?
    private var hasStarted = false
    private var didTeardown = false

    init(makeEngine: @escaping @Sendable () -> any MonitorCaptureEngine = { MonitorMicrophoneEngine() }) {
        self.makeEngine = makeEngine
    }

    func start(
        analyzer: PitcheeCoreAnalyzer?,
        needsSpectrum: Bool,
        onUpdate: @escaping @Sendable (MonitorCaptureUpdate) async -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lifecycleQueue.async {
                    guard !self.isCancelled, !self.hasStarted else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    self.hasStarted = true
                    do {
                        try self.startEngine(analyzer: analyzer, needsSpectrum: needsSpectrum,
                                             onUpdate: onUpdate, onError: onError)
                        continuation.resume()
                    } catch {
                        self.requestCancellation()
                        self.teardownEngine()
                        continuation.resume(throwing: error)
                    }
                }
            }
            try Task.checkCancellation()
        } onCancel: {
            self.cancel()
        }
    }

    private var isCancelled: Bool { stateLock.withLock { cancellationRequested } }

    private func startEngine(
        analyzer: PitcheeCoreAnalyzer?,
        needsSpectrum: Bool,
        onUpdate: @escaping @Sendable (MonitorCaptureUpdate) async -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        let engine = makeEngine()
        self.engine = engine
        guard !isCancelled else { throw CancellationError() }
        let format = engine.inputFormat
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0,
              format.commonFormat == .pcmFormatFloat32 else {
            throw MonitorAudioCaptureError.inputUnavailable
        }
        let converter = try LivePitchPCMConverter(sampleRate: format.sampleRate)
        let spectrum = try needsSpectrum ? MonitorSpectrumAnalyzer() : nil
        guard format.sampleRate <= 384_000 else { throw MonitorAudioCaptureError.inputUnavailable }
        let run = try MonitorCaptureIngress(format: format,
                                            maximumFrameCount: Int(ceil(format.sampleRate * 2)))
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                while !Task.isCancelled, run.isActive {
                    guard let buffer = run.nextBuffer() else {
                        if run.isDrained {
                            if let error = run.error { throw error }
                            return
                        }
                        // Polling is worker-only: no GCD dispatch, locks, or
                        // AsyncStream.yield is required from the audio tap.
                        try await Task.sleep(for: .milliseconds(2))
                        continue
                    }
                    defer { run.releaseBuffer() }
                    let samples = try converter.convert(buffer)
                    guard !samples.isEmpty else { continue }
                    let spectrumFrames = spectrum?.process(samples) ?? []
                    let pitchFrames: [PitcheeF0Frame]
                    if let analyzer {
                        pitchFrames = try await analyzer.processRealtimeF0(samples: samples)
                    } else {
                        pitchFrames = []
                    }
                    guard !Task.isCancelled, run.isActive else { return }
                    // Keep this input reserved until the timeline consumes its
                    // update. Backpressure must include main-actor delivery,
                    // not just conversion and inference, to bound retained PCM.
                    await onUpdate(MonitorCaptureUpdate(
                        samples: samples,
                        pitchFrames: pitchFrames,
                        spectrumFrames: spectrumFrames
                    ))
                }
            } catch {
                guard !Task.isCancelled, run.isActive else { return }
                self?.fail(run: run, error: error, onError: onError)
            }
        }
        // Register before installing the tap. Cancellation either closes this
        // run immediately or is observed here before any input is admitted.
        let shouldCancel = stateLock.withLock {
            currentRun = run
            workerTask = worker
            return cancellationRequested
        }
        guard !shouldCancel else {
            run.cancel()
            worker.cancel()
            throw CancellationError()
        }
        engine.installTap(format: format) { buffer in
            run.enqueue(buffer)
        }
        guard !isCancelled else { throw CancellationError() }
        engine.prepare()
        guard !isCancelled else { throw CancellationError() }
        try engine.start()
        // A synchronous engine.start cannot be interrupted, so cancellation
        // during it must tear down before startup reports success.
        guard !isCancelled else { throw CancellationError() }
    }

    /// Terminal cancellation closes admission immediately. Await the returned
    /// task before starting another capture or changing AVAudioSession policy.
    /// It includes an in-flight onUpdate; that callback must not await this task.
    @discardableResult
    func cancel() -> Task<Void, Never> {
        requestCancellation()
        return stateLock.withLock {
            if let teardownTask { return teardownTask }
            let task = Task.detached(priority: .userInitiated) {
                let worker: Task<Void, Never>? = await withCheckedContinuation { continuation in
                    self.lifecycleQueue.async {
                        self.teardownEngine()
                        let worker = self.stateLock.withLock {
                            let worker = self.workerTask
                            self.currentRun = nil
                            self.workerTask = nil
                            return worker
                        }
                        continuation.resume(returning: worker)
                    }
                }
                await worker?.value
            }
            teardownTask = task
            return task
        }
    }

    @discardableResult
    func stop() -> Task<Void, Never> {
        cancel()
    }

    deinit {
        currentRun?.cancel()
        workerTask?.cancel()
        // An owner may be released on MainActor without an explicit stop. The
        // queue keeps the engine alive through cleanup without retaining self.
        let engine = engine
        lifecycleQueue.async { engine?.stop() }
    }

    private func requestCancellation() {
        let state = stateLock.withLock {
            cancellationRequested = true
            return (currentRun, workerTask)
        }
        state.0?.cancel()
        state.1?.cancel()
    }

    private func teardownEngine() {
        guard !didTeardown else { return }
        engine?.stop()
        engine = nil
        didTeardown = true
    }

    private func fail(
        run: MonitorCaptureIngress,
        error: Error,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        let shouldReport = stateLock.withLock {
            currentRun === run && !cancellationRequested && run.isActive
        }
        guard shouldReport else { return }
        cancel()
        onError(error)
    }
}

/// The controller owns lifecycle ordering; the adapter only performs engine
/// operations. Injection exercises that same ordering without opening a mic.
nonisolated protocol MonitorCaptureEngine: AnyObject, Sendable {
    var inputFormat: AVAudioFormat { get }
    func installTap(format: AVAudioFormat, onAudio: @escaping @Sendable (AVAudioPCMBuffer) -> Void)
    func prepare()
    func start() throws
    func stop()
}

private nonisolated final class MonitorMicrophoneEngine: MonitorCaptureEngine, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var hasInputTap = false

    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func installTap(format: AVAudioFormat, onAudio: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            onAudio(buffer)
        }
        hasInputTap = true
    }

    func prepare() { engine.prepare() }
    func start() throws { try engine.start() }

    func stop() {
        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        engine.stop()
        engine.reset()
    }
}

/// Bounds both the number of buffers and the total retained hardware frames,
/// including the buffer currently under analysis. An overrun explicitly fails
/// the run; discarded input can never silently compress the monitoring clock.
private nonisolated final class MonitorCaptureIngress: @unchecked Sendable {
    private let lock = NSLock()
    private let ring: RealtimeAudioBufferRing
    private var active = true

    init(format: AVAudioFormat, maximumFrameCount: Int) throws {
        ring = try RealtimeAudioBufferRing(format: format, maximumFrameCount: maximumFrameCount)
    }

    var isActive: Bool {
        lock.withLock { active }
    }

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        ring.enqueue(buffer)
    }

    func nextBuffer() -> AVAudioPCMBuffer? { ring.nextBuffer() }
    func releaseBuffer() { ring.releaseBuffer() }
    var isDrained: Bool { ring.isDrained }
    var error: MonitorAudioCaptureError? {
        switch ring.failure {
        case .overrun: return .processingOverrun
        case .invalidBuffer: return .copyFailed
        case nil: return nil
        }
    }

    func cancel() {
        ring.close()
        lock.withLock { active = false }
    }
}

nonisolated enum MonitorAudioCaptureError: Error {
    case inputUnavailable
    case copyFailed
    case processingOverrun
}
