import SwiftUI

/// A miniature app made from production presentation views and fixed values.
/// It never creates a recording model, persistence container, or article loader.
struct OnboardingAppPreview: View {
    enum Screen { case recording, result }

    static let canvasSize = CGSize(width: 402, height: 874)
    let screen: Screen

    var body: some View {
        TabView(selection: .constant(AppTab.practice)) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                NavigationStack {
                    if tab == .practice {
                        page
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {} label: {
                                        Image(systemName: "chevron.backward")
                                    }
                                }
                                if screen == .result {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        RecordingExportButton(
                                            result: OnboardingSampleData.result,
                                            volumeStatistics: nil,
                                            preference: .feminine
                                        )
                                        .labelStyle(.iconOnly)
                                    }
                                }
                            }
                    } else {
                        Color.clear
                    }
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }
        }
        .modifier(TabBarAccessory(isVisible: screen == .recording) {
            RecordingAccessoryControls(state: .recording, action: {})
        })
        .background(Color(uiColor: .systemBackground))
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.verticalSizeClass, .regular)
        .dynamicTypeSize(.large)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var page: some View {
        switch screen {
        case .recording:
            ScoringContent(
                snapshot: OnboardingSampleData.pitch,
                currentPitch: OnboardingSampleData.pitch.currentPitch,
                elapsedTime: OnboardingSampleData.duration
            )
        case .result:
            RecordingResultView(
                result: OnboardingSampleData.result,
                volumeStatistics: nil,
                saveError: nil,
                recordedPreference: .feminine,
                showsTrainingSuggestions: false
            )
            .navigationTitle("analysis.navigation.result")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

}

private enum OnboardingSampleData {
    static let duration = 12.0
    static let pitch = ScoringPitchSnapshot(samples: (0...120).map { index in
        let time = Double(index) / 10
        return LivePitchSample(elapsedTime: time, pitchHz: pitchHz(at: time))
    })

    private static func pitchHz(at time: Double) -> Double? {
        guard !(4.2...4.9).contains(time), !(8.4...9.0).contains(time) else { return nil }
        return 196 + sin(time * 1.6) * 14 + sin(time * 4.1) * 3
    }

    static let result: PitcheeAnalysisResult = {
        let windows: [PitcheeAnalysisResult.PitchWindow] = (0..<24).map { index in
            let start = Double(index) / 2
            return .init(startSeconds: start, endSeconds: start + 0.5, f0Hz: pitchHz(at: start + 0.25))
        }
        let segments: [PitcheeAnalysisResult.Segment] = [
            .init(startSeconds: 0, endSeconds: 4.2, speechStartSeconds: 0, speechEndSeconds: 4.2),
            .init(startSeconds: 4.9, endSeconds: 8.4, speechStartSeconds: 4.9, speechEndSeconds: 8.4),
            .init(startSeconds: 9, endSeconds: 12, speechStartSeconds: 9, speechEndSeconds: 12)
        ]
        return PitcheeAnalysisResult(
            schemaVersion: 2, modelVersion: "onboarding-sample", scoreProfile: nil,
            audio: .init(sourceSampleRate: 44_100, sourceChannels: 1,
                         inputSeconds: duration, analyzedSeconds: duration),
            vad: .init(segmentCount: segments.count, speechSeconds: 10.7,
                       sileroSegmentCount: segments.count, discardedBreathLikeCount: 0,
                       trimmedSegmentCount: 0, segments: segments),
            f0: .init(windowSeconds: 0.5, meanHz: 196, standardDeviationHz: 10,
                      voicedFrameCount: 1_070, voicedWindowCount: windows.compactMap(\.f0Hz).count,
                      windows: windows),
            vfp: .init(vfpStandardScore: 68, windowCount: 12, windowDurationSeconds: 1,
                       windows: (0..<12).map {
                           .init(startSeconds: Double($0), endSeconds: Double($0 + 1),
                                 vfpStandardScore: 68 + sin(Double($0) * 0.45) * 8)
                       }),
            naturalness: .init(score: 78, windowCount: 12, windowDurationSeconds: 1,
                               windows: (0..<12).map {
                                   .init(startSeconds: Double($0), endSeconds: Double($0 + 1),
                                         score: 78 + cos(Double($0) * 0.35) * 7)
                               }),
            composite: VoiceDirectionScore.feminineComposite(
                standardScore: 68, naturalness: 78, pitchHz: 196
            )
        )
    }()
}
