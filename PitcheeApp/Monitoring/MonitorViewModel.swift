//
//  MonitorViewModel.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import AVFoundation
import Foundation
import Observation
import OSLog

enum MonitorKind: String, CaseIterable, Identifiable {
    case spectrum, pitch

    var id: String { rawValue }
    var titleKey: String { "monitor.\(rawValue).title" }
    var symbol: String { self == .spectrum ? "waveform.path" : "waveform.path.ecg" }
}

/// Each destination owns its microphone timeline. Playback freezes capture so
/// the speaker cannot feed back into the microphone or evict the selected audio.
@MainActor
@Observable
final class MonitorViewModel {
    enum State { case idle, preparing, live, paused, replaying }

    nonisolated static let windowDurations: [TimeInterval] = [3, 5, 8, 10, 15, 30]

    let kind: MonitorKind
    private let includesSpectrogram: Bool
    private(set) var state: State = .idle
    private(set) var errorMessage: String?
    private(set) var windowDuration: TimeInterval = 10
    private(set) var cursorTime: TimeInterval = 0
    private let presentation = MonitorPresentation()
    @ObservationIgnored private var playbackRange: ClosedRange<TimeInterval>?
    @ObservationIgnored private var playbackPage: ClosedRange<TimeInterval>?
    @ObservationIgnored private var browsePage: ClosedRange<TimeInterval>?
    @ObservationIgnored private var resumesLiveAfterPlayback = false

    @ObservationIgnored private var capture: MonitorAudioCapture?
    @ObservationIgnored private var analyzer: PitcheeCoreAnalyzer?
    @ObservationIgnored private var analyzerSettings: AnalyzerSettings?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playerDelegate: MonitorPlaybackDelegate?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var playbackClock: Task<Void, Never>?
    @ObservationIgnored private var displayClock: Task<Void, Never>?
    @ObservationIgnored private var needsPresentation = false
    @ObservationIgnored private var audioTeardown: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var sessionOwner: UUID?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var sceneIsActive = true
    @ObservationIgnored private var awaitingPermission = false

    nonisolated private static let logger = Logger(subsystem: "com.lvyzhan.Pitchee", category: "Monitoring")

    init(kind: MonitorKind, includesSpectrogram: Bool = false) {
        self.kind = kind
        self.includesSpectrogram = includesSpectrogram
        let stored = UserDefaults.standard.object(forKey: AppStorageKey.monitorWindowDuration) as? Double ?? 10
        windowDuration = Self.windowDurations.contains(stored) ? stored : 10
    }

    var statusKey: String {
        switch state {
        case .idle: "monitor.status.ready"
        case .preparing: "monitor.status.preparing"
        case .live: "monitor.status.live"
        case .paused: "monitor.status.paused"
        case .replaying: "monitor.status.replaying"
        }
    }

    var availableRange: ClosedRange<TimeInterval> { presentation.availableRange }
    var hasAudio: Bool { availableRange.upperBound > availableRange.lowerBound }
    var canRewind: Bool { !isBusy && cursorTime > availableRange.lowerBound }
    var isBusy: Bool { state == .preparing }

    var visibleRange: ClosedRange<TimeInterval> { presentation.pitchWindow.range }

    var visiblePitchSamples: [LivePitchSample] {
        presentation.pitchWindow.samples
    }

    var visiblePitchRange: ClosedRange<Double>? { presentation.pitchWindow.pitchRange }
    var visibleAveragePitchHz: Double? { presentation.pitchWindow.averagePitchHz }

    var visibleSpectrogramColumns: [MonitorSpectrogramColumn] {
        presentation.visibleSpectrogramColumns
    }

    /// A partial capture fills a fixed-width time window from the left. Its
    /// existing columns keep their scale while new audio fills the empty area.
    var spectrogramTimeRange: ClosedRange<TimeInterval> {
        let range = visibleRange
        return range.lowerBound...max(range.upperBound, range.lowerBound + windowDuration)
    }

    var currentPitchHz: Double? { presentation.currentPitchHz }

    var currentSpectrum: MonitorSpectrumFrame? { presentation.currentSpectrum }

    /// Frequency and amplitude readouts use the same strongest visible bin.
    var currentSpectrumPeak: (frequencyHz: Double, amplitudeDBFS: Float)? {
        currentSpectrum?.peak
    }

    var currentFrequencyHz: Double? {
        kind == .pitch ? currentPitchHz : currentSpectrumPeak?.frequencyHz
    }

    func startOrResume() {
        guard sceneIsActive, state != .live, !isBusy else { return }
        stopAudio()
        installObservers()
        errorMessage = nil
        browsePage = nil
        cursorTime = presentation.duration
        state = .preparing
        refreshPresentation()
        let token = generation
        let owner = UUID()
        sessionOwner = owner
        awaitingPermission = true
        let renderSpectrogram = includesSpectrogram
        let previousTeardown = audioTeardown
        operation = Task { [weak self] in
            do {
                // The previous engine and its in-flight detector callback
                // must finish before reusing the analyzer or audio session.
                await previousTeardown?.value
                try Task.checkCancellation()
                guard let self, generation == token else { return }
                let granted = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
                }
                guard generation == token, !Task.isCancelled else { return }
                // Permission completion can arrive before the system dismisses
                // its prompt. Wait for the view's active event before opening
                // the microphone; background/leaving cancels this operation.
                while !sceneIsActive {
                    try await Task.sleep(for: .milliseconds(50))
                    guard generation == token else { return }
                }
                awaitingPermission = false
                guard granted else {
                    fail(String(localized: "recording.error.microphonePermissionDenied"))
                    return
                }

                var preparedAnalyzer: PitcheeCoreAnalyzer?
                if kind == .pitch {
                    let settings = AnalyzerSettings.current
                    if analyzer == nil || analyzerSettings != settings {
                        let loaded = try await Task.detached(priority: .userInitiated) {
                            try PitcheeCoreAnalyzer(settings: settings)
                        }.value
                        guard generation == token, !Task.isCancelled else { return }
                        analyzer = loaded
                        analyzerSettings = settings
                    }
                    preparedAnalyzer = analyzer
                    try await preparedAnalyzer?.resetRealtimeF0()
                }
                guard generation == token, !Task.isCancelled else { return }
                try await AudioSessionController.activate(owner: owner, use: .recording, holder: self)
                guard generation == token, !Task.isCancelled else {
                    AudioSessionController.deactivate(owner: owner)
                    return
                }

                let offset = presentation.duration
                // Resuming starts a fresh detector context; don't connect the
                // previous voiced segment across an interval with no capture.
                presentation.append(audio: [], pitch: [LivePitchSample(elapsedTime: offset, pitchHz: nil)], spectra: [])
                let newCapture = MonitorAudioCapture()
                capture = newCapture
                try await newCapture.start(
                    analyzer: preparedAnalyzer,
                    needsSpectrum: kind == .spectrum,
                    onUpdate: { [weak self] update in
                        guard !Task.isCancelled else { return }
                        // The capture worker calls this off MainActor. Render
                        // each new FFT column once, within its bounded delivery
                        // budget, so scrolling never repeats rasterization.
                        let columns = renderSpectrogram
                            ? Self.makeSpectrogramColumns(update.spectrumFrames, offset: offset) : []
                        await MainActor.run { [weak self] in
                            // First PCM can arrive before start resumes here.
                            guard let self, generation == token,
                                  state == .preparing || state == .live else { return }
                            append(update, columns: columns, offset: offset)
                        }
                    },
                    onError: { [weak self] error in
                        Self.logger.error("Monitor capture failed: \(String(describing: error), privacy: .private)")
                        Task { @MainActor [weak self] in
                            guard let self, generation == token else { return }
                            fail(String(localized: "monitor.error.capture"))
                        }
                    }
                )
                guard generation == token, !Task.isCancelled else { return }
                state = .live
                refreshPresentation()
                startDisplayClock(token: token)
            } catch {
                guard let self, generation == token, !Task.isCancelled else { return }
                Self.logger.error("Unable to start monitoring: \(String(describing: error), privacy: .private)")
                if error is AudioSessionCoordinator.Failure {
                    fail(String(localized: "monitor.error.sessionBusy"))
                } else {
                    fail(String(localized: "monitor.error.capture"))
                }
            }
        }
    }

    func pause() {
        if let player, let playbackRange {
            cursorTime = min(playbackRange.upperBound, playbackRange.lowerBound + player.currentTime)
        } else if playbackRange == nil, state == .live || state == .preparing {
            // Include already-delivered PCM since the last display tick.
            cursorTime = presentation.duration
        }
        let preserveReplaySelection = playbackRange != nil
            && (state == .preparing || state == .replaying)
        stopAudio(clearPlaybackRange: !preserveReplaySelection)
        refreshPresentation()
        state = hasAudio ? .paused : .idle
    }

    /// Called once when the slider gesture starts, before its first value
    /// update. This avoids repeatedly tearing down capture for every drag tick.
    func beginSeeking() {
        guard sceneIsActive, hasAudio, !isBusy else { return }
        if state == .live || state == .preparing || state == .replaying {
            pause()
        }
        playbackRange = nil
        playbackPage = nil
        resumesLiveAfterPlayback = false
        if browsePage == nil {
            browsePage = MonitorTimeline.browsePage(
                containing: cursorTime,
                duration: windowDuration,
                availableRange: availableRange
            )
        }
        refreshPresentation()
    }

    func seek(to time: TimeInterval) {
        guard sceneIsActive, hasAudio, !isBusy else { return }
        // A direct accessibility adjustment may not deliver onEditingChanged.
        if state == .live || state == .preparing || state == .replaying {
            beginSeeking()
        }
        playbackRange = nil
        playbackPage = nil
        resumesLiveAfterPlayback = false
        let selectedTime = MonitorTimeline.clampedTime(time, availableRange: availableRange)
        let page = MonitorTimeline.browsePage(
            containing: selectedTime,
            duration: windowDuration,
            availableRange: availableRange
        )
        if browsePage != page { browsePage = page }
        cursorTime = selectedTime
        refreshPresentation()
    }

    func rewindFiveSeconds() {
        // Rewind is a transport action, not just a cursor move: play from five
        // seconds earlier through the live tail.
        guard sceneIsActive, hasAudio, !isBusy, canRewind else { return }
        let shouldResumeLive = resumesLiveAfterPlayback
            || state == .live
            || (state == .preparing && playbackRange == nil)
        pause()
        browsePage = nil
        let tail = availableRange.upperBound
        let start = max(availableRange.lowerBound, min(cursorTime, tail) - 5)
        guard tail - start > 0.001 else {
            playbackRange = nil
            playbackPage = nil
            refreshPresentation()
            return
        }
        let audioRange = start...tail
        let page = MonitorTimeline.playbackPage(
            containing: start, duration: windowDuration,
            replayRange: audioRange, availableRange: availableRange
        )
        beginPlayback(
            audioRange: audioRange, startingAt: start, page: page,
            resumesLive: shouldResumeLive
        )
    }

    func setWindowDuration(_ seconds: TimeInterval) {
        guard Self.windowDurations.contains(seconds) else { return }
        let keepsBrowsePage = browsePage != nil
        if state == .replaying || state == .preparing { pause() }
        playbackRange = nil
        playbackPage = nil
        browsePage = nil
        resumesLiveAfterPlayback = false
        windowDuration = seconds
        UserDefaults.standard.set(seconds, forKey: AppStorageKey.monitorWindowDuration)
        if keepsBrowsePage, hasAudio {
            browsePage = MonitorTimeline.browsePage(
                containing: cursorTime,
                duration: windowDuration,
                availableRange: availableRange
            )
        }
        refreshPresentation()
    }

    /// Toggles the compact transport's middle control. A paused replay keeps
    /// its original audio range so continuing starts at the current playhead
    /// rather than rebuilding the range from scratch.
    func toggleReplay() {
        guard sceneIsActive, hasAudio, !isBusy else { return }
        if state == .replaying {
            pause()
            return
        }
        if let playbackRange,
           state == .paused,
           cursorTime >= playbackRange.lowerBound,
           cursorTime < playbackRange.upperBound - 0.001 {
            let page = MonitorTimeline.playbackPage(
                containing: cursorTime, duration: windowDuration,
                replayRange: playbackRange, availableRange: availableRange
            )
            beginPlayback(
                audioRange: playbackRange,
                startingAt: cursorTime,
                page: page,
                resumesLive: resumesLiveAfterPlayback
            )
            return
        }
        browsePage = nil
        replayFromCursor()
    }

    private func replayFromCursor() {
        guard sceneIsActive, hasAudio, !isBusy else { return }
        let shouldResumeLive = state == .live
            || (state == .preparing && playbackRange == nil)
        pause()
        browsePage = nil
        let tail = availableRange.upperBound
        let cursor = MonitorTimeline.clampedTime(cursorTime, availableRange: availableRange)
        let start = cursor >= tail - 0.05
            ? max(availableRange.lowerBound, tail - windowDuration)
            : cursor
        guard tail - start > 0.001 else {
            playbackRange = nil
            playbackPage = nil
            resumesLiveAfterPlayback = false
            refreshPresentation()
            return
        }
        let audioRange = start...tail
        let page = MonitorTimeline.playbackPage(
            containing: start, duration: windowDuration,
            replayRange: audioRange, availableRange: availableRange
        )
        beginPlayback(
            audioRange: audioRange, startingAt: start, page: page,
            resumesLive: shouldResumeLive
        )
    }

    private func beginPlayback(
        audioRange: ClosedRange<TimeInterval>,
        startingAt: TimeInterval,
        page: ClosedRange<TimeInterval>,
        resumesLive: Bool
    ) {
        // Encode the whole tail once so playback is gapless across chart pages.
        let samples = presentation.audio(in: audioRange)
        guard !samples.isEmpty else {
            playbackRange = nil
            playbackPage = nil
            resumesLiveAfterPlayback = false
            refreshPresentation()
            return
        }
        installObservers()
        errorMessage = nil
        let token = generation
        let owner = UUID()
        sessionOwner = owner
        state = .preparing
        playbackRange = audioRange
        playbackPage = page
        resumesLiveAfterPlayback = resumesLive
        let initialTime = min(audioRange.upperBound, max(audioRange.lowerBound, startingAt))
        cursorTime = initialTime
        refreshPresentation()
        let previousTeardown = audioTeardown
        operation = Task { [weak self] in
            do {
                await previousTeardown?.value
                try Task.checkCancellation()
                guard let self, generation == token else { return }
                let data = await Task.detached(priority: .userInitiated) {
                    MonitorWaveEncoder.encode(samples)
                }.value
                try Task.checkCancellation()
                try await AudioSessionController.activate(owner: owner, use: .playback, holder: self) { [weak self] in
                    self?.pause()
                }
                guard generation == token, !Task.isCancelled else {
                    AudioSessionController.deactivate(owner: owner)
                    return
                }
                let audioPlayer = try AVAudioPlayer(data: data)
                let delegate = MonitorPlaybackDelegate { [weak self] successful in
                    guard let self, generation == token else { return }
                    if successful {
                        let shouldResumeLive = resumesLiveAfterPlayback
                        cursorTime = audioRange.upperBound
                        stopAudio()
                        state = .paused
                        refreshPresentation()
                        if shouldResumeLive, sceneIsActive {
                            startOrResume()
                        }
                    } else {
                        fail(String(localized: "monitor.error.playback"))
                    }
                }
                playerDelegate = delegate
                audioPlayer.delegate = delegate
                player = audioPlayer
                audioPlayer.currentTime = min(
                    audioPlayer.duration,
                    max(0, initialTime - audioRange.lowerBound)
                )
                let played = await Task.detached(priority: .userInitiated) {
                    audioPlayer.play()
                }.value
                guard played else { throw CocoaError(.fileReadUnknown) }
                guard generation == token, !Task.isCancelled else {
                    audioPlayer.stop()
                    AudioSessionController.deactivate(owner: owner)
                    return
                }
                cursorTime = initialTime
                state = .replaying
                refreshPresentation()
                startPlaybackClock(token: token, range: audioRange)
            } catch {
                AudioSessionController.deactivate(owner: owner)
                guard let self, generation == token, !Task.isCancelled else { return }
                fail(String(localized: error is AudioSessionCoordinator.Failure
                    ? "monitor.error.sessionBusy" : "monitor.error.playback"))
            }
        }
    }

    func handleSceneInactive() {
        // The system permission prompt also makes the scene inactive.
        sceneIsActive = false
        if !awaitingPermission { pause() }
    }

    func handleSceneActive() {
        sceneIsActive = true
    }

    func stopForLeaving() {
        pause()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        // Monitoring audio is ephemeral, never a saved recording.
        presentation.reset(windowDuration: windowDuration, includesPitch: kind == .pitch)
        cursorTime = 0
        playbackRange = nil
        playbackPage = nil
        browsePage = nil
        resumesLiveAfterPlayback = false
        analyzer = nil
        analyzerSettings = nil
        errorMessage = nil
        state = .idle
    }

    func clearError() { errorMessage = nil }

    nonisolated private static func makeSpectrogramColumns(
        _ frames: [MonitorSpectrumFrame], offset: TimeInterval = 0
    ) -> [MonitorSpectrogramColumn] {
        frames.compactMap { frame in
            guard let image = MonitorSpectrogramRasterizer.makeColumn(frame: frame) else { return nil }
            return MonitorSpectrogramColumn(elapsedTime: frame.elapsedTime + offset, image: image)
        }
    }

    private func append(
        _ update: MonitorCaptureUpdate, columns: [MonitorSpectrogramColumn], offset: TimeInterval
    ) {
        presentation.append(audio: update.samples, pitch: update.pitchFrames.map {
            LivePitchSample(elapsedTime: offset + $0.elapsedTime, pitchHz: $0.pitchHz)
        }, spectra: update.spectrumFrames.map {
            $0.offset(by: offset)
        }, columns: columns)
        needsPresentation = true
    }

    private func refreshPresentation() {
        if state == .live { cursorTime = presentation.duration }
        presentation.publish(
            cursorTime: cursorTime, windowDuration: windowDuration,
            selectedRange: playbackPage ?? browsePage, includesPitch: kind == .pitch
        )
        needsPresentation = false
    }

    private func startDisplayClock(token: UUID) {
        displayClock?.cancel()
        // Use elapsed wall time rather than capture timestamps: a burst of
        // queued PCM must not turn into an equally large burst of UI updates.
        let f0Rate = max(
            20,
            min(
                60,
                UserDefaults.standard.object(forKey: AnalyzerSettingsKey.f0SampleRate) as? Int ?? 30
            )
        )
        let interval: Duration = kind == .pitch
            ? .milliseconds(Int64(max(1, 1_000 / f0Rate)))
            : .milliseconds(100)
        displayClock = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, generation == token, state == .live else { return }
                if needsPresentation { refreshPresentation() }
            }
        }
    }

    private func startPlaybackClock(token: UUID, range: ClosedRange<TimeInterval>) {
        playbackClock?.cancel()
        playbackClock = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                guard let self, generation == token, state == .replaying, let player else { return }
                let next = min(range.upperBound, range.lowerBound + player.currentTime)
                cursorTime = next
                let page = MonitorTimeline.playbackPage(
                    containing: next, duration: windowDuration,
                    replayRange: range, availableRange: availableRange
                )
                if playbackPage != page { playbackPage = page }
                refreshPresentation()
                if next >= range.upperBound - 0.001 { return }
            }
        }
    }

    private func stopAudio(clearPlaybackRange: Bool = true) {
        generation = UUID()
        awaitingPermission = false
        operation?.cancel()
        operation = nil
        playbackClock?.cancel()
        playbackClock = nil
        displayClock?.cancel()
        displayClock = nil
        if let capture, let sessionOwner {
            AudioSessionController.retainUntilStopped(owner: sessionOwner, holder: capture)
        }
        let captureTeardown = capture?.stop()
        capture = nil
        player?.stop()
        player = nil
        playerDelegate = nil
        if clearPlaybackRange {
            playbackRange = nil
            playbackPage = nil
            resumesLiveAfterPlayback = false
        }
        let owner = sessionOwner
        sessionOwner = nil
        if let captureTeardown {
            let previousTeardown = audioTeardown
            // Teardown includes onUpdate, which needs MainActor. Wait in this
            // independent task before releasing the old recording session.
            audioTeardown = Task {
                await previousTeardown?.value
                await captureTeardown.value
                if let owner { AudioSessionController.deactivate(owner: owner) }
            }
        } else if let owner {
            // Playback can release synchronously for coordinator handoff.
            AudioSessionController.deactivate(owner: owner)
        }
    }

    private func fail(_ message: String) {
        pause()
        errorMessage = message
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                // A category change is part of our own capture/playback switch.
                if notification.name == AVAudioSession.routeChangeNotification {
                    let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    guard value == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                        || value == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
                        || value == AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue else { return }
                }
                if notification.name == AVAudioSession.interruptionNotification {
                    let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    guard value == AVAudioSession.InterruptionType.began.rawValue else { return }
                }
                // Delivery is already on .main. Deferring this could pause a
                // new capture started after the interruption was handled.
                MainActor.assumeIsolated { self?.pause() }
            }
            observers.append(observer)
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        stopAudio()
    }

    #if DEBUG
    /// Isolated fixtures for previews and the opt-in simulator review launch argument.
    /// No microphone, audio session, or persistent data is used.
    static func preview(kind: MonitorKind, includesSpectrogram: Bool = false) -> MonitorViewModel {
        if includesSpectrogram { return spectrogramPreview(kind: kind) }
        let model = MonitorViewModel(kind: kind)
        let sampleRate = MonitorTimeline.sampleRate
        let samples: [Float] = (0..<Int(sampleRate * 12)).map { index in
            let time = Double(index) / sampleRate
            return Float(sin(2 * .pi * 196 * time) * 0.16 + sin(2 * .pi * 392 * time) * 0.05)
        }
        let pitches = (0...120).map { index in
            let time = Double(index) * 0.1
            let pitch = (42...49).contains(index) || (84...90).contains(index)
                ? nil : 196 + sin(time * 1.6) * 14 + sin(time * 4.1) * 3
            return LivePitchSample(elapsedTime: time, pitchHz: pitch)
        }
        let analyzer = try! MonitorSpectrumAnalyzer()
        model.presentation.append(audio: samples, pitch: pitches, spectra: analyzer.process(samples))
        model.cursorTime = 11.9
        model.state = .paused
        model.refreshPresentation()
        return model
    }

    private static func spectrogramPreview(kind: MonitorKind) -> MonitorViewModel {
        let model = MonitorViewModel(kind: kind, includesSpectrogram: true)
        let sampleRate = MonitorTimeline.sampleRate
        func pitch(at time: TimeInterval) -> Double? {
            let phraseTime = time.truncatingRemainder(dividingBy: 3.2)
            guard (0.22..<2.55).contains(phraseTime) else { return nil }
            let progress = (phraseTime - 0.22) / 2.33
            return 188 + 44 * sin(progress * .pi) + 4 * sin(time * 4.1)
        }
        // Integrate the changing fundamental into phase so its harmonics bend
        // together. Short fades keep pauses from adding artificial click bands.
        var phase = 0.0
        let samples: [Float] = (0..<Int(sampleRate * 12)).map { index in
            let time = Double(index) / sampleRate
            let frequency = pitch(at: time)
            phase += 2 * .pi * (frequency ?? 188) / sampleRate
            guard frequency != nil else { return 0 }
            let phraseTime = time.truncatingRemainder(dividingBy: 3.2)
            let envelope = min(1, (phraseTime - 0.22) / 0.04, (2.55 - phraseTime) / 0.06)
            let signal = sin(phase) * 0.22 + sin(2 * phase) * 0.10
                + sin(3 * phase) * 0.055 + sin(4 * phase) * 0.028
                + sin(5 * phase) * 0.015 + sin(7 * phase) * 0.008
            return Float(signal * envelope)
        }
        let pitches = (0...120).map { index in
            let time = Double(index) * 0.1
            return LivePitchSample(elapsedTime: time, pitchHz: pitch(at: time))
        }
        let analyzer = try! MonitorSpectrumAnalyzer()
        let spectra = analyzer.process(samples)
        model.presentation.append(audio: samples, pitch: pitches, spectra: spectra,
                                  columns: Self.makeSpectrogramColumns(spectra))
        model.cursorTime = 11.9
        model.state = .paused
        model.refreshPresentation()
        return model
    }
    #endif
}

private final class MonitorPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let completion: @MainActor (Bool) -> Void

    init(completion: @escaping @MainActor (Bool) -> Void) {
        self.completion = completion
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.completion(flag) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.completion(false) }
    }
}
