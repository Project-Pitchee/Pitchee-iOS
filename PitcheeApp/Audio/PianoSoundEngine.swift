//
//  PianoSoundEngine.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/18.
//

import AVFoundation
import Combine
import Foundation
import OSLog

struct PianoNote: Identifiable, Hashable {
    let midi: Int
    let displayName: String

    var id: Int { midi }
    var frequency: Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    static let allNotes: [PianoNote] = [
        ("F#2", 42), ("G2", 43), ("G#2", 44), ("A2", 45), ("A#2", 46), ("B2", 47),
        ("C3", 48), ("C#3", 49), ("D3", 50), ("D#3", 51), ("E3", 52), ("F3", 53),
        ("F#3", 54), ("G3", 55), ("G#3", 56), ("A3", 57), ("A#3", 58), ("B3", 59),
        ("C4", 60), ("C#4", 61), ("D4", 62), ("D#4", 63), ("E4", 64), ("F4", 65)
    ].map { PianoNote(midi: $0.1, displayName: $0.0) }
}

@MainActor
final class PianoSoundEngine: ObservableObject {
    private let logger = Logger(subsystem: "com.lvyzhan.Pitchee", category: "Piano")
    private let engine = AVAudioEngine()
    private let renderer = PianoToneRenderer(sampleRate: 48_000)
    private var sourceNode: AVAudioSourceNode?
    private var sessionOwner: UUID?
    private var preparation: Task<Bool, Never>?
    private var pendingNote: Task<Void, Never>?
    private var pendingMIDI: Int?

    @discardableResult
    func prepare() async -> Bool {
        if let preparation { return await preparation.value }
        if engine.isRunning { return true }
        let owner = UUID()
        sessionOwner = owner
        let task = Task { [weak self] in
            guard let self else { return false }
            do {
                try await AudioSessionController.activate(owner: owner, use: .piano, holder: self) { [weak self] in
                    self?.stopAll()
                }
                guard !Task.isCancelled, sessionOwner == owner else {
                    AudioSessionController.deactivate(owner: owner)
                    return false
                }
                guard startEngine() else {
                    AudioSessionController.deactivate(owner: owner)
                    sessionOwner = nil
                    return false
                }
                return true
            } catch {
                AudioSessionController.deactivate(owner: owner)
                if sessionOwner == owner { sessionOwner = nil }
                if !(error is CancellationError) {
                    logger.error("Unable to prepare piano: \(String(describing: error), privacy: .private)")
                }
                return false
            }
        }
        preparation = task
        let ready = await task.value
        if sessionOwner == owner || sessionOwner == nil { preparation = nil }
        return ready
    }

    private func startEngine() -> Bool {
        if sourceNode == nil {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) else {
                logger.error("Unable to create piano audio format")
                return false
            }
            let renderer = renderer
            let source = AVAudioSourceNode(format: format) { isSilent, _, frameCount, output in
                let buffers = UnsafeMutableAudioBufferListPointer(output)
                guard let samples = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
                    return noErr
                }
                isSilent.pointee = ObjCBool(
                    renderer.render(into: samples, frameCount: Int(frameCount))
                )
                return noErr
            }
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: format)
            sourceNode = source
        }

        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                logger.error("Unable to start piano audio engine: \(String(describing: error), privacy: .public)")
                return false
            }
        }
        return engine.isRunning
    }

    func play(note: PianoNote) {
        schedule(note: note, oneShot: true)
    }

    func start(note: PianoNote) {
        schedule(note: note, oneShot: false)
    }

    private func schedule(note: PianoNote, oneShot: Bool) {
        pendingNote?.cancel()
        pendingMIDI = note.midi
        pendingNote = Task { [weak self] in
            guard let self, await prepare(), !Task.isCancelled else { return }
            renderer.noteOn(midi: note.midi, oneShot: oneShot)
        }
    }

    func stop(note: PianoNote) {
        if pendingMIDI == note.midi {
            pendingNote?.cancel()
            pendingNote = nil
            pendingMIDI = nil
        }
        renderer.noteOff(midi: note.midi)
    }

    func stopAll() {
        pendingNote?.cancel()
        pendingNote = nil
        pendingMIDI = nil
        preparation?.cancel()
        preparation = nil
        renderer.releaseAll()
        engine.pause()
        if let sessionOwner { AudioSessionController.deactivate(owner: sessionOwner) }
        sessionOwner = nil
    }

    isolated deinit {
        pendingNote?.cancel()
        preparation?.cancel()
        engine.stop()
        if let sessionOwner { AudioSessionController.deactivate(owner: sessionOwner) }
    }
}
