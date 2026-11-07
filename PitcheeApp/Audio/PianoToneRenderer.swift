//
//  PianoToneRenderer.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/18.
//

import Foundation

/// Commands are shared; oscillator and envelope state belong exclusively to the audio thread.
nonisolated final class PianoToneRenderer: @unchecked Sendable {
    private struct Command {
        var generation: UInt64 = 0
        var held = false
        var oneShot = false
    }

    private struct Voice {
        var generation: UInt64 = 0
        var phase = 0.0
        var gain = 0.0
        var rampStart = 0.0
        var target = 0.0
        var rampPosition = 0
        var rampLength = 1
        var age = 0
        var held = false
        var oneShot = false
        let increment: Double

        mutating func ramp(to value: Double, frames: Int) {
            rampStart = gain
            target = value
            rampPosition = 0
            rampLength = frames
        }
    }

    private let lock = NSLock()
    private var commands = Array(repeating: Command(), count: 24)
    private var voices: [Voice]
    private let attackFrames: Int
    private let releaseFrames: Int
    private let minimumFrames: Int
    private let oneShotFrames: Int

    init(sampleRate: Double) {
        attackFrames = max(1, Int(sampleRate * 0.008))
        releaseFrames = max(1, Int(sampleRate * 0.18))
        minimumFrames = max(1, Int(sampleRate * 0.025))
        oneShotFrames = max(1, Int(sampleRate * 0.6))
        voices = (42...65).map { midi in
            Voice(increment: 2 * .pi * 440 * pow(2, Double(midi - 69) / 12) / sampleRate)
        }
    }

    func noteOn(midi: Int, oneShot: Bool = false) {
        guard (42...65).contains(midi) else { return }
        lock.lock()
        commands[midi - 42].generation &+= 1
        commands[midi - 42].held = true
        commands[midi - 42].oneShot = oneShot
        lock.unlock()
    }

    func noteOff(midi: Int) {
        guard (42...65).contains(midi) else { return }
        lock.lock()
        commands[midi - 42].held = false
        lock.unlock()
    }

    func releaseAll() {
        lock.lock()
        for index in commands.indices { commands[index].held = false }
        lock.unlock()
    }

    /// Never wait on the UI thread in the render callback. A busy mailbox is read next buffer.
    func render(into samples: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        if lock.try() {
            for index in voices.indices {
                if voices[index].generation != commands[index].generation {
                    voices[index].generation = commands[index].generation
                    voices[index].age = 0
                    voices[index].oneShot = commands[index].oneShot
                    // Preserve phase AND current gain when retriggering a release tail.
                    voices[index].ramp(to: 1, frames: attackFrames)
                }
                voices[index].held = commands[index].held
            }
            lock.unlock()
        }

        var silent = true
        for frame in 0..<frameCount {
            var mixed = 0.0
            for index in voices.indices {
                guard voices[index].gain > 0 || voices[index].target > 0 else { continue }
                if voices[index].target > 0,
                   (!voices[index].held && voices[index].age >= minimumFrames
                    || voices[index].oneShot && voices[index].age >= oneShotFrames) {
                    voices[index].ramp(to: 0, frames: releaseFrames)
                }
                let phase = voices[index].phase
                mixed += (sin(phase) + 0.22 * sin(2 * phase) + 0.08 * sin(3 * phase))
                    * voices[index].gain * 0.32
                voices[index].phase += voices[index].increment
                if voices[index].phase >= 2 * .pi { voices[index].phase -= 2 * .pi }
                voices[index].age += 1
                if voices[index].rampPosition < voices[index].rampLength {
                    voices[index].rampPosition += 1
                    let t = Double(voices[index].rampPosition) / Double(voices[index].rampLength)
                    let eased = t * t * (3 - 2 * t)
                    voices[index].gain = voices[index].rampStart
                        + (voices[index].target - voices[index].rampStart) * eased
                }
            }
            // Smooth saturation leaves headroom even when release tails overlap.
            samples[frame] = Float(0.9 * tanh(mixed / 0.9))
            if samples[frame] != 0 { silent = false }
        }
        return silent
    }
}
