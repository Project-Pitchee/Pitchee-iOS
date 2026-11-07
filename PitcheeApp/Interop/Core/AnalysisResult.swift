//
//  AnalysisResult.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/13.
//

import Foundation

nonisolated public struct PitcheeAnalysisResult: Codable, Sendable {
    public let schemaVersion: Int
    public let modelVersion: String
    public let scoreProfile: String?
    public let audio: Audio
    public let vad: VoiceActivity
    public let f0: Pitch
    public let vfp: VFP
    public let naturalness: Naturalness
    public let composite: CompositeScore
    public internal(set) var voiceQuality: VoiceQuality?

    init(
        schemaVersion: Int,
        modelVersion: String,
        scoreProfile: String?,
        audio: Audio,
        vad: VoiceActivity,
        f0: Pitch,
        vfp: VFP,
        naturalness: Naturalness,
        composite: CompositeScore,
        voiceQuality: VoiceQuality? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.modelVersion = modelVersion
        self.scoreProfile = scoreProfile
        self.audio = audio
        self.vad = vad
        self.f0 = f0
        self.vfp = vfp
        self.naturalness = naturalness
        self.composite = composite
        self.voiceQuality = voiceQuality
    }

    public struct Audio: Codable, Sendable {
        public let sourceSampleRate: Int
        public let sourceChannels: Int
        public let inputSeconds: Double
        public let analyzedSeconds: Double
    }

    public struct VoiceActivity: Codable, Sendable {
        public let segmentCount: Int
        public let speechSeconds: Double
        public let sileroSegmentCount: Int
        public let discardedBreathLikeCount: Int
        public let trimmedSegmentCount: Int
        public let segments: [Segment]
    }

    public struct Segment: Codable, Sendable {
        public let startSeconds: Double
        public let endSeconds: Double
        public let speechStartSeconds: Double
        public let speechEndSeconds: Double
    }

    public struct Pitch: Codable, Sendable {
        public let windowSeconds: Double
        public let meanHz: Double?
        public let standardDeviationHz: Double?
        public let voicedFrameCount: Int
        public let voicedWindowCount: Int
        public let windows: [PitchWindow]
    }

    public struct PitchWindow: Codable, Sendable {
        public let startSeconds: Double
        public let endSeconds: Double
        public let f0Hz: Double?
    }

    nonisolated public struct VoiceQuality: Codable, Sendable {
        public let algorithm: String
        public let hnrDb: Double?
        public let hnrWindowCount: Int
        public let hnrStdDb: Double?
        /// HNR's own window duration; its overlapping timeline is independent of F0.
        public let windowSeconds: Double
        public let windows: [HNRWindow]
    }

    nonisolated public struct HNRWindow: Codable, Sendable {
        public let startSeconds: Double
        public let endSeconds: Double
        /// Available when the clipped window midpoint passes VAD and correlation is reliable.
        public let hnrDb: Double?
    }

    public struct VFP: Codable, Sendable {
        public let vfpStandardScore: Double
        public let windowCount: Int
        public let windowDurationSeconds: Double
        public let windows: [VFPWindow]
    }

    public struct VFPWindow: Codable, Sendable {
        public let startSeconds: Double
        public let endSeconds: Double
        public let vfpStandardScore: Double
    }

    public struct Naturalness: Codable, Sendable {
        public let score: Double
        public let windowCount: Int
        public let windowDurationSeconds: Double
        public let windows: [NaturalnessWindow]
    }

    public struct NaturalnessWindow: Codable, Sendable {
        public let startSeconds: Double
        public let endSeconds: Double
        public let score: Double
    }

    public struct CompositeScore: Codable, Sendable {
        public let baseScore: Double
        public let finalScore: Double
        public let cap: Double?
        public let rule: String
        public let limited: Bool
        public let boosted: Bool
    }
}
