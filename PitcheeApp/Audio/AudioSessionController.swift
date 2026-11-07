//
//  AudioSessionController.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/27.
//

import AVFoundation
import Foundation
import OSLog

/// Owns the shared session and serializes hardware changes off the main actor.
@MainActor
enum AudioSessionController {
    private static let queue = DispatchQueue(
        label: "com.lvyzhan.Pitchee.audio-session",
        qos: .userInitiated
    )
    private static let logger = Logger(subsystem: "com.lvyzhan.Pitchee", category: "AudioSession")
    private static let coordinator = AudioSessionCoordinator(
        activate: configure,
        deactivate: enqueueDeactivation
    )

    static func activate(
        owner: UUID,
        use: AudioSessionCoordinator.Use,
        holder: AnyObject,
        stopPlayback: @escaping @MainActor () -> Void = {}
    ) async throws {
        try await coordinator.activate(owner: owner, use: use, holder: holder, stopPlayback: stopPlayback)
    }

    static func deactivate(owner: UUID) {
        coordinator.release(owner: owner)
    }

    static func retainUntilStopped(owner: UUID, holder: AnyObject) {
        coordinator.retainUntilStopped(owner: owner, holder: holder)
    }

    private static func configure(_ use: AudioSessionCoordinator.Use) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    switch use {
                    case .recording:
                        try session.setCategory(.record, mode: .measurement)
                        try session.setPreferredIOBufferDuration(0.02)
                    case .piano:
                        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                        try session.setPreferredIOBufferDuration(0.005)
                    case .playback:
                        try session.setCategory(.playback, mode: .spokenAudio)
                        try session.setPreferredIOBufferDuration(0.02)
                    }
                    // Keep configuration and activation together on this queue,
                    // including on OS versions without async activation APIs.
                    try session.setActive(true, options: [])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func enqueueDeactivation() {
        let logger = logger
        // Enqueue immediately so a subsequent activation cannot overtake cleanup.
        queue.async {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
            } catch {
                logger.error("Unable to deactivate audio session: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
