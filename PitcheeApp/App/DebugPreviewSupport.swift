//
//  DebugPreviewSupport.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/26.
//

#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Deterministic data used only by SwiftUI previews.
/// Keeping it here makes result, export, and chart previews show the same
/// realistic recording without touching the app's persistence layer.
enum DebugPreviewData {
    static let result = makeResult()
    static let previousFinalScore = 74.0
    static let previousMetrics = PreviousScoreMetrics(
        finalScore: previousFinalScore,
        standardScore: 62,
        naturalnessScore: 72,
        meanPitchHz: 165
    )
    static func makePlaybackAudioURL() -> URL? {
        let sampleRate = 16_000
        let duration = 12
        let samples = (0..<(sampleRate * duration)).map { index in
            let time = Double(index) / Double(sampleRate)
            let envelope = 0.22 + 0.16 * sin(time * 3.2).magnitude
            let voice = sin(2 * .pi * 174 * time) + 0.28 * sin(2 * .pi * 348 * time)
            return Float(voice * envelope)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pitchee-playback-preview-\(UUID().uuidString).wav")
        do {
            try MonitorWaveEncoder.encode(samples).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
    static let bottleneckResult = makeResult(
        meanPitchHz: 150,
        standardScore: 42,
        naturalnessScore: 72,
        finalScore: 42,
        rule: "low_f0_natural_cap",
        cap: 59,
        limited: true
    )
    static let recordedAt = Date(timeIntervalSince1970: 1_790_395_200)
    static let history = [
        makeResult(meanPitchHz: 156, standardScore: 55, naturalnessScore: 66, finalScore: 64),
        makeResult(meanPitchHz: 165, standardScore: 62, naturalnessScore: 72, finalScore: 74),
        result
    ]

    private static func makeResult(
        meanPitchHz: Double = 174,
        standardScore: Double = 68,
        naturalnessScore: Double = 78,
        finalScore: Double = 82,
        rule: String = "continuous",
        cap: Double? = nil,
        limited: Bool = false,
        boosted: Bool = false
    ) -> PitcheeAnalysisResult {
        let pitchWindows: [PitcheeAnalysisResult.PitchWindow] = (0..<240).map { index in
            let start = Double(index) * 0.05
            let pitch: Double? = index.isMultiple(of: 57)
                ? nil
                : meanPitchHz + sin(Double(index) * 0.065) * 18
            return .init(
                startSeconds: start,
                endSeconds: start + 0.05,
                f0Hz: pitch
            )
        }
        let segments = [
            PitcheeAnalysisResult.Segment(
                startSeconds: 0.5,
                endSeconds: 5.5,
                speechStartSeconds: 0.6,
                speechEndSeconds: 5.4
            ),
            PitcheeAnalysisResult.Segment(
                startSeconds: 6.5,
                endSeconds: 11.5,
                speechStartSeconds: 6.6,
                speechEndSeconds: 11.4
            )
        ]
        let vfpWindows = (0..<12).map { index in
            PitcheeAnalysisResult.VFPWindow(
                startSeconds: Double(index),
                endSeconds: Double(index + 1),
                vfpStandardScore: standardScore + sin(Double(index) * 0.45) * 8
            )
        }
        let naturalnessWindows = (0..<12).map { index in
            PitcheeAnalysisResult.NaturalnessWindow(
                startSeconds: Double(index),
                endSeconds: Double(index + 1),
                score: naturalnessScore + cos(Double(index) * 0.35) * 7
            )
        }

        return PitcheeAnalysisResult(
            schemaVersion: 2,
            modelVersion: "debug-preview",
            scoreProfile: nil,
            audio: .init(sourceSampleRate: 44_100, sourceChannels: 1, inputSeconds: 12, analyzedSeconds: 12),
            vad: .init(
                segmentCount: segments.count,
                speechSeconds: 10,
                sileroSegmentCount: segments.count,
                discardedBreathLikeCount: 0,
                trimmedSegmentCount: 0,
                segments: segments
            ),
            f0: .init(
                windowSeconds: 0.05,
                meanHz: meanPitchHz,
                standardDeviationHz: 14,
                voicedFrameCount: 1_920,
                voicedWindowCount: pitchWindows.compactMap(\.f0Hz).count,
                windows: pitchWindows
            ),
            vfp: .init(
                vfpStandardScore: standardScore,
                windowCount: vfpWindows.count,
                windowDurationSeconds: 1,
                windows: vfpWindows
            ),
            naturalness: .init(
                score: naturalnessScore,
                windowCount: naturalnessWindows.count,
                windowDurationSeconds: 1,
                windows: naturalnessWindows
            ),
            composite: .init(
                baseScore: finalScore,
                finalScore: finalScore,
                cap: cap,
                rule: rule,
                limited: limited,
                boosted: boosted
            )
        )
    }

    static let volumeStatistics: RecordingVolumeStatistics = {
        let windows = (0..<48).map { index in
            let isSpeech = index % 6 != 0
            let level = -28 + sin(Double(index) * 0.4) * 4
            return RecordingVolumeWindow(
                centerSeconds: Double(index) * 0.25 + 0.125,
                voiceDBFS: isSpeech ? level : nil,
                backgroundDBFS: isSpeech ? nil : level - 12
            )
        }
        return RecordingVolumeStatistics(
            environmentDBFS: -40,
            averageDBFS: -27,
            medianDBFS: -27,
            high95DBFS: -23,
            low5DBFS: -32,
            windows: windows
        )
    }()

    static let liveSamples: [LivePitchSample] = (0..<36).map { index in
        LivePitchSample(
            elapsedTime: Double(index) * 0.1,
            pitchHz: index % 9 == 0 ? nil : 175 + sin(Double(index) * 0.4) * 22
        )
    }
}

/// Creates isolated preview defaults without putting state in the app's suite.
enum DebugPreviewDefaults {
    static let store: UserDefaults = {
        let store = UserDefaults(suiteName: "com.lvyzhan.Pitchee.preview")!
        store.register(defaults: [
            AppStorageKey.onboardingCompletedVersion: 0,
            AppStorageKey.voicePreference: VoicePreference.feminine.rawValue,
            AppStorageKey.customThemeColor: "",
            AppStorageKey.themeSelection: AppThemeOption.twilt.rawValue,
            AppStorageKey.openedDateKeys: ""
        ])
        return store
    }()
}

/// Creates a fresh in-memory SwiftData store for previews that need it.
enum DebugPreviewStore {
    static func makeContainer(withHistory: Bool = false) -> ModelContainer? {
        do {
            let container = try ModelContainer(
                for: RecordingAssessment.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            if withHistory {
                for (index, result) in DebugPreviewData.history.enumerated() {
                    let daysAgo = DebugPreviewData.history.count - index - 1
                    let assessment = try RecordingAssessment(
                        recordedAt: DebugPreviewData.recordedAt.addingTimeInterval(-Double(daysAgo) * 86_400),
                        result: result
                    )
                    container.mainContext.insert(assessment)
                }
                try container.mainContext.save()
            }
            return container
        } catch {
            return nil
        }
    }
}
#endif
