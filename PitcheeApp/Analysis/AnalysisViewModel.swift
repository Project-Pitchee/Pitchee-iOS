//
//  AnalysisViewModel.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/13.
//

import AVFoundation
import Combine
import Foundation
import OSLog
import SwiftData
#if os(iOS)
import UIKit
#endif

@MainActor
final class AnalysisViewModel: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "com.lvyzhan.Pitchee", category: "Analysis")
    private static let livePitchRetention: TimeInterval = 30
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case awaitingFeedback
        case analyzing
        case completed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var livePitchSamples: [LivePitchSample] = []
    @Published private(set) var result: PitcheeAnalysisResult?
    @Published private(set) var volumeStatistics: RecordingVolumeStatistics?
    @Published private(set) var studyFeedbackDirection: ScoreStudyDirection?
    // Recording alerts and analysis feedback belong to separate screens.
    @Published private(set) var recordingError: String?
    @Published private(set) var analysisError: String?
    @Published private(set) var captureNotice: String?
    @Published private(set) var assessment: RecordingAssessment?

    @discardableResult
    func prepareRetake() -> Bool {
        guard state == .completed else { return false }
        result = nil
        assessment = nil
        volumeStatistics = nil
        elapsedTime = 0
        livePitchSamples = []
        captureNotice = nil
        state = .idle
        return true
    }

    /// End this take at the interruption. Accepted PCM is drained into a valid
    /// WAV, and analysis resumes in the foreground without reopening the mic.
    func interruptCapture() {
        if let context = recordingModelContext, audioCapture != nil, recordingURL != nil,
           state == .recording || state == .requestingPermission {
            captureGeneration = UUID()
            permissionTask?.cancel()
            stopRecording(modelContext: context, interrupted: true)
            return
        }
        cancelRecording(message: String(localized: "practice.recording.interrupted"))
    }

    func handleSceneInactive(isBackground: Bool) {
        sceneIsActive = false
        // A microphone permission prompt temporarily makes the scene inactive.
        // Going to the background still cancels that pending request.
        if isBackground || !awaitingPermission { interruptCapture() }
    }

    func handleSceneActive() {
        sceneIsActive = true
        if let pendingRecording {
            self.pendingRecording = nil
            completeRecording(pendingRecording.url, recordedAt: pendingRecording.recordedAt,
                              modelContext: pendingRecording.modelContext,
                              studyAuthorization: nil, studyDirection: nil)
        }
    }

    private func cancelRecording(message: String) {
        guard state == .recording || state == .requestingPermission else { return }
        captureGeneration = UUID()
        permissionTask?.cancel()
        stopTimer()
        let hadCapture = audioCapture != nil
        discardCapture(audioCapture, url: recordingURL)
        audioCapture = nil
        recordingURL = nil
        recordingStartedAt = nil
        recordingStudyAuthorization = nil
        recordingStudyDirection = nil
        recordingModelContext = nil
        awaitingPermission = false
        if hadCapture { audioSessionOwner = nil }
        else { deactivateAudioSession() }
        showRecordingError(message)
    }

    private var audioCapture: LivePitchAudioCapture?
    private var recordingURL: URL?
    private var recordingStartedAt: Date?
    private var timerTask: Task<Void, Never>?
    private var analyzer: PitcheeCoreAnalyzer?
    private var analyzerPreparationTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var recordingStopTask: Task<Void, Never>?
    private var captureCleanupTask: Task<Void, Never>?
    private var captureGeneration = UUID()
    private var audioSessionOwner: UUID?
    private var recordingStudyAuthorization: LocalScoreStudyStore.Authorization?
    private var recordingStudyDirection: ScoreStudyDirection?
    private var feedbackTimeoutTask: Task<Void, Never>?
    private var pendingStudy: PendingStudy?
    private var recordingModelContext: ModelContext?
    private var pendingRecording: PendingRecording?
    private var sceneIsActive = true
    private var awaitingPermission = false
    private var observers: [NSObjectProtocol] = []

    private struct PendingRecording {
        let url: URL
        let recordedAt: Date
        let modelContext: ModelContext
    }

    private struct PendingStudy {
        let url: URL
        let recordedAt: Date
        let modelContext: ModelContext
        let attempt: LocalScoreStudyStore.Attempt
    }

    #if DEBUG
    private var usesPreviewData = false
    #endif

    var isRequestingPermission: Bool {
        state == .requestingPermission
    }

    var isRecording: Bool {
        state == .recording
    }

    var isAnalyzing: Bool {
        state == .analyzing
    }

    var isAwaitingFeedback: Bool { state == .awaitingFeedback }
    var needsAnalysisScreen: Bool { isAnalyzing || isAwaitingFeedback }

    var hasResult: Bool {
        result != nil && state == .completed
    }

    /// Load the native model before the user starts a take. The work runs at
    /// utility priority so entering the page stays responsive, and a later
    /// tap only needs to reset the realtime stream and open the microphone.
    func prepareForRecording() {
        guard state == .idle, analyzer == nil, analyzerPreparationTask == nil else { return }
        analyzerPreparationTask = Task { [weak self] in
            guard let self else { return }
            guard let analyzer = try? await self.preparedAnalyzer() else { return }
            // Allocate the realtime detector while the page is idle. The
            // recording tap can then reset an existing stream instead of
            // creating native state during the button interaction.
            try? await analyzer.resetRealtimeF0()
        }
    }

    func primaryButtonTapped(modelContext: ModelContext) {
        #if DEBUG
        if usesPreviewData {
            switch state {
            case .idle, .completed:
                applyPreviewState(.recording)
            case .recording:
                applyPreviewState(.completed)
            case .requestingPermission, .awaitingFeedback, .analyzing:
                break
            }
            return
        }
        #endif

        switch state {
        case .recording:
            stopRecording(modelContext: modelContext)
        case .idle, .completed:
            startRecording(modelContext: modelContext)
        case .requestingPermission, .awaitingFeedback, .analyzing:
            break
        }
    }

    func clearRecordingError() {
        recordingError = nil
    }

    private func startRecording(modelContext: ModelContext) {
        guard sceneIsActive else { return }
        if state == .completed, !prepareRetake() { return }
        recordingStudyAuthorization = LocalScoreStudyStore.shared.authorizeRecording()
        // Ordinary recordings have no directed-practice context. Preserve
        // their existing exclusion from the direction-specific study cohort.
        recordingStudyDirection = ScoreStudyEvaluator.direction(for: .undecided)
        recordingError = nil
        analysisError = nil
        captureNotice = nil
        recordingModelContext = modelContext
        result = nil
        elapsedTime = 0
        livePitchSamples = []
        volumeStatistics = nil
        recordingStartedAt = nil
        state = .requestingPermission
        awaitingPermission = true
        installObservers()
        let generation = UUID()
        captureGeneration = generation

        permissionTask = Task { [weak self] in
            guard let self else { return }
            let granted = await requestMicrophonePermission()
            guard !Task.isCancelled, captureGeneration == generation else { return }

            // Permission completion can precede dismissal of the system prompt.
            while !sceneIsActive {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard captureGeneration == generation else { return }
            }
            awaitingPermission = false

            if granted {
                await beginRecording(generation: generation)
            } else {
                recordingModelContext = nil
                showRecordingError(String(localized: "recording.error.microphonePermissionDenied"))
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func beginRecording(generation: UUID) async {
        guard state == .requestingPermission, captureGeneration == generation else { return }
        let owner = UUID()
        var startedCapture: LivePitchAudioCapture?
        var startedURL: URL?

        do {
            // A previous cancellation closes its WAV and engine before the next
            // take opens the microphone. Waiting here leaves the UI responsive.
            await captureCleanupTask?.value
            guard isCurrentRecordingRequest(generation) else { return }
            if let preparationTask = analyzerPreparationTask {
                await preparationTask.value
                analyzerPreparationTask = nil
            }
            guard isCurrentRecordingRequest(generation) else { return }
            let analyzer = try await preparedAnalyzer()
            guard isCurrentRecordingRequest(generation) else { return }
            try await analyzer.resetRealtimeF0()
            guard isCurrentRecordingRequest(generation) else { return }
            audioSessionOwner = owner
            try await AudioSessionController.activate(
                owner: owner,
                use: .recording,
                holder: self
            )
            guard isCurrentRecordingRequest(generation) else {
                releaseAudioSession(owner)
                return
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pitchee-\(UUID().uuidString)")
                .appendingPathExtension("wav")
            let newCapture = LivePitchAudioCapture()
            startedCapture = newCapture
            startedURL = url
            recordingURL = url
            audioCapture = newCapture
            recordingStartedAt = Date()
            let onPitch: @Sendable ([PitcheeF0Frame]) -> Void = { [weak self] frames in
                Task { @MainActor [weak self] in
                    guard let self, self.captureGeneration == generation,
                          self.state == .recording || self.state == .requestingPermission,
                          self.recordingURL == url else { return }
                    self.appendLivePitch(frames)
                }
            }
            let onError: @Sendable (Error) -> Void = { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.captureGeneration == generation,
                          self.state == .recording || self.state == .requestingPermission,
                          self.recordingURL == url else { return }
                    Self.logger.error("Realtime F0 failed: \(String(describing: error), privacy: .private)")
                    self.recordingError = String(localized: "recording.error.realtimePitchUnavailable")
                }
            }
            let onRecordingError: @Sendable (Error) -> Void = { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.captureGeneration == generation, self.recordingURL == url else { return }
                    Self.logger.error("Recording capture failed: \(String(describing: error), privacy: .private)")
                    self.cancelRecording(message: String(localized: "recording.error.saveFailed"))
                }
            }

            try await Task.detached(priority: .userInitiated) {
                try newCapture.start(
                    writingTo: url,
                    analyzer: analyzer,
                    onPitch: onPitch,
                    onError: onError,
                    onRecordingError: onRecordingError
                )
            }.value
            guard isCurrentRecordingRequest(generation) else {
                // Cancellation/interruption owns teardown, including a take
                // finalized while this detached engine startup was pending.
                return
            }
            state = .recording
            startTimer()
        } catch {
            guard captureGeneration == generation else { return }
            discardCapture(startedCapture, url: startedURL)
            // An obsolete startup must not clear a newer recording's state.
            guard !Task.isCancelled, captureGeneration == generation else { return }
            audioCapture = nil
            recordingURL = nil
            recordingStartedAt = nil
            recordingModelContext = nil
            // No engine exists if startup failed before constructing capture.
            if startedCapture == nil { releaseAudioSession(owner) }
            else if audioSessionOwner == owner { audioSessionOwner = nil }
            stopTimer()
            showRecordingError(recordingErrorMessage(for: error))
        }
    }

    private func isCurrentRecordingRequest(_ generation: UUID) -> Bool {
        !Task.isCancelled && captureGeneration == generation && state == .requestingPermission
    }

    private func stopRecording(modelContext: ModelContext, interrupted: Bool = false) {
        guard state == .recording || state == .requestingPermission,
              let audioCapture, let url = recordingURL else { return }
        stopTimer()
        let recordedAt = recordingStartedAt ?? Date()
        elapsedTime = Date().timeIntervalSince(recordedAt)
        let generation = captureGeneration
        let owner = audioSessionOwner
        let studyAuthorization = recordingStudyAuthorization
        let studyDirection = recordingStudyDirection
        if let owner { AudioSessionController.retainUntilStopped(owner: owner, holder: audioCapture) }
        self.audioCapture = nil
        recordingURL = nil
        recordingStartedAt = nil
        recordingStudyAuthorization = nil
        recordingStudyDirection = nil
        recordingModelContext = nil
        awaitingPermission = false
        clearRecordingError()
        if interrupted { captureNotice = String(localized: "recording.interruption.saved") }
        state = .analyzing

        #if os(iOS)
        // Only finishing accepted writes needs background time. The microphone
        // stops immediately, and protected-file analysis waits for foreground.
        let backgroundTask = CaptureBackgroundTask()
        #endif

        recordingStopTask = Task { [weak self] in
            // Stop hardware and finish accepted writes before Core sees the WAV.
            // The analysis screen can render while this drains off the main actor.
            let writeError = await audioCapture.finish()
            #if os(iOS)
            backgroundTask.end()
            #endif
            if let owner { AudioSessionController.deactivate(owner: owner) }
            guard let self, !Task.isCancelled, self.captureGeneration == generation else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            if self.audioSessionOwner == owner { self.audioSessionOwner = nil }
            self.recordingStopTask = nil
            if let writeError {
                Self.logger.error("Recording write failed: \(String(describing: writeError), privacy: .private)")
                try? FileManager.default.removeItem(at: url)
                self.analysisError = String(localized: "recording.error.saveFailed")
                self.state = .idle
                return
            }
            if !self.sceneIsActive {
                self.pendingRecording = PendingRecording(url: url, recordedAt: recordedAt,
                                                         modelContext: modelContext)
            } else {
                self.completeRecording(url, recordedAt: recordedAt, modelContext: modelContext,
                                       studyAuthorization: interrupted ? nil : studyAuthorization,
                                       studyDirection: interrupted ? nil : studyDirection)
            }
        }
    }

    private func completeRecording(
        _ recordingURL: URL,
        recordedAt: Date,
        modelContext: ModelContext,
        studyAuthorization: LocalScoreStudyStore.Authorization?,
        studyDirection: ScoreStudyDirection?
    ) {
        let invitation = LocalScoreStudyStore.shared.invite(
            authorizedBy: studyAuthorization, direction: studyDirection
        )
        if let invitation {
            pendingStudy = PendingStudy(url: recordingURL, recordedAt: recordedAt,
                                        modelContext: modelContext, attempt: invitation)
            studyFeedbackDirection = invitation.direction
            state = .awaitingFeedback
            feedbackTimeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(LocalScoreStudyState.feedbackSeconds)) } catch { return }
                self?.submitStudyFeedback(.timedOut)
            }
            return
        }
        state = .analyzing
        analyze(recordingURL, recordedAt: recordedAt, modelContext: modelContext)
    }

    func submitStudyFeedback(_ feedback: ScoreStudyFeedback) {
        #if DEBUG
        if usesPreviewData, isAwaitingFeedback {
            studyFeedbackDirection = nil
            applyPreviewState(.completed)
            return
        }
        #endif
        guard let pendingStudy else { return }
        self.pendingStudy = nil
        feedbackTimeoutTask?.cancel()
        feedbackTimeoutTask = nil
        studyFeedbackDirection = nil
        LocalScoreStudyStore.shared.respond(pendingStudy.attempt, feedback: feedback)
        state = .analyzing
        analyze(pendingStudy.url, recordedAt: pendingStudy.recordedAt,
                modelContext: pendingStudy.modelContext, studyAttempt: pendingStudy.attempt)
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                // Elapsed-time text has its own low-frequency subscription;
                // the pitch chart advances independently with detector frames.
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard let self,
                      self.state == .recording,
                      let recordingStartedAt = self.recordingStartedAt else { return }
                elapsedTime = Date().timeIntervalSince(recordingStartedAt)
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func appendLivePitch(_ frames: [PitcheeF0Frame]) {
        guard !frames.isEmpty else { return }
        let samples = frames.map { LivePitchSample(elapsedTime: $0.elapsedTime, pitchHz: $0.pitchHz) }
        // Capture already coalesces delivery at the chart's display cadence. Trim
        // the rolling window before publishing it so a batch invalidates the
        // observing views once, with no second main-actor throttle or buffer.
        let newestTime = samples.last?.elapsedTime ?? 0
        let oldestVisibleTime = max(0, newestTime - Self.livePitchRetention)
        var visible = livePitchSamples
        visible.append(contentsOf: samples)
        let firstVisibleIndex = TimelineSearch.lowerBound(in: visible, at: oldestVisibleTime, time: \.elapsedTime)
        if firstVisibleIndex > 0 { visible.removeFirst(firstVisibleIndex) }
        livePitchSamples = visible
    }

    private func deactivateAudioSession() {
        guard let owner = audioSessionOwner else { return }
        releaseAudioSession(owner)
    }

    private func releaseAudioSession(_ owner: UUID) {
        AudioSessionController.deactivate(owner: owner)
        if audioSessionOwner == owner { audioSessionOwner = nil }
    }

    private func discardCapture(_ capture: LivePitchAudioCapture?, url: URL?) {
        guard capture != nil || url != nil else { return }
        let previousCleanup = captureCleanupTask
        let owner = audioSessionOwner
        if let capture, let owner {
            AudioSessionController.retainUntilStopped(owner: owner, holder: capture)
        }
        let cancellation = capture?.cancel()
        captureCleanupTask = Task.detached(priority: .utility) {
            await previousCleanup?.value
            if let cancellation { _ = await cancellation.value }
            if let url { try? FileManager.default.removeItem(at: url) }
            if let owner { await AudioSessionController.deactivate(owner: owner) }
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                if notification.name == AVAudioSession.interruptionNotification {
                    let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
                }
                if notification.name == AVAudioSession.routeChangeNotification {
                    let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    // Ignore category changes generated by our own activation.
                    guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                        || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
                        || reason == AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue else { return }
                }
                // NotificationCenter delivers on .main; handle this event now
                // so a queued task cannot interrupt a later recording attempt.
                MainActor.assumeIsolated { self?.interruptCapture() }
            })
        }
    }

    private func analyze(
        _ url: URL,
        recordedAt: Date,
        modelContext: ModelContext,
        studyAttempt: LocalScoreStudyStore.Attempt? = nil
    ) {
        analysisTask?.cancel()
        let analysisProfile: PitcheeScoreProfile = {
            let preference = VoicePreference(legacyStoredValue: UserDefaults.standard.string(forKey: AppStorageKey.voicePreference) ?? "")
                ?? .undecided
            return preference == .masculine ? .masculinization : .feminization
        }()
        let diagnostics = LocalDiagnosticsStore.shared
        let diagnosticToken = diagnostics.beginAttempt()
        let recordedSeconds = elapsedTime
        let startedAt = ProcessInfo.processInfo.systemUptime
        analysisTask = Task { [weak self] in
            var diagnosticOutcome = DiagnosticOutcome.interrupted
            var inputSeconds: Double? = recordedSeconds
            var speechSeconds: Double?
            var quality = DiagnosticQuality.unavailable
            var studyPair: ScoreStudyPair?
            var studyFailed = true
            defer {
                try? FileManager.default.removeItem(at: url)
                LocalScoreStudyStore.shared.finish(studyAttempt, pair: studyPair, failed: studyFailed)
                diagnostics.finish(diagnosticToken, outcome: diagnosticOutcome, observation: .init(
                    inputSeconds: inputSeconds, speechSeconds: speechSeconds, quality: quality,
                    latencySeconds: ProcessInfo.processInfo.systemUptime - startedAt
                ))
            }
            guard let self else { diagnosticOutcome = .cancelled; return }

            do {
                try Task.checkCancellation()
                let analyzer = try await preparedAnalyzer()

                let analysisResult = try await analyzer.analyze(
                    wavFile: url,
                    scoreProfile: analysisProfile
                )
                try Task.checkCancellation()
                if let studyAttempt {
                    studyPair = ScoreStudyEvaluator.pair(for: analysisResult, direction: studyAttempt.direction)
                }
                inputSeconds = analysisResult.audio.inputSeconds
                speechSeconds = analysisResult.vad.speechSeconds
                let volumeStatistics: RecordingVolumeStatistics?
                do {
                    volumeStatistics = try await Task.detached(priority: .userInitiated) {
                        try RecordingVolumeAnalyzer.analyze(
                            wavFile: url,
                            speechSegments: analysisResult.vad.segments
                        )
                    }.value
                } catch {
                    Self.logger.error(
                        "Volume analysis failed: \(String(describing: error), privacy: .private)"
                    )
                    volumeStatistics = nil
                }
                try Task.checkCancellation()
                if diagnosticToken != nil, let volumeStatistics {
                    // Only actual non-speech windows count as background. The UI's
                    // quietest-voice fallback would imply a nonexistent noise reference.
                    let background = volumeStatistics.windows.compactMap(\.backgroundDBFS).sorted()
                    quality = DiagnosticQuality(
                        speechDBFS: volumeStatistics.medianDBFS,
                        backgroundDBFS: RecordingStatisticsMath.percentile(0.5, in: background)
                    )
                }
                result = analysisResult
                self.volumeStatistics = volumeStatistics
                let recordingQuality = RecordingQuality(
                    speechSeconds: analysisResult.vad.speechSeconds,
                    speechDBFS: volumeStatistics?.medianDBFS,
                    backgroundDBFS: volumeStatistics?.measuredBackgroundDBFS,
                    clippedFraction: volumeStatistics?.clippedSampleFraction
                )
                diagnosticOutcome = .success
                studyFailed = false

                do {
                    let assessment = try RecordingAssessment(
                        recordedAt: recordedAt,
                        result: analysisResult,
                        quality: recordingQuality
                    )
                    self.assessment = assessment
                    modelContext.insert(assessment)
                    do {
                        try modelContext.save()
                    } catch {
                        modelContext.delete(assessment)
                        throw error
                    }
                } catch {
                    diagnosticOutcome = .historySaveFailed
                    analysisError = String(localized: "analysis.error.resultSaveFailed")
                }
                state = .completed
            } catch {
                diagnosticOutcome = Self.diagnosticOutcome(for: error)
                Self.logger.error("Analysis failed: \(String(describing: error), privacy: .private)")
                result = nil
                volumeStatistics = nil
                state = .idle
                if !(error is CancellationError) { analysisError = analysisErrorMessage(for: error) }
            }
        }
    }

    private static func diagnosticOutcome(for error: Error) -> DiagnosticOutcome {
        if error is CancellationError { return .cancelled }
        guard let error = error as? PitcheeCoreError else { return .analysisFailed }
        switch error.statusCode {
        case 5: return .noSpeech
        case 2, 6: return .unreadableAudio
        case 3, 4: return .modelUnavailable
        default: return .analysisFailed
        }
    }

    private func preparedAnalyzer() async throws -> PitcheeCoreAnalyzer {
        if let analyzer { return analyzer }
        let analyzer = try await Task.detached(priority: .utility) {
            try PitcheeCoreAnalyzer()
        }.value
        self.analyzer = analyzer
        return analyzer
    }

    private func showRecordingError(_ message: String) {
        recordingError = message
        if state != .analyzing {
            state = .idle
        }
    }

    private func recordingErrorMessage(for error: Error) -> String {
        if error is PitcheeCoreError {
            return analysisErrorMessage(for: error)
        }
        if error is LivePitchAudioCaptureError {
            return String(localized: "recording.error.microphoneUnavailable")
        }
        return String(localized: "recording.error.startFailed")
    }

    private func analysisErrorMessage(for error: Error) -> String {
        guard let coreError = error as? PitcheeCoreError else {
            return String(localized: "analysis.error.resultUnreadable")
        }

        switch coreError.statusCode {
        case 5: // PITCHEE_ERROR_NO_SPEECH
            return String(localized: "analysis.error.noSpeechDetected")
        case 3, 4: // PITCHEE_ERROR_ORT_UNAVAILABLE, PITCHEE_ERROR_MODEL
            return String(localized: "analysis.error.modelUnavailable \(coreError.statusCode)")
        case 2, 6: // PITCHEE_ERROR_IO, PITCHEE_ERROR_UNSUPPORTED_FORMAT
            return String(localized: "analysis.error.recordingUnreadable \(coreError.statusCode)")
        default:
            return String(localized: "analysis.error.analysisFailed \(coreError.statusCode)")
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        permissionTask?.cancel()
        timerTask?.cancel()
        analysisTask?.cancel()
        analyzerPreparationTask?.cancel()
        feedbackTimeoutTask?.cancel()
        recordingStopTask?.cancel()
        discardCapture(audioCapture, url: recordingURL)
        if audioCapture == nil, recordingStopTask == nil { deactivateAudioSession() }
        if let pendingRecording { try? FileManager.default.removeItem(at: pendingRecording.url) }
        if let pendingStudy { try? FileManager.default.removeItem(at: pendingStudy.url) }
    }
}

#if os(iOS)
@MainActor
private final class CaptureBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish recording") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }

    isolated deinit { end() }
}
#endif

#if DEBUG
extension AnalysisViewModel {
    /// Supplies real UI states without requesting microphone permission,
    /// loading inference models, starting timers, or saving assessments.
    static func preview(state: State = .idle) -> AnalysisViewModel {
        let model = AnalysisViewModel()
        model.usesPreviewData = true
        model.applyPreviewState(state)
        return model
    }

    private func applyPreviewState(_ state: State) {
        self.state = state
        recordingError = nil
        analysisError = nil
        switch state {
        case .idle, .requestingPermission:
            elapsedTime = 0
            livePitchSamples = []
        case .recording:
            elapsedTime = DebugPreviewData.liveSamples.last?.elapsedTime ?? 0
            livePitchSamples = DebugPreviewData.liveSamples
        case .awaitingFeedback, .analyzing, .completed:
            elapsedTime = DebugPreviewData.result.audio.inputSeconds
            livePitchSamples = DebugPreviewData.liveSamples
        }
        result = state == .completed ? DebugPreviewData.result : nil
        volumeStatistics = state == .completed ? DebugPreviewData.volumeStatistics : nil
        studyFeedbackDirection = state == .awaitingFeedback ? .feminine : nil
    }
}
#endif
