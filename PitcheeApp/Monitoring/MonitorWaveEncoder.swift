//
//  MonitorWaveEncoder.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import Foundation

/// Canonical mono PCM16 WAV held in memory for AVAudioPlayer. Keeping playback
/// in memory avoids creating an additional persistent microphone recording.
nonisolated enum MonitorWaveEncoder {
    static func encode(_ samples: [Float]) -> Data {
        let byteCount = UInt32(samples.count * 2)
        var data = Data(capacity: 44 + Int(byteCount))
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(byteCount + 36)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(MonitorTimeline.sampleRate))
        append(UInt32(MonitorTimeline.sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(byteCount)
        for sample in samples {
            let finite = sample.isFinite ? sample : 0
            append(Int16((min(1, max(-1, finite)) * 32_767).rounded()))
        }
        return data
    }
}
