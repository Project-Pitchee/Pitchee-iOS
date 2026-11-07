//
//  LocalScoreStudyStore.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Combine
import Foundation

@MainActor
final class LocalScoreStudyStore: ObservableObject {
    struct Authorization: Equatable { fileprivate let id = UUID() }
    struct Attempt: Equatable {
        fileprivate let id = UUID()
        let direction: ScoreStudyDirection
    }
    private struct ActiveAttempt {
        let token: Attempt
        let deadline: TimeInterval
        var feedback: ScoreStudyFeedback?
    }

    static let shared: LocalScoreStudyStore = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalScoreStudyStore(
            fileURL: support.appendingPathComponent("LocalScoreStudy/state.json"),
            configuration: LocalDiagnosticsStore.bundledConfiguration
        )
    }()

    @Published private(set) var state: LocalScoreStudyState
    @Published private(set) var storageUnavailable = false
    private let fileURL: URL
    private let configuration: DiagnosticConfiguration
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let select: () -> Bool
    private var authorization = Authorization()
    private var active: ActiveAttempt?

    init(fileURL: URL, configuration: DiagnosticConfiguration, now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         select: @escaping () -> Bool = { Int.random(in: 0..<4) == 0 }) {
        self.fileURL = fileURL
        self.configuration = configuration
        self.now = now
        self.uptime = uptime
        self.select = select
        state = LocalScoreStudyState(now: now(), configuration: configuration)
        guard configuration.isValid else { storageUnavailable = true; return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 16_384 else { throw CocoaError(.fileReadCorruptFile) }
            let loaded = try JSONDecoder().decode(LocalScoreStudyState.self, from: Data(contentsOf: fileURL))
            guard loaded.isValid else { throw CocoaError(.fileReadCorruptFile) }
            state = loaded
            _ = state.refresh(now: now(), configuration: configuration)
            state.recover()
            persist()
        } catch { failClosed() }
    }

    func refresh() {
        if state.refresh(now: now(), configuration: configuration) {
            invalidate()
            persist()
        }
    }

    func setEnabled(_ value: Bool) {
        refresh()
        guard configuration.isValid else { storageUnavailable = true; return }
        invalidate()
        state.setEnabled(value)
        persist()
    }

    func clear() {
        invalidate()
        state.clear()
        persist()
    }

    /// Capture before recording starts. Enabling midway does not enroll old audio.
    func authorizeRecording() -> Authorization? {
        refresh()
        return state.enabled && !storageUnavailable ? authorization : nil
    }

    func invite(authorizedBy permit: Authorization?, direction: ScoreStudyDirection?) -> Attempt? {
        refresh()
        guard let permit, permit == authorization, let direction, active == nil,
              state.enabled, !storageUnavailable,
              state.usedInvitations < LocalScoreStudyState.invitationLimit,
              state.usedScreens < LocalScoreStudyState.screenLimit else { return nil }
        let selected = state.screen(direction: direction, selected: select())
        if selected {
            let token = Attempt(direction: direction)
            active = ActiveAttempt(token: token, deadline: uptime() + LocalScoreStudyState.feedbackSeconds)
        }
        persist()
        return storageUnavailable ? nil : active?.token
    }

    func isAwaitingFeedback(_ token: Attempt) -> Bool {
        refresh()
        return active?.token == token && active?.feedback == nil && !storageUnavailable
    }

    func respond(_ token: Attempt, feedback: ScoreStudyFeedback) {
        refresh()
        guard let attempt = active, attempt.token == token, attempt.feedback == nil,
              !storageUnavailable else { return }
        let accepted = uptime() >= attempt.deadline ? ScoreStudyFeedback.timedOut : feedback
        active?.feedback = accepted
        state.respond(direction: token.direction, response: accepted.response)
        persist()
    }

    /// Full model results, exact scores and voice preferences never enter here.
    func finish(_ token: Attempt?, pair: ScoreStudyPair?, failed: Bool) {
        refresh()
        guard let token, let active, active.token == token, !storageUnavailable else { return }
        if active.feedback == nil {
            state.respond(direction: token.direction, response: .interrupted)
        }
        let difference = failed ? nil : active.feedback?.rating.flatMap { pair?.lossDifference(from: $0) }
        let outcome: ScoreStudyAnalysis = failed ? .failed : (pair == nil ? .unavailable : .comparable)
        self.active = nil
        state.finish(direction: token.direction, outcome: outcome, lossDifference: difference)
        persist()
    }

    private func invalidate() {
        authorization = Authorization()
        active = nil
    }

    private func persist() {
        do {
            guard state.isValid else { throw CocoaError(.fileWriteUnknown) }
            try PrivateAppStorage.protectDirectory(fileURL.deletingLastPathComponent())
            let data = try JSONEncoder().encode(state)
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
            storageUnavailable = false
        } catch { failClosed() }
    }

    private func failClosed() {
        invalidate()
        state.setEnabled(false)
        storageUnavailable = true
        try? FileManager.default.removeItem(at: fileURL)
    }
}
