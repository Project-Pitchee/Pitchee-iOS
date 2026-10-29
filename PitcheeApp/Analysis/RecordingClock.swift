//
//  RecordingClock.swift
//  Pitchee
//

import Foundation

nonisolated enum RecordingClock {
    static let maximumSeconds: TimeInterval = 60

    /// Stopwatch format used by the recording readout and the tab accessory.
    static func string(_ seconds: TimeInterval) -> String {
        let clamped = min(maximumSeconds, max(0, seconds.isFinite ? seconds : 0))
        let tenths = Int((clamped * 10).rounded(.down))
        return String(format: "%02d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}
