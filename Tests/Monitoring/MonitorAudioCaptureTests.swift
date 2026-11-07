//
//  MonitorAudioCaptureTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/6.
//

import AVFoundation
import Foundation

/// Uses the production capture controller, ingress, converter, and FFT. Only
/// hardware engine calls are substituted, so no microphone permission is needed.
@main
enum MonitorAudioCaptureTests {
    @MainActor
    static func main() async throws {
        var checks = 0
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition {
                failures += 1
                print("FAIL: \(message)")
            }
        }

        let factories = CaptureEvents()
        let cancelled = MonitorAudioCapture {
            factories.record("created")
            return TestMonitorEngine()
        }
        await cancelled.cancel().value
        check(await startWasCancelled(cancelled), "cancellation before startup is terminal")
        check(factories.count("created") == 0, "cancel-before-start never creates an audio engine")
        await cancelled.stop().value

        let activeEngine = TestMonitorEngine()
        let active = MonitorAudioCapture { activeEngine }
        try await start(active)
        check(await startWasCancelled(active), "a second start on one capture is rejected")
        check(activeEngine.events.count("start") == 1 && activeEngine.events.count("stop") == 0,
              "duplicate startup does not interrupt the active run")
        await active.cancel().value
        await active.stop().value
        check(activeEngine.events.count("stop") == 1, "repeated cancellation tears down the engine once")
        check(activeEngine.events.count("main-thread") == 0, "engine calls run off the main thread")

        let orphanEngine = TestMonitorEngine()
        var orphan: MonitorAudioCapture? = MonitorAudioCapture { orphanEngine }
        let weakOrphan = CaptureWeakReference(orphan)
        try await start(orphan!)
        orphan = nil
        check(await waitFor { orphanEngine.events.count("stop") == 1 },
              "releasing an owner without explicit cancellation still stops its microphone")
        check(weakOrphan.value == nil, "the polling worker never keeps an abandoned capture alive")

        for cancelTask in [false, true] {
            let gate = CaptureThreadGate()
            let engine = TestMonitorEngine(prepareGate: gate)
            let capture = MonitorAudioCapture { engine }
            let startup = Task { await startWasCancelled(capture) }
            check(await waitFor { engine.events.count("prepare") == 1 }, "prepare can be held during startup")
            if cancelTask { startup.cancel() }
            let teardown = capture.cancel()
            check(engine.events.count("start") == 0 && engine.events.count("stop") == 0,
                  "cancellation returns while prepare is still blocked")
            gate.open()
            check(await startup.value, "startup observes explicit or task cancellation during prepare")
            await teardown.value
            check(engine.events.count("start") == 0 && engine.events.count("stop") == 1,
                  "cancelled preparation tears down without starting the microphone")
            check(!gate.timedOut, "cancellation never waits synchronously for preparation")
        }

        let startGate = CaptureThreadGate()
        let startingEngine = TestMonitorEngine(startGate: startGate)
        let starting = MonitorAudioCapture { startingEngine }
        let startup = Task { await startWasCancelled(starting) }
        check(await waitFor { startingEngine.events.count("start") == 1 }, "test engine holds an in-flight start")
        let firstTeardown = starting.cancel()
        let secondTeardown = starting.cancel()
        startGate.open()
        check(await startup.value, "cancellation during engine.start cannot report a successful capture")
        await firstTeardown.value
        await secondTeardown.value
        check(startingEngine.events.count("stop") == 1 && !startGate.timedOut,
              "an in-flight start is stopped once before cancellation completes")

        let failingEngine = TestMonitorEngine(failStart: true)
        let failing = MonitorAudioCapture { failingEngine }
        do {
            try await start(failing)
            check(false, "engine startup failure must propagate")
        } catch CaptureTestError.startFailed {
            check(true, "engine startup failure propagates")
        }
        await failing.cancel().value
        check(failingEngine.events.count("stop") == 1, "failed startup cleans up its installed tap once")
        check(await startWasCancelled(failing), "failed capture cannot be restarted")

        let stopGate = CaptureThreadGate()
        let oldEngine = TestMonitorEngine(stopGate: stopGate)
        let oldCapture = MonitorAudioCapture { oldEngine }
        try await start(oldCapture)
        let oldTeardown = oldCapture.cancel()
        check(await waitFor { oldEngine.events.count("stop") == 1 }, "old engine teardown can remain in flight")
        let newEngine = TestMonitorEngine()
        let newCapture = MonitorAudioCapture { newEngine }
        let newUpdates = CaptureUpdates()
        try await start(newCapture, onUpdate: { newUpdates.append($0) })
        stopGate.open()
        await oldTeardown.value
        newEngine.emit(samples: [1, 2, 3])
        check(await waitFor { newUpdates.count == 1 }, "old teardown cannot stop a newer capture instance")
        check(newEngine.events.count("stop") == 0 && !stopGate.timedOut,
              "each capture owns its engine and teardown")
        await newCapture.cancel().value

        let updateGate = CaptureAsyncGate()
        let blockedEngine = TestMonitorEngine()
        let blockedCapture = MonitorAudioCapture { blockedEngine }
        let delivery = CaptureEvents()
        try await start(blockedCapture, onUpdate: { _ in
            delivery.record("update")
            await updateGate.wait()
        })
        blockedEngine.emit(samples: [1, 2, 3])
        check(await waitFor { delivery.count("update") == 1 }, "test delivery holds one in-flight update")
        let cancellation = blockedCapture.cancel()
        let completion = Task {
            await cancellation.value
            delivery.record("finished")
        }
        check(await waitFor { blockedEngine.events.count("stop") == 1 }, "engine stops while UI delivery is suspended")
        check(delivery.count("finished") == 0, "cancellation completion waits for the in-flight update")
        blockedEngine.emit(samples: [4, 5])
        updateGate.open()
        await completion.value
        check(delivery.count("update") == 1, "cancelled capture admits no further updates")

        // The first buffer is suspended inside onUpdate. It must still count
        // against both limits until the callback returns.
        for (frameCount, bufferCount) in [(16_000, 2), (1, 128)] {
            let gate = CaptureAsyncGate()
            let engine = TestMonitorEngine()
            let capture = MonitorAudioCapture { engine }
            let updates = CaptureUpdates()
            let errors = CaptureEvents()
            try await capture.start(analyzer: nil, needsSpectrum: false, onUpdate: { update in
                updates.append(update)
                await gate.wait()
            }, onError: { error in
                if case MonitorAudioCaptureError.processingOverrun = error { errors.record("overrun") }
                else { errors.record("unexpected") }
            })
            let samples = [Float](repeating: 0.25, count: frameCount)
            engine.emit(samples: samples)
            check(await waitFor { updates.count == 1 }, "budget test suspends the first delivered buffer")
            for _ in 1..<bufferCount { engine.emit(samples: samples) }
            engine.emit(samples: [0])
            gate.open()
            check(await waitFor { errors.count("overrun") == 1 },
                  "\(bufferCount == 2 ? "2-second" : "128-buffer") limit includes in-flight onUpdate")
            await capture.cancel().value
            check(updates.count == bufferCount && errors.count("unexpected") == 0,
                  "overload preserves accepted PCM order and reports one explicit failure")
            check(updates.samples.allSatisfy { $0 == samples }, "accepted audio retains its exact sample clock")
        }

        for needsSpectrum in [false, true] {
            let engine = TestMonitorEngine()
            let capture = MonitorAudioCapture { engine }
            let updates = CaptureUpdates()
            try await capture.start(analyzer: nil, needsSpectrum: needsSpectrum,
                                    onUpdate: { updates.append($0) }, onError: { _ in })
            let samples = (0..<2_048).map { Float(sin(2 * Double.pi * 250 * Double($0) / 16_000)) }
            engine.emit(samples: samples)
            check(await waitFor { updates.count == 1 }, "explicit spectrum mode delivers PCM")
            await capture.cancel().value
            check(updates.samples == [samples], "spectrum selection does not change PCM samples")
            let frames = updates.spectra
            check(needsSpectrum ? frames.count == 1 : frames.isEmpty,
                  "FFT is controlled explicitly, independently of an optional pitch analyzer")
            if let frame = frames.first {
                check(frame.elapsedTime == 0.128 && frame.magnitudesDB.count == 1_025,
                      "enabled spectrum retains the original FFT window and timestamp")
            }
        }

        print("Monitor capture checks: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }

    private static func start(
        _ capture: MonitorAudioCapture,
        onUpdate: @escaping @Sendable (MonitorCaptureUpdate) async -> Void = { _ in }
    ) async throws {
        try await capture.start(analyzer: nil, needsSpectrum: false, onUpdate: onUpdate, onError: { _ in })
    }

    private static func startWasCancelled(_ capture: MonitorAudioCapture) async -> Bool {
        do { try await start(capture); return false }
        catch is CancellationError { return true }
        catch { return false }
    }

    private static func waitFor(_ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }
}

private enum CaptureTestError: Error { case startFailed }

private final class CaptureWeakReference<Value: AnyObject>: @unchecked Sendable {
    weak var value: Value?
    init(_ value: Value?) { self.value = value }
}

private final class CaptureEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func record(_ event: String) { lock.withLock { events.append(event) } }
    func count(_ event: String) -> Int { lock.withLock { events.filter { $0 == event }.count } }
}

private final class CaptureUpdates: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [MonitorCaptureUpdate] = []
    func append(_ update: MonitorCaptureUpdate) { lock.withLock { updates.append(update) } }
    var count: Int { lock.withLock { updates.count } }
    var samples: [[Float]] { lock.withLock { updates.map(\.samples) } }
    var spectra: [MonitorSpectrumFrame] { lock.withLock { updates.flatMap(\.spectrumFrames) } }
}

private final class CaptureThreadGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var timeout = false
    var timedOut: Bool { lock.withLock { timeout } }
    func wait() {
        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            lock.withLock { timeout = true }
        }
    }
    func open() { semaphore.signal() }
}

private final class CaptureAsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            let resume = lock.withLock {
                if isOpen { return true }
                self.continuation = continuation
                return false
            }
            if resume { continuation.resume() }
        }
    }
    func open() {
        let pending = lock.withLock {
            isOpen = true
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume()
    }
}

private final class TestMonitorEngine: MonitorCaptureEngine, @unchecked Sendable {
    let events = CaptureEvents()
    private let lock = NSLock()
    private let prepareGate: CaptureThreadGate?
    private let startGate: CaptureThreadGate?
    private let stopGate: CaptureThreadGate?
    private let failStart: Bool
    private var onAudio: (@Sendable (AVAudioPCMBuffer) -> Void)?

    init(prepareGate: CaptureThreadGate? = nil, startGate: CaptureThreadGate? = nil,
         stopGate: CaptureThreadGate? = nil, failStart: Bool = false) {
        self.prepareGate = prepareGate
        self.startGate = startGate
        self.stopGate = stopGate
        self.failStart = failStart
    }

    var inputFormat: AVAudioFormat {
        record("format")
        return AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    }

    func installTap(format: AVAudioFormat, onAudio: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        record("tap")
        lock.withLock { self.onAudio = onAudio }
    }

    func prepare() { record("prepare"); prepareGate?.wait() }
    func start() throws {
        record("start")
        startGate?.wait()
        if failStart { throw CaptureTestError.startFailed }
    }
    func stop() {
        record("stop")
        stopGate?.wait()
        lock.withLock { onAudio = nil }
    }
    func emit(samples: [Float]) {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count)
        }
        lock.withLock { onAudio }?(buffer)
    }
    private func record(_ event: String) {
        if Thread.isMainThread { events.record("main-thread") }
        events.record(event)
    }
}
