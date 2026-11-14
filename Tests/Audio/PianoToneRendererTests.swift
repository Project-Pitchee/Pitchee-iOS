import Foundation

@main
enum PianoToneRendererTests {
    static func main() {
        var checks = 0
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition {
                failures += 1
                print("FAIL: \(message)")
            }
        }
        func render(_ renderer: PianoToneRenderer, frames: Int = 48_000) -> [Float] {
            var samples = [Float](repeating: 0, count: frames)
            samples.withUnsafeMutableBufferPointer {
                _ = renderer.render(into: $0.baseAddress!, frameCount: $0.count)
            }
            return samples
        }

        var levels: [Double] = []
        for midi in 42...65 {
            let renderer = PianoToneRenderer(sampleRate: 48_000)
            renderer.noteOn(midi: midi)
            _ = render(renderer, frames: 4_800)
            let samples = render(renderer)
            let rms = sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
            levels.append(rms)
            check(rms >= 0.28 && rms <= 0.6, "MIDI \(midi) has a stronger, bounded steady level (\(rms))")
            check(samples.allSatisfy { $0.isFinite && abs(Double($0)) < 0.9 },
                  "MIDI \(midi) stays finite below the output ceiling")
            let crossings = zip(samples, samples.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
            let frequency = 440 * pow(2, Double(midi - 69) / 12)
            check(abs(Double(crossings) - frequency) <= 1.5,
                  "MIDI \(midi) retains its fundamental frequency")
            renderer.noteOff(midi: midi)
            _ = render(renderer, frames: 12_000)
            check(render(renderer, frames: 1_024).allSatisfy { $0 == 0 },
                  "MIDI \(midi) becomes silent after releasing sustain")
        }
        check(20 * log10(levels[0] / levels[23]) >= 4,
              "The lowest key receives at least 4 dB of compensation relative to the highest")
        for (lower, higher) in zip(levels, levels.dropFirst()) {
            let stepDB = 20 * log10(lower / higher)
            check(stepDB >= 0 && stepDB <= 0.5, "Adjacent keys have smooth low-register compensation")
        }

        let overlapping = PianoToneRenderer(sampleRate: 48_000)
        for midi in 42...65 { overlapping.noteOn(midi: midi) }
        check(render(overlapping).allSatisfy { $0.isFinite && abs(Double($0)) < 0.9 },
              "All 24 overlapping keys stay finite below the output ceiling")
        overlapping.releaseAll()
        _ = render(overlapping, frames: 12_000)
        check(render(overlapping, frames: 1_024).allSatisfy { $0 == 0 },
              "Releasing every key silences overlapping voices")

        let oneShot = PianoToneRenderer(sampleRate: 48_000)
        oneShot.noteOn(midi: 57, oneShot: true)
        check(render(oneShot, frames: 4_800).contains { $0 != 0 }, "One-shot playback emits audio")
        _ = render(oneShot)
        check(render(oneShot, frames: 1_024).allSatisfy { $0 == 0 },
              "One-shot playback becomes silent without a note-off command")

        print("Piano tone: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
