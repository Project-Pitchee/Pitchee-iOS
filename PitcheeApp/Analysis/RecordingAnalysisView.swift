//
//  RecordingAnalysisView.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/18.
//

import AVFoundation
import SwiftUI
import LaTeXSwiftUI

extension Color {
    static let pitcheeTendencyPink = Color(
        red: 1,
        green: 182 / 255,
        blue: 193 / 255
    )
    static let pitcheeTendencySky = Color(
        red: 100 / 255,
        green: 149 / 255,
        blue: 237 / 255
    )
}

struct RecordingAnalysisView: View {
    @ObservedObject var viewModel: AnalysisViewModel
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""

    private var voicePreference: VoicePreference {
        viewModel.assessment?.recordedTarget
            ?? VoicePreference(legacyStoredValue: savedVoicePreference)
            ?? .undecided
    }

    var body: some View {
        Group {
            if viewModel.isAwaitingFeedback, let direction = viewModel.studyFeedbackDirection {
                ScoreStudyFeedbackView(direction: direction) { feedback in
                    viewModel.submitStudyFeedback(feedback)
                }
            } else if viewModel.isAnalyzing {
                stateScroll { analyzingState }
            } else if let result = viewModel.result {
                RecordingResultView(
                    result: result,
                    volumeStatistics: viewModel.volumeStatistics,
                    saveError: viewModel.analysisError,
                    recordingNotice: viewModel.captureNotice,
                    quality: viewModel.assessment?.quality,
                    recordedPreference: viewModel.assessment?.recordedTarget,
                    playbackAudioURL: viewModel.playbackAudioURL,
                    previousScore: viewModel.previousFinalScore,
                    previousMetrics: viewModel.previousMetrics,
                    hasPlayedScoreAnimation: viewModel.hasPlayedScoreAnimation,
                    onScoreAnimationPlayed: viewModel.markScoreAnimationPlayed
                )
            } else {
                stateScroll {
                    ContentUnavailableView {
                        Label("analysis.emptyState.noResult.title", systemImage: "waveform.badge.exclamationmark")
                    } description: {
                        Text(viewModel.analysisError ?? String(localized: "analysis.emptyState.noResult.description"))
                    }
                    .padding(.top, 60)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(viewModel.isAnalyzing || viewModel.isAwaitingFeedback
            ? String(localized: "analysis.navigation.analyzing")
            : String(localized: "analysis.navigation.result"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isAnalyzing || viewModel.isAwaitingFeedback)
        .toolbar {
            if let result = viewModel.result, !viewModel.isAnalyzing {
                ToolbarItem(placement: .topBarTrailing) {
                    RecordingExportButton(
                        result: result,
                        volumeStatistics: viewModel.volumeStatistics,
                        preference: self.voicePreference
                    )
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    private func stateScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(24)
        }
    }

    private var analyzingState: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.path")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.pitcheeAccent)
                .frame(width: 112, height: 112)
                .background(Color.pitcheeAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 32))
            VStack(spacing: 10) {
                Text("analysis.progress.title")
                    .font(.title2.weight(.bold))
                Text("analysis.progress.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let notice = viewModel.captureNotice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView().controlSize(.large)
            Label("analysis.progress.privacyNote", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }
}

struct RecordingResultView: View {
    let result: PitcheeAnalysisResult
    let volumeStatistics: RecordingVolumeStatistics?
    let saveError: String?
    let recordingNotice: String?
    let quality: RecordingQuality?
    let recordedPreference: VoicePreference?
    let playbackAudioURL: URL?
    let previousScore: Double?
    let previousMetrics: PreviousScoreMetrics?
    let animatesScore: Bool
    let hasPlayedScoreAnimation: Bool
    let onScoreAnimationPlayed: () -> Void
    private let showsBackground: Bool
    private let pitchStatistics: RecordingPitchStatistics

    @ObservedObject private var library = VoiceTrainingLibraryLoader.shared
    @State private var selectedVoiceArticle: VoiceArticle?
    @State private var showsAllTrainingArticles = false
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""

    private enum InsightMetric {
        case naturalness
        case timbre
        case pitch
    }

    private enum ScoreOutcome {
        case bottleneck(title: String, description: String, metric: InsightMetric)
        case pass
        case none
    }

    private var voicePreference: VoicePreference {
        recordedPreference ?? VoicePreference(legacyStoredValue: savedVoicePreference) ?? .undecided
    }

    private var directionScore: VoiceDirectionScore {
        voicePreference.score(for: result)
    }

    private var usesMasculineScoringProfile: Bool {
        voicePreference == .masculine
            || (voicePreference == .undecided && result.scoreProfile == "masculinization")
    }

    private var trainingRecommendation: VoiceTrainingRecommendation {
        VoiceLibraryMatcher.recommend(
            for: result,
            preference: voicePreference,
            quality: quality,
            volumeStatistics: volumeStatistics,
            store: library.store
        )
    }

    init(
        result: PitcheeAnalysisResult,
        volumeStatistics: RecordingVolumeStatistics?,
        saveError: String?,
        recordingNotice: String? = nil,
        quality: RecordingQuality? = nil,
        recordedPreference: VoicePreference? = nil,
        playbackAudioURL: URL? = nil,
        previousScore: Double? = nil,
        previousMetrics: PreviousScoreMetrics? = nil,
        animatesScore: Bool = true,
        hasPlayedScoreAnimation: Bool = false,
        onScoreAnimationPlayed: @escaping () -> Void = {},
        showsBackground: Bool = true
    ) {
        self.result = result
        self.volumeStatistics = volumeStatistics
        self.saveError = saveError
        self.recordingNotice = recordingNotice
        self.quality = quality
        self.recordedPreference = recordedPreference
        self.playbackAudioURL = playbackAudioURL
        self.previousScore = previousScore
        self.previousMetrics = previousMetrics
        self.animatesScore = animatesScore
        self.hasPlayedScoreAnimation = hasPlayedScoreAnimation
        self.onScoreAnimationPlayed = onScoreAnimationPlayed
        self.showsBackground = showsBackground
        self.pitchStatistics = RecordingPitchStatistics(pitch: result.f0)
    }

    var body: some View {
        FoldAwareArrangementView(
            primary: { resultPane(resultOverview) },
            secondary: { resultPane(resultSecondary) },
            regular: { resultScroll(allContent) }
        )
        .background {
            if showsBackground {
                Color(uiColor: .systemGroupedBackground)
            }
        }
        .task { await library.load() }
        .sheet(item: $selectedVoiceArticle) { article in
            VoiceArticleDetailView(article: article)
        }
        .sheet(isPresented: $showsAllTrainingArticles) {
            VoiceTrainingLibraryBrowserView()
        }
    }

    private var resultOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScoreCircleSummary(
                targetScore: directionScore.finalScore,
                previousScore: previousScore,
                previousMetrics: previousMetrics,
                masculine: usesMasculineScoringProfile,
                animates: animatesScore,
                hasPlayed: hasPlayedScoreAnimation,
                onAnimationPlayed: onScoreAnimationPlayed,
                result: result,
                preference: voicePreference
            )

            RecordedAudioPlayerView(
                audioURL: playbackAudioURL,
                f0Windows: result.f0.windows,
                vfpWindows: result.vfp.windows,
                naturalnessWindows: result.naturalness.windows
            )
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                scoreInsightSection

                VoiceProfileMetricBars(
                    naturalnessScore: directionScore.naturalnessScore,
                    timbreScore: directionScore.standardScore,
                    meanPitchHz: result.f0.meanHz,
                    masculine: usesMasculineScoringProfile
                )
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }

            if let recordingNotice {
                Label(recordingNotice, systemImage: "pause.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var scoreInsightSection: some View {
        switch scoreOutcome {
        case .bottleneck(let title, let description, _):
            scoreInsightCard(
                title: title,
                description: description,
                accent: Color(uiColor: .systemRed),
                symbol: "exclamationmark.triangle.fill"
            )
        case .pass:
            scoreInsightCard(
                title: SettingsCopy.text("你的声音很pass", "Your voice passes"),
                description: SettingsCopy.text(
                    "本次没有触发主要短板规则。",
                    "No main bottleneck rule was triggered."
                ),
                accent: Color(uiColor: .systemGreen),
                symbol: "checkmark"
            )
        case .none:
            EmptyView()
        }
    }

    private func scoreInsightCard(
        title: String,
        description: String,
        accent: Color,
        symbol: String
    ) -> some View {
        NavigationLink {
            ScoreExplanationView(
                result: result,
                preference: voicePreference,
                previousMetrics: previousMetrics
            )
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 25, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(verbatim: description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            SettingsCopy.text("打开评分规则详情", "Opens scoring rule details")
        )
        .accessibilityElement(children: .combine)
    }

    private var scoreOutcome: ScoreOutcome {
        let score = directionScore
        let guidance = scoreGuidance(for: score.rule)

        if usesMasculineScoringProfile {
            return score.finalScore > 60 ? .pass : .none
        }

        switch score.rule {
        case "f0_unavailable":
            return .bottleneck(
                title: SettingsCopy.text("音高不可用", "Pitch unavailable"),
                description: guidance,
                metric: .pitch
            )
        case "high_f0_stylized_cap":
            return .bottleneck(
                title: SettingsCopy.text("自然度过低", "Naturalness below threshold"),
                description: guidance,
                metric: .naturalness
            )
        case "low_f0_natural_cap":
            return .bottleneck(
                title: SettingsCopy.text("音高过低", "Pitch below threshold"),
                description: guidance,
                metric: .pitch
            )
        case "low_f0_stylized_cap":
            return .bottleneck(
                title: SettingsCopy.text("音高和自然度过低", "Pitch and naturalness below thresholds"),
                description: guidance,
                metric: .naturalness
            )
        case "high_f0_male_cap":
            return .bottleneck(
                title: SettingsCopy.text("音色分过低", "Timbre below threshold"),
                description: guidance,
                metric: .timbre
            )
        case "pass_boost":
            return score.finalScore > 60 ? .pass : .none
        default:
            return continuousScoreOutcome(score, guidance: guidance)
        }
    }

    private func scoreGuidance(for rule: String) -> String {
        switch rule {
        case "f0_unavailable":
            return SettingsCopy.text(
                "没有识别到稳定音高，下次可以离麦克风近一点。",
                "No stable pitch was detected. Try moving closer to the microphone."
            )
        case "high_f0_stylized_cap":
            return SettingsCopy.text(
                "刻意抬升音高而导致发声不健康的结果。请量力而行。",
                "This result comes from forcing pitch higher in a way that makes phonation less healthy. Stay within your comfortable limits."
            )
        case "low_f0_natural_cap":
            return SettingsCopy.text(
                "自然度已经不错，接下来把注意力放在音高上。",
                "Naturalness is already good. Focus on pitch next."
            )
        case "low_f0_stylized_cap":
            return SettingsCopy.text(
                "音高和自然度都需要照顾。请先完整自然地读完整段语料。",
                "Both pitch and naturalness need attention. Read the full passage naturally from beginning to end."
            )
        case "high_f0_male_cap":
            return SettingsCopy.text(
                "你的声音在高音调下仍保持自然，说明你的问题不在音高上。接下来请尝试缩短声道，将共鸣焦点前移，方法包括但不限于：舌位前移、唇部展开。",
                "Your voice stays natural at a higher pitch, so pitch is not the issue here. Next, try shortening the vocal tract and moving the resonance focus forward. This may include moving the tongue forward and spreading the lips, among other approaches."
            )
        case "pass_boost":
            return SettingsCopy.text(
                "完全“Pass”。恭喜！请继续加油。",
                "A clear “Pass.” Congratulations—keep it up."
            )
        default:
            return SettingsCopy.text(
                "基本“Pass”，达到及格线。请保持现在的状态。",
                "A basic “Pass”—at or above the passing line. Keep things as they are."
            )
        }
    }

    private func continuousScoreOutcome(
        _ score: VoiceDirectionScore,
        guidance: String
    ) -> ScoreOutcome {
        var issues: [(value: Double, outcome: ScoreOutcome)] = []

        if let pitch = result.f0.meanHz, pitch.isFinite {
            let pitchScore = min(max((pitch - 100) / 150 * 100, 0), 100)
            if pitch <= 165 {
                issues.append((
                    pitchScore,
                    .bottleneck(
                        title: SettingsCopy.text("音高过低", "Pitch below threshold"),
                        description: guidance,
                        metric: .pitch
                    )
                ))
            }
        } else {
            issues.append((
                0,
                .bottleneck(
                    title: SettingsCopy.text("音高不可用", "Pitch unavailable"),
                    description: guidance,
                    metric: .pitch
                )
            ))
        }

        if score.standardScore < 50 {
            issues.append((
                score.standardScore,
                .bottleneck(
                    title: SettingsCopy.text("音色分过低", "Timbre below threshold"),
                    description: guidance,
                    metric: .timbre
                )
            ))
        }

        if score.naturalnessScore < 50 {
            issues.append((
                score.naturalnessScore,
                .bottleneck(
                    title: SettingsCopy.text("自然度过低", "Naturalness below threshold"),
                    description: guidance,
                    metric: .naturalness
                )
            ))
        }

        if let lowest = issues.min(by: { $0.value < $1.value }) {
            return lowest.outcome
        }
        return score.finalScore > 60 ? .pass : .none
    }

    private var resultSecondary: some View {
        VStack(alignment: .leading, spacing: 28) {
            suggestionsSection
        }
    }

    private var allContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            resultOverview
            Divider()
            resultSecondary
        }
    }

    private func resultScroll<Content: View>(_ content: Content) -> some View {
        ScrollView {
            content
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
        }
    }

    private func resultPane<Content: View>(_ content: Content) -> some View {
        resultScroll(content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            PracticeSuggestionsSection(suggestions: trainingRecommendation.prioritySuggestions) { article in
                selectedVoiceArticle = article
            }

            Button {
                showsAllTrainingArticles = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label("practice.suggestions.browseLibrary", systemImage: "books.vertical")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pitcheeAccent)
        }
    }

    private var scoreSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(voicePreference.scoreTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink {
                    ScoreExplanationView(
                        result: result,
                        preference: voicePreference,
                        previousMetrics: previousMetrics
                    )
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("analysis.score.explanation.a11y")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scoreText(directionScore.finalScore))
                    .font(.system(size: 78, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.pitcheeAccent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("common.unit.pointsOutOf100")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("analysis.score.summary.a11y \(scoreText(directionScore.finalScore))")
    }

    private var recordingStatistics: some View {
        VStack(alignment: .leading, spacing: 24) {
            compactStatisticsSection(title: "analysis.statistics.pitch.title", metrics: pitchMetrics)

            compactStatisticsSection(title: "analysis.statistics.volume.title", metrics: volumeMetrics)

            Text("analysis.statistics.volume.note")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pitchRangeHz: ClosedRange<Double>? {
        guard let low = pitchStatistics.low5Hz,
              let high = pitchStatistics.high95Hz else { return nil }
        return low...high
    }

    private var pitchMetrics: [CompactMetric] {
        let dominantBand = dominantPitchBand(pitchStatistics)
        return [
            CompactMetric(title: "common.metric.meanPitch.title", value: metricNumber(pitchStatistics.averageHz), unit: String(localized: "common.unit.hertz"), symbol: "waveform.path"),
            CompactMetric(title: "common.metric.medianPitch.title", value: metricNumber(pitchStatistics.medianHz), unit: String(localized: "common.unit.hertz"), symbol: "equal"),
            CompactMetric(title: "common.metric.corePitchRange.title", value: pitchRangeText(pitchStatistics), unit: String(localized: "common.unit.hertzPercentileRange"), symbol: "arrow.left.and.right"),
            CompactMetric(title: "analysis.statistics.dominantPitchBand.label", value: dominantBand.name, unit: dominantBand.percentage, symbol: "scope")
        ]
    }

    private var volumeMetrics: [CompactMetric] {
        [
            CompactMetric(title: "common.metric.environmentNoiseFloor.title", value: metricNumber(volumeStatistics?.environmentDBFS), unit: String(localized: "common.unit.dbfs"), symbol: "wind"),
            CompactMetric(title: "analysis.statistics.averageVolume.label", value: metricNumber(volumeStatistics?.averageDBFS), unit: volumeUnit(volumeStatistics?.averageDBFS), symbol: "speaker.wave.2"),
            CompactMetric(title: "analysis.statistics.medianVolume.label", value: metricNumber(volumeStatistics?.medianDBFS), unit: volumeUnit(volumeStatistics?.medianDBFS), symbol: "equal"),
            CompactMetric(title: "analysis.statistics.volumeRange.label", value: volumeRangeText, unit: String(localized: "common.unit.dbfsPercentileRange"), symbol: "arrow.left.and.right")
        ]
    }

    private func compactStatisticsSection(
        title: LocalizedStringKey,
        metrics: [CompactMetric]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                spacing: 12
            ) {
                ForEach(metrics.indices, id: \.self) { index in
                    let metric = metrics[index]
                    ResultMetric(
                        title: metric.title,
                        value: metric.value,
                        unit: metric.unit,
                        symbol: metric.symbol
                    )
                }
            }
        }
    }

    private func metricNumber(_ value: Double?) -> String {
        guard let value else { return String(localized: "common.placeholder.noValue") }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    private func pitchRangeText(_ statistics: RecordingPitchStatistics) -> String {
        guard let low = statistics.low5Hz,
              let high = statistics.high95Hz else { return String(localized: "common.placeholder.noValue") }
        return "\(metricNumber(low))–\(metricNumber(high))"
    }

    private func dominantPitchBand(
        _ statistics: RecordingPitchStatistics
    ) -> (name: String, percentage: String) {
        guard statistics.medianHz != nil else { return (String(localized: "common.placeholder.noValue"), "") }
        let bands = [
            (String(localized: "analysis.pitchBands.veryHigh"), statistics.veryHighPercentage),
            (String(localized: "analysis.pitchBands.feminine"), statistics.femininePercentage),
            (String(localized: "analysis.pitchBands.androgynous"), statistics.androgynousPercentage),
            (String(localized: "analysis.pitchBands.masculine"), statistics.masculinePercentage),
            (String(localized: "analysis.pitchBands.veryLow"), statistics.veryLowPercentage)
        ]
        guard let dominant = bands.max(by: { $0.1 < $1.1 }) else { return (String(localized: "common.placeholder.noValue"), "") }
        return (
            dominant.0,
            dominant.1.formatted(.percent.precision(.fractionLength(0)))
        )
    }

    private func volumeUnit(_ value: Double?) -> String {
        guard let value,
              let environment = volumeStatistics?.environmentDBFS else { return String(localized: "common.unit.dbfs") }
        let delta = (value - environment).formatted(
            .number
                .sign(strategy: .always())
                .precision(.fractionLength(1))
        )
        return String(localized: "common.unit.dbfsWithDelta \(delta)")
    }

    private var volumeRangeText: String {
        guard let low = volumeStatistics?.low5DBFS,
              let high = volumeStatistics?.high95DBFS else { return String(localized: "common.placeholder.noValue") }
        return "\(metricNumber(low))–\(metricNumber(high))"
    }

    private func scoreText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

}

private struct ScoreCircleSummary: View {
    let targetScore: Double
    let previousScore: Double?
    let previousMetrics: PreviousScoreMetrics?
    let masculine: Bool
    let animates: Bool
    let hasPlayed: Bool
    let onAnimationPlayed: () -> Void
    let result: PitcheeAnalysisResult
    let preference: VoicePreference

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart: Date?
    @State private var animationCompleted = false
    @State private var animationActivated = false
    @State private var soundPlayer: ScoreSoundPlayer?

    private var targetValue: Double {
        min(max(targetScore.isFinite ? targetScore : 0, 0), 100)
    }

    private var targetFemale: Double {
        masculine ? 100 - targetValue : targetValue
    }

    private var startFemale: Double {
        guard animates, let previousScore, previousScore.isFinite else { return 0 }
        let previous = min(max(previousScore, 0), 100)
        return masculine ? 100 - previous : previous
    }

    private var showsAnimatedChart: Bool {
        animates && !reduceMotion && (animationActivated || !hasPlayed)
    }

    var body: some View {
        circleChart
            .frame(height: 304)
            .overlay(alignment: .bottomTrailing) {
                NavigationLink {
                    ScoreExplanationView(
                        result: result,
                        preference: preference,
                        previousMetrics: previousMetrics
                    )
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .accessibilityLabel("analysis.score.explanation.a11y")
            }
            .task {
                guard animates, !hasPlayed, !animationActivated else { return }
                animationActivated = true
                onAnimationPlayed()
                soundPlayer = ScoreSoundPlayer()
                await animateScore()
            }
            .onDisappear {
                soundPlayer?.stop()
                soundPlayer = nil
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("analysis.score.summary.a11y \(targetScore.formatted(.number.precision(.fractionLength(1))))")
    }

    @ViewBuilder
    private var circleChart: some View {
        if showsAnimatedChart {
            TimelineView(.animation(
                minimumInterval: 1.0 / 120,
                paused: animationCompleted
            )) { timeline in
                ScoreCircleCanvas(
                    femaleScore: interpolatedFemaleScore(at: timeline.date)
                )
            }
        } else {
            ScoreCircleCanvas(femaleScore: targetFemale)
        }
    }

    private func interpolatedFemaleScore(at date: Date) -> Double {
        guard let animationStart else { return startFemale }
        let elapsed = max(0, date.timeIntervalSince(animationStart))
        let progress = min(1, elapsed / 0.9)
        let eased = 1 - pow(1 - progress, 3)
        return startFemale + (targetFemale - startFemale) * eased
    }

    private func animateScore() async {
        guard animates else { return }

        guard !reduceMotion else {
            soundPlayer?.play(score: targetValue, pitchScore: targetValue)
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        let initialDirectionScore = masculine ? 100 - startFemale : startFemale
        let delta = abs(targetValue - initialDirectionScore)
        if delta <= 0.01 {
            animationCompleted = true
            soundPlayer?.play(score: targetValue, pitchScore: targetValue)
            return
        }
        let tickCount = min(20, max(2, Int(ceil(delta / 3)) + 1))
        let tickInterval = 0.35 / Double(tickCount - 1)
        animationStart = Date()
        animationCompleted = false
        soundPlayer?.play(
            score: initialDirectionScore,
            pitchScore: initialDirectionScore
        )

        let soundTask = Task {
            for index in 1..<tickCount {
                let progress = Double(index) / Double(tickCount - 1)
                let interval = tickInterval * (0.8 + 0.6 * progress * progress)
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let elapsed = Date().timeIntervalSince(animationStart ?? Date())
                let animationProgress = min(1, elapsed / 0.9)
                let eased = 1 - pow(1 - animationProgress, 3)
                let femaleScore = startFemale + (targetFemale - startFemale) * eased
                let pitchScore = initialDirectionScore
                    + (targetValue - initialDirectionScore) * progress
                soundPlayer?.play(
                    score: masculine ? 100 - femaleScore : femaleScore,
                    pitchScore: pitchScore
                )
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(900))
        } catch {
            soundTask.cancel()
            return
        }
        animationCompleted = true
        await soundTask.value
    }
}

private struct ScoreCircleCanvas: View {
    let femaleScore: Double

    private let feminineColor = Color.pitcheeTendencyPink
    private let masculineColor = Color.pitcheeTendencySky
    private let feminineContent = Color(red: 58 / 255, green: 31 / 255, blue: 42 / 255)
    private let masculineContent = Color(red: 16 / 255, green: 36 / 255, blue: 67 / 255)

    var body: some View {
        Canvas { context, size in
            let female = min(max(femaleScore, 0), 100)
            let male = 100 - female
            let feminineVisual = min(max(female, 0), 112)
            let masculineVisual = min(max(male, 0), 112)
            let feminineSize = 76 + feminineVisual * 1.76
            let masculineSize = 76 + masculineVisual * 1.76
            let feminineTravel = cornerTravel(female)
            let masculineTravel = cornerTravel(male)
            let feminineCenter = CGPoint(x: feminineTravel, y: -feminineTravel * 0.82)
            let masculineCenter = CGPoint(x: -masculineTravel, y: masculineTravel * 0.82)

            let rawMinX = min(
                feminineCenter.x - feminineSize / 2,
                masculineCenter.x - masculineSize / 2
            )
            let rawMaxX = max(
                feminineCenter.x + feminineSize / 2,
                masculineCenter.x + masculineSize / 2
            )
            let rawMinY = min(
                feminineCenter.y - feminineSize / 2,
                masculineCenter.y - masculineSize / 2
            )
            let rawMaxY = max(
                feminineCenter.y + feminineSize / 2,
                masculineCenter.y + masculineSize / 2
            )
            let rawWidth = max(1, rawMaxX - rawMinX)
            let rawHeight = max(1, rawMaxY - rawMinY)
            let scale = min(
                max(1, (size.width - 40) / rawWidth),
                max(1, 288 / rawHeight)
            )

            let pinkSize = feminineSize * scale
            let blueSize = masculineSize * scale
            let pinkTravel = feminineTravel * scale
            let blueTravel = masculineTravel * scale
            let pinkCenter = CGPoint(x: pinkTravel, y: -pinkTravel * 0.82)
            let blueCenter = CGPoint(x: -blueTravel, y: blueTravel * 0.82)
            let groupMinX = min(pinkCenter.x - pinkSize / 2, blueCenter.x - blueSize / 2)
            let groupMaxX = max(pinkCenter.x + pinkSize / 2, blueCenter.x + blueSize / 2)
            let groupMinY = min(pinkCenter.y - pinkSize / 2, blueCenter.y - blueSize / 2)
            let groupMaxY = max(pinkCenter.y + pinkSize / 2, blueCenter.y + blueSize / 2)
            let offsetX = -(groupMinX + groupMaxX) / 2
            let offsetY = -(groupMinY + groupMaxY) / 2
            let pinkPoint = CGPoint(
                x: size.width / 2 + pinkCenter.x + offsetX,
                y: size.height / 2 + pinkCenter.y + offsetY
            )
            let bluePoint = CGPoint(
                x: size.width / 2 + blueCenter.x + offsetX,
                y: size.height / 2 + blueCenter.y + offsetY
            )

            drawCircle(
                score: male,
                color: masculineColor,
                contentColor: masculineContent,
                size: blueSize,
                center: bluePoint,
                context: &context
            )
            drawCircle(
                score: female,
                color: feminineColor,
                contentColor: feminineContent,
                size: pinkSize,
                center: pinkPoint,
                context: &context
            )
        }
        .accessibilityHidden(true)
    }

    private func drawCircle(
        score: Double,
        color: Color,
        contentColor: Color,
        size: CGFloat,
        center: CGPoint,
        context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
        context.fill(Path(ellipseIn: rect), with: .color(color))
        let progress = min(max(score / 100, 0), 1)
        let fontSize = 34 + 18 * sqrt(progress)
        context.draw(
            Text(
                verbatim: score.formatted(
                    .percent.scale(1).precision(.fractionLength(1))
                )
            )
            .font(PitcheeAndroidFont.font(size: fontSize, weight: .black))
            .foregroundStyle(contentColor),
            at: center
        )
    }

    private func cornerTravel(_ score: Double) -> Double {
        22 + (1 - min(max(score / 100, 0), 1)) * 42
    }
}

@MainActor
private final class ScoreSoundPlayer {
    private var players: [AVAudioPlayer] = []
    private var nextPlayer = 0
    private var sessionIsActive = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )
        guard let url = Bundle.main.url(forResource: "pitchee-score", withExtension: "wav") else {
            return
        }
        players = (0..<8).compactMap { _ -> AVAudioPlayer? in
            guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            player.enableRate = true
            player.prepareToPlay()
            return player
        }
    }

    func play(score: Double, pitchScore: Double) {
        guard !players.isEmpty else { return }
        if !sessionIsActive {
            try? AVAudioSession.sharedInstance().setActive(true)
            sessionIsActive = true
        }
        let scoreProgress = min(max(score / 100, 0), 1)
        let pitchProgress = min(max(pitchScore / 100, 0), 1)
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.currentTime = 0
        player.volume = Float(0.55 + scoreProgress * 0.20)
        player.rate = Float(0.80 + pitchProgress * 0.75)
        player.play()
    }

    func stop() {
        players.forEach { $0.stop() }
        if sessionIsActive {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            sessionIsActive = false
        }
    }
}

private struct ScoreIndicatorPresentation: Identifiable {
    let id: String
    let label: String
    let value: String
    let tier: String
    let passed: Bool
    let current: Double?
    let previous: Double?
    let unit: String

    private var delta: Double? {
        guard let current, let previous else { return nil }
        return current - previous
    }

    var comparisonText: String {
        guard let delta else { return SettingsCopy.text("较上次 —", "vs last —") }
        let arrow: String
        let value: Double
        if delta > 0.05 {
            arrow = "↑"
            value = delta
        } else if delta < -0.05 {
            arrow = "↓"
            value = abs(delta)
        } else {
            arrow = "→"
            value = 0
        }
        let formatted = unit == " Hz"
            ? value.formatted(.number.precision(.fractionLength(0)))
            : value.formatted(.number.precision(.fractionLength(1)))
        return SettingsCopy.text(
            "较上次 \(arrow) \(formatted)\(unit)",
            "vs last \(arrow) \(formatted)\(unit)"
        )
    }

    var comparisonColor: Color {
        guard let delta else { return .secondary }
        if delta > 0.05 { return .green }
        if delta < -0.05 { return .red }
        return .secondary
    }
}

struct ScoreExplanationView: View {
    let result: PitcheeAnalysisResult
    let preference: VoicePreference
    let previousMetrics: PreviousScoreMetrics?
    @State private var otherRulesExpanded = false

    init(
        result: PitcheeAnalysisResult,
        preference: VoicePreference = .undecided,
        previousMetrics: PreviousScoreMetrics? = nil
    ) {
        self.result = result
        self.preference = preference
        self.previousMetrics = previousMetrics
        #if DEBUG
        _otherRulesExpanded = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("-rules-expanded-preview")
        )
        #endif
    }

    private var directionScore: VoiceDirectionScore {
        preference.score(for: result)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(verbatim: SettingsCopy.text(
                    "结合本次指标查看综合分的计算过程",
                    "Review how this assessment produced the overall score."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                scoreOverview
                indicatorsSection
                commonFormulaSection
                currentRuleSection
                otherRulesSection
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Text(verbatim: SettingsCopy.text("评分规则", "Scoring Rules")))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scoreOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: SettingsCopy.text("本次综合分", "Overall score"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(directionScore.finalScore, format: .number.precision(.fractionLength(1)))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.pitcheeAccent)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: SettingsCopy.text("较上次", "vs last"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: scoreDeltaText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(scoreDeltaColor)
                }
            }
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var scoreDeltaText: String {
        guard let previous = previousMetrics?.finalScore else {
            return SettingsCopy.text("首次测评", "First assessment")
        }
        let delta = directionScore.finalScore - previous
        if delta > 0.05 {
            return "↑ \(delta.formatted(.number.precision(.fractionLength(1))))"
        }
        if delta < -0.05 {
            return "↓ \(abs(delta).formatted(.number.precision(.fractionLength(1))))"
        }
        return "→ 0.0"
    }

    private var scoreDeltaColor: Color {
        guard let previous = previousMetrics?.finalScore else { return .secondary }
        let delta = directionScore.finalScore - previous
        if delta > 0.05 { return .green }
        if delta < -0.05 { return .red }
        return .secondary
    }

    private var indicatorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: SettingsCopy.text("本次指标", "Current metrics"))
                .font(.title3.weight(.bold))

            VStack(spacing: 0) {
                ForEach(Array(scoreIndicators.enumerated()), id: \.element.id) { index, indicator in
                    HStack(spacing: 12) {
                        Image(systemName: indicator.passed ? "checkmark" : "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(indicator.passed ? Color.green : Color.red)
                            .frame(width: 36, height: 36)
                            .background(
                                (indicator.passed ? Color.green : Color.red).opacity(0.12),
                                in: Circle()
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: indicator.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(verbatim: indicator.value)
                                .font(.headline.weight(.bold).monospacedDigit())
                        }

                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(verbatim: indicator.tier)
                                .font(.subheadline.weight(.medium))
                            Text(verbatim: indicator.comparisonText)
                                .font(.caption)
                                .foregroundStyle(indicator.comparisonColor)
                        }
                    }
                    .padding(.vertical, 11)

                    if index < scoreIndicators.count - 1 {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private var scoreIndicators: [ScoreIndicatorPresentation] {
        let standard = directionScore.standardScore
        let naturalness = directionScore.naturalnessScore
        let f0 = result.f0.meanHz
        let rule = directionScore.rule

        let standardLimited: Bool
        let naturalnessLimited: Bool
        let f0Limited: Bool

        if preference == .masculine {
            standardLimited = standard < 50
            naturalnessLimited = naturalness < 50
            f0Limited = f0 == nil || (f0 ?? 0) >= 165
        } else {
            standardLimited = rule == "high_f0_male_cap"
                || (rule == "continuous" && standard < 50)
            naturalnessLimited = rule == "high_f0_stylized_cap"
                || rule == "low_f0_stylized_cap"
                || (rule == "continuous" && naturalness < 50)
            f0Limited = ["f0_unavailable", "low_f0_natural_cap", "low_f0_stylized_cap"].contains(rule)
                || (rule == "continuous" && (f0 == nil || (f0 ?? 0) <= 165))
        }

        let f0Score = f0.map { pitch -> Double in
            if preference == .masculine {
                return min(max((250 - pitch) / 150 * 100, 0), 100)
            }
            return min(max((pitch - 100) / 120 * 100, 0), 100)
        }
        let standardPassed = metricPassed(standard, limited: standardLimited)
        let naturalnessPassed = metricPassed(naturalness, limited: naturalnessLimited)
        let f0Passed = metricPassed(f0Score ?? 0, limited: f0Limited)
        let values: [ScoreIndicatorPresentation] = [
            ScoreIndicatorPresentation(
                id: "standard",
                label: SettingsCopy.text("音色分S", "Timbre S"),
                value: standard.formatted(.number.precision(.fractionLength(1))),
                tier: indicatorTier(standard, passed: standardPassed),
                passed: standardPassed,
                current: standard,
                previous: previousMetrics?.standardScore,
                unit: ""
            ),
            ScoreIndicatorPresentation(
                id: "naturalness",
                label: SettingsCopy.text("自然度N", "Naturalness N"),
                value: naturalness.formatted(.number.precision(.fractionLength(1))),
                tier: indicatorTier(naturalness, passed: naturalnessPassed),
                passed: naturalnessPassed,
                current: naturalness,
                previous: previousMetrics?.naturalnessScore,
                unit: ""
            ),
            ScoreIndicatorPresentation(
                id: "pitch",
                label: SettingsCopy.text("平均音高F0", "Mean pitch F0"),
                value: f0.map { "\($0.formatted(.number.precision(.fractionLength(0)))) Hz" }
                    ?? SettingsCopy.text("未检测到", "Not detected"),
                tier: f0Score.map { indicatorTier($0, passed: f0Passed) }
                    ?? SettingsCopy.text("未检测到", "Not detected"),
                passed: f0Passed,
                current: f0,
                previous: previousMetrics?.meanPitchHz,
                unit: " Hz"
            )
        ]
        return values.filter { !$0.passed } + values.filter(\.passed)
    }

    private func indicatorTier(_ value: Double, passed: Bool) -> String {
        if value < 50 { return SettingsCopy.text("不通过", "Not passed") }
        if !passed { return SettingsCopy.text("综分限制项", "Score limiter") }
        return switch value {
        case 50..<60: SettingsCopy.text("好", "Fair")
        case 60..<70: SettingsCopy.text("良好", "Good")
        case 70..<80: SettingsCopy.text("很好", "Great")
        default: SettingsCopy.text("非常好", "Excellent")
        }
    }

    private func metricPassed(_ score: Double, limited: Bool) -> Bool {
        !limited && score >= 50
    }

    private var commonFormulaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: SettingsCopy.text("基础公式", "Base formulas"))
                .font(.title3.weight(.bold))
            Text(verbatim: SettingsCopy.text(
                "所有规则以此基础计算",
                "All rules build on these base calculations."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            FormulaBlock(lines: preference == .masculine ? [
                #"\mathrm{Standard} = 100 - \mathrm{VFP}"#,
                #"F_0 = \overline{f_0}"#,
                #"d_{F_0} = \min(1, \max(-1, \frac{165 - F_0}{75}))"#,
                #"d_{VFP} = \min(1, \max(-1, \frac{50 - VFP}{50}))"#,
                #"\mathrm{Base} = \mathrm{Final} = \min(100, \max(0, 60 + 25d_{F_0} + 15d_{VFP}))"#
            ] : [
                #"\mathrm{Standard} = \mathrm{VFP}"#,
                #"\mathrm{Naturalness} \in [0,100]"#,
                #"F_0 = \overline{f_0}"#,
                #"S_r = \frac{\mathrm{Standard}}{100}"#,
                #"\begin{aligned}n &= \frac{\mathrm{Naturalness} - 40}{50} \\ N_r &= \min(1,\max(0,n))\end{aligned}"#,
                #"F_{0r} = \min\left(1, \max\left(0, \frac{F_0 - 110}{90}\right)\right)"#,
                #"\begin{aligned}\mathrm{Base} &= 100 \times \bigl(0.50\,S_r + 0.20\,N_r \\ &\quad + 0.15\,F_{0r} + 0.15\,S_r\,N_r\,F_{0r}\bigr)\end{aligned}"#,
                #"\mathrm{Base} \xrightarrow{\mathrm{rule}} \mathrm{Final}"#
            ])
            Text(verbatim: preference == .masculine
                ? SettingsCopy.text(
                    "Standard 是男性化倾向，即 100 减去模型的女性化倾向分；Naturalness 是自然度分；音高是整段语音的平均音高，单位为 Hz。归一化变量限制在 0 到 1 之间：音高分量在 110 Hz 及以下为 1，在 200 Hz 及以上为 0。Base 是调整前的基础分，Final 是显示的男性化评分。",
                    "Standard is masculine tendency: 100 minus the model's feminine tendency score. Naturalness is the naturalness score. Pitch is the mean F0 in Hz. Normalized variables are clamped from 0 to 1: the pitch component is 1 at 110 Hz or below and 0 at 200 Hz or above. Base is the pre-rule score and Final is the displayed masculine score."
                )
                : SettingsCopy.text(
                    "Standard 是模型识别的音色分；Naturalness 是自然度分；音高是整段语音的平均音高，单位为 Hz。带 _r 的变量会被限制在 0 到 1 之间。Base 是应用规则前的基础分，Final 是结果页显示的综合分。",
                    "Standard is the model's timbre score; Naturalness is the naturalness score; Pitch is the mean F0 of the recording in Hz. Variables ending in _r are clamped from 0 to 1. Base is the score before rules and Final is the score shown on the result page."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentRuleSection: some View {
        let rule = currentRuleDocumentation

        return VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: SettingsCopy.text("本次命中规则", "Matched rule"))
                .font(.title3.weight(.bold))
            Text(verbatim: androidInsightDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ruleDetailsCard(rule, isCurrent: true)
        }
    }

    private func ruleDetail(_ title: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let text {
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var otherRulesSection: some View {
        let otherRules = ruleDocumentation.filter { $0.id != directionScore.rule }

        return DisclosureGroup(isExpanded: $otherRulesExpanded) {
            VStack(spacing: 0) {
                ForEach(Array(otherRules.enumerated()), id: \.element.id) { index, rule in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: rule.title)
                            .font(.headline.weight(.semibold))
                        Text(verbatim: rule.guidance)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        ruleDetail(SettingsCopy.text("触发条件", "Trigger"), text: rule.condition)
                        ruleDetail(SettingsCopy.text("计算公式", "Formula"), text: nil)
                        FormulaBlock(lines: rule.formulas)
                        ruleDetail(SettingsCopy.text("处理结果", "Result"), text: rule.result)
                    }
                    .padding(.top, index == 0 ? 12 : 18)
                    .padding(.bottom, 14)

                    if index < otherRules.count - 1 {
                        Divider()
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: SettingsCopy.text(
                    "未触发的其他规则",
                    "Other rules not triggered"
                ))
                .font(.subheadline.weight(.semibold))
                Text(verbatim: SettingsCopy.text(
                    "\(otherRules.count) 条规则",
                    "\(otherRules.count) rules"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func ruleDetailsCard(_ rule: ScoreRuleDocumentation, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: rule.title)
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                if isCurrent {
                    Text(verbatim: SettingsCopy.text("当前命中", "Matched"))
                        .font(.caption)
                        .foregroundStyle(Color.pitcheeAccent)
                }
            }
            Text(verbatim: rule.guidance)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            ruleDetail(SettingsCopy.text("触发条件", "Trigger"), text: rule.condition)
            ruleDetail(SettingsCopy.text("计算公式", "Formula"), text: nil)
            FormulaBlock(lines: rule.formulas)
            ruleDetail(SettingsCopy.text("处理结果", "Result"), text: rule.result)
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var currentRuleDocumentation: ScoreRuleDocumentation {
        ruleDocumentation.first { $0.id == directionScore.rule } ?? ruleDocumentation[0]
    }

    private var androidInsightDescription: String {
        if preference == .masculine {
            return SettingsCopy.text(
                "综合分会结合音高和音色相对中性参考的位置计算。",
                "The overall score combines pitch and timbre relative to a neutral reference."
            )
        }
        return switch directionScore.rule {
        case "pass_boost":
            SettingsCopy.text(
                "三项条件同时满足时，综合分进入 60–100 区间。",
                "When all three conditions are met, the overall score moves into the 60–100 range."
            )
        case "high_f0_stylized_cap":
            SettingsCopy.text(
                "音高已经较高，但自然度低于 50，限制了最终分数。",
                "Pitch is high, but naturalness is below 50, limiting the final score."
            )
        case "low_f0_natural_cap":
            SettingsCopy.text(
                "自然度达标，但音高小于 165 Hz，限制了最终分数。",
                "Naturalness passes, but pitch is below 165 Hz, limiting the final score."
            )
        case "low_f0_stylized_cap":
            SettingsCopy.text(
                "音高低于 165 Hz 且自然度低于 50，同时限制了最终分数。",
                "Pitch is below 165 Hz and naturalness is below 50, together limiting the final score."
            )
        case "high_f0_male_cap":
            SettingsCopy.text(
                "音高高于 165 Hz，但音色分低于 50，限制了最终分数。",
                "Pitch is above 165 Hz, but the timbre score is below 50, limiting the final score."
            )
        case "f0_unavailable":
            SettingsCopy.text(
                "未找到可靠的音高，本次直接使用音色分，未套用综合分公式。",
                "No reliable pitch was found, so the overall score uses the timbre score."
            )
        default:
            SettingsCopy.text(
                "本次没有触发封顶或提升。",
                "No cap or boost was triggered this time."
            )
        }
    }

    private var ruleDocumentation: [ScoreRuleDocumentation] {
        scoreRuleDocumentation(for: preference)
    }

}

private struct FormulaBlock: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                LaTeX("\\[\(line)\\]")
                    .font(.subheadline)
                    .imageRenderingMode(.template)
                    .blockMode(.blockViews)
                    .errorMode(.rendered)
                    .renderingStyle(.redactedOriginal)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ScoreRuleDocumentation: Identifiable {
    let id: String
    let title: String
    let guidance: String
    let condition: String
    let formulas: [String]
    let result: String
}

private let scoreRuleDocumentation: [ScoreRuleDocumentation] = [
    androidRuleDocumentation(
        id: "continuous",
        formulas: [#"\mathrm{Final} = \mathrm{Base}"#]
    ),
    androidRuleDocumentation(
        id: "pass_boost",
        formulas: [
            #"s_F = \frac{F_0 - 165}{25}"#,
            #"s_N = \frac{\mathrm{Naturalness} - 80}{20}"#,
            #"s_S = \frac{\mathrm{Standard} - 50}{30}"#,
            #"\mathrm{strength} = \min(s_F, s_N, s_S, 1)"#,
            #"\mathrm{promoted} = 60 + 40 \times \mathrm{strength}"#,
            #"\mathrm{Final} = \max(\mathrm{Base}, \mathrm{promoted})"#
        ]
    ),
    androidRuleDocumentation(
        id: "high_f0_stylized_cap",
        formulas: [#"\mathrm{Final} = \min(\mathrm{Base}, 30)"#]
    ),
    androidRuleDocumentation(
        id: "low_f0_natural_cap",
        formulas: [#"\mathrm{Final} = \min(\mathrm{Base}, 59)"#]
    ),
    androidRuleDocumentation(
        id: "low_f0_stylized_cap",
        formulas: [#"\mathrm{Final} = \min(\mathrm{Base}, 20)"#]
    ),
    androidRuleDocumentation(
        id: "high_f0_male_cap",
        formulas: [#"\mathrm{Final} = \min(\mathrm{Base}, 59)"#]
    ),
    androidRuleDocumentation(
        id: "f0_unavailable",
        formulas: [#"\mathrm{Final} = \mathrm{Standard}"#]
    )
]

private let masculineScoreRuleDocumentation: [ScoreRuleDocumentation] = [
    androidRuleDocumentation(
        id: "masculine_continuous",
        formulas: [
            #"d_{F_0} = \min(1, \max(-1, \frac{165 - F_0}{75}))"#,
            #"d_{VFP} = \min(1, \max(-1, \frac{50 - VFP}{50}))"#,
            #"\mathrm{Base} = \mathrm{Final} = \min(100, \max(0, 60 + 25d_{F_0} + 15d_{VFP}))"#
        ]
    )
]

private func androidRuleDocumentation(
    id: String,
    formulas: [String]
) -> ScoreRuleDocumentation {
    let copy: (title: String, guidance: String, condition: String, result: String)
    switch id {
    case "pass_boost":
        copy = (
            SettingsCopy.text("加分", "Boost"),
            SettingsCopy.text("完全“Pass”。恭喜！请继续加油。", "A clear “Pass.” Congratulations—keep it up."),
            "F0 > 165, Naturalness > 80, Standard > 50",
            SettingsCopy.text(
                "综合分最高为 100。\n如果 promoted > Base，综合分采用 promoted。",
                "The overall score caps at 100.\nWhen promoted > Base, the result uses promoted."
            )
        )
    case "high_f0_stylized_cap":
        copy = (
            SettingsCopy.text("高音高、低自然度封顶", "High pitch and low naturalness cap"),
            SettingsCopy.text("刻意抬升音高而导致发声不健康的结果。请量力而行。", "This result comes from forcing pitch higher in a way that makes phonation less healthy. Stay within your comfortable limits."),
            "F0 > 165, Naturalness < 50",
            SettingsCopy.text("综合分最高为 30。", "The overall score caps at 30.")
        )
    case "low_f0_natural_cap":
        copy = (
            SettingsCopy.text("低音高封顶", "Low pitch cap"),
            SettingsCopy.text("自然度已经不错，接下来把注意力放在音高上。", "Naturalness is already good. Focus on pitch next."),
            "F0 ≤ 165, Naturalness ≥ 50",
            SettingsCopy.text("综合分最高为 59。", "The overall score caps at 59.")
        )
    case "low_f0_stylized_cap":
        copy = (
            SettingsCopy.text("低音高、低自然度", "Low pitch and low naturalness"),
            SettingsCopy.text("音高和自然度都需要照顾。请先完整自然地读完整段语料。", "Both pitch and naturalness need attention. Read the full passage naturally from beginning to end."),
            "F0 ≤ 165, Naturalness < 50",
            SettingsCopy.text("综合分最高为 20。", "The overall score caps at 20.")
        )
    case "high_f0_male_cap":
        copy = (
            SettingsCopy.text("音色分不足", "Timbre score cap"),
            SettingsCopy.text("你的声音在高音调下仍保持自然，说明你的问题不在音高上。接下来请尝试缩短声道，将共鸣焦点前移，方法包括但不限于：舌位前移、唇部展开。", "Your voice stays natural at a higher pitch, so pitch is not the issue here. Next, try shortening the vocal tract and moving the resonance focus forward. This may include moving the tongue forward and spreading the lips, among other approaches."),
            "F0 > 165, Naturalness ≥ 50, Standard < 50",
            SettingsCopy.text("综合分最高为 59。", "The overall score caps at 59.")
        )
    case "f0_unavailable":
        copy = (
            SettingsCopy.text("音高不可用", "Pitch unavailable"),
            SettingsCopy.text("没有识别到稳定音高，下次可以离麦克风近一点。", "No stable pitch was detected. Try moving closer to the microphone."),
            SettingsCopy.text("音高不可用", "Pitch unavailable"),
            SettingsCopy.text("综合分直接采用音色分。", "The overall score uses the timbre score directly.")
        )
    case "masculine_continuous":
        copy = (
            SettingsCopy.text("男性向连续评分", "Masculine continuous scoring"),
            SettingsCopy.text("音高低于 165 Hz、音色更偏中性或低沉时，男性向综合分会提高。", "Pitch below 165 Hz and a less feminine timbre raise the masculine score."),
            SettingsCopy.text("适用于能够完成分析的录音。", "Applies to recordings that complete analysis."),
            SettingsCopy.text("综合分直接采用男性向公式的结果。", "The overall score uses the masculine formula directly.")
        )
    default:
        copy = (
            SettingsCopy.text("连续评分", "Continuous scoring"),
            SettingsCopy.text("基本“Pass”，达到及格线。请保持现在的状态。", "A basic “Pass”—at or above the passing line. Keep things as they are."),
            SettingsCopy.text("未命中下列任何封顶或提升规则", "Does not trigger any cap or boost rule below"),
            SettingsCopy.text("综合分采用 Base。", "The overall score uses Base.")
        )
    }
    return ScoreRuleDocumentation(
        id: id == "masculine_continuous" ? "continuous" : id,
        title: copy.title,
        guidance: copy.guidance,
        condition: copy.condition,
        formulas: formulas,
        result: copy.result
    )
}

private func scoreRuleDocumentation(for preference: VoicePreference) -> [ScoreRuleDocumentation] {
    preference == .masculine ? masculineScoreRuleDocumentation : scoreRuleDocumentation
}

struct VoiceProfileReferenceChart: View {
    let femalePercentage: Double
    let meanPitchHz: Double?
    let medianPitchHz: Double?
    let pitchRangeHz: ClosedRange<Double>?
    @State private var measuredWidth: CGFloat = 0

    private let designSize = CGSize(width: 760, height: 598)
    private let borderColor = Color(red: 134.0 / 255.0, green: 63.0 / 255.0, blue: 63.0 / 255.0)
    private let valueColor = Color(red: 98.0 / 255.0, green: 98.0 / 255.0, blue: 98.0 / 255.0)
    private let femaleColor = Color(red: 241.0 / 255.0, green: 155.0 / 255.0, blue: 145.0 / 255.0)
    private let maleColor = Color(red: 115.0 / 255.0, green: 191.0 / 255.0, blue: 249.0 / 255.0)

    private var femaleValue: Double {
        guard femalePercentage.isFinite else { return 0 }
        return min(max(femalePercentage, 0), 100)
    }

    private var maleValue: Double { 100 - femaleValue }

    var body: some View {
        Group {
            if measuredWidth > 0 {
                chartCanvas(width: measuredWidth)
            } else {
                Color.clear
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ChartWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(ChartWidthPreferenceKey.self) { width in
            guard width.isFinite, width > 0, abs(width - measuredWidth) > 0.5 else { return }
            measuredWidth = width
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "analysis.voiceProfile.reference.a11y \(meanPitchText) \(pitchRangeText) \(medianPitchText) \(percentageText(femaleValue)) \(percentageText(maleValue))"
        )
    }

    private func chartCanvas(width: CGFloat) -> some View {
        let scale = width / designSize.width

        return ZStack(alignment: .topLeading) {
            metricRows(scale: scale)
                .frame(width: 300 * scale, alignment: .leading)
                .offset(x: 41 * scale, y: 41 * scale)

            TendencyPie(
                femalePercentage: femaleValue,
                malePercentage: maleValue,
                femaleColor: femaleColor,
                maleColor: maleColor
            )
            .frame(width: 261 * scale, height: 261 * scale)
            .offset(x: 33 * scale, y: 217 * scale)

            PitchGenderScale(
                meanHz: meanPitchHz,
                rangeHz: pitchRangeHz,
                femaleColor: femaleColor,
                maleColor: maleColor,
                markerColor: borderColor,
                valueColor: valueColor
            )
            .frame(width: 160 * scale, height: 430 * scale)
            .offset(x: 575 * scale, y: 56 * scale)
        }
        .frame(
            width: designSize.width * scale,
            height: designSize.height * scale,
            alignment: .topLeading
        )
        .background(Color.white)
        .overlay {
            Rectangle()
                .strokeBorder(borderColor, lineWidth: 1.75)
        }
    }

    private func metricRows(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9 * scale) {
            metricRow(
                SettingsCopy.text("范围", "Range"),
                value: pitchRangeText,
                scale: scale
            )
            metricRow(
                SettingsCopy.text("平均值", "Average"),
                value: meanPitchText,
                scale: scale
            )
            metricRow(
                SettingsCopy.text("中位数", "Median"),
                value: medianPitchText,
                scale: scale
            )
        }
    }

    private func metricRow(_ label: String, value: String, scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: label)
                .font(.system(size: 35 * scale, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 120 * scale, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(verbatim: value)
                .font(.system(size: 29 * scale))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .offset(x: -2 * scale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percentageText(_ percentage: Double) -> String {
        percentage.formatted(.percent.scale(1).precision(.fractionLength(0)))
    }

    private var meanPitchText: String {
        guard let meanPitchHz, meanPitchHz.isFinite else { return String(localized: "analysis.voiceProfile.noData") }
        return "\(meanPitchHz.formatted(.number.precision(.fractionLength(0))))Hz"
    }

    private var medianPitchText: String {
        guard let medianPitchHz, medianPitchHz.isFinite else {
            return String(localized: "analysis.voiceProfile.noData")
        }
        return "\(medianPitchHz.formatted(.number.precision(.fractionLength(0))))Hz"
    }

    private var pitchRangeText: String {
        guard let pitchRangeHz else { return String(localized: "analysis.voiceProfile.noData") }
        return "\(pitchRangeHz.lowerBound.formatted(.number.precision(.fractionLength(0))))-\(pitchRangeHz.upperBound.formatted(.number.precision(.fractionLength(0))))Hz"
    }
}

private struct ChartWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TendencyPie: View {
    let femalePercentage: Double
    let malePercentage: Double
    let femaleColor: Color
    let maleColor: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let half = side / 2
            ZStack {
                Circle()
                    .fill(maleColor)
                Circle()
                    .fill(femaleColor)
                    .mask {
                        Rectangle()
                            .frame(width: half, height: side)
                            .offset(x: -half / 2)
                    }
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: side)
                    .position(x: side / 2, y: side / 2)
                Text(verbatim: percentageText(femalePercentage))
                    .font(.system(size: side * 0.185, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .position(x: side * 0.25, y: side * 0.477)
                Text(verbatim: percentageText(malePercentage))
                    .font(.system(size: side * 0.185, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .position(x: side * 0.75, y: side * 0.539)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func percentageText(_ percentage: Double) -> String {
        percentage.formatted(.percent.scale(1).precision(.fractionLength(0)))
    }
}

private struct VoiceProfileMetricBars: View {
    let naturalnessScore: Double
    let timbreScore: Double
    let meanPitchHz: Double?
    let masculine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricRow(
                title: Text(verbatim: SettingsCopy.text("音色分 T", "Timbre T")),
                value: scoreValue(timbreScore),
                progress: normalized(timbreScore),
                scoreForColor: timbreScore
            )
            metricRow(
                title: Text(verbatim: SettingsCopy.text("自然分 N", "Naturalness N")),
                value: scoreValue(naturalnessScore),
                progress: normalized(naturalnessScore),
                scoreForColor: naturalnessScore
            )
            metricRow(
                title: Text(verbatim: SettingsCopy.text("平均音高 F0", "Mean pitch F0")),
                value: pitchValue,
                progress: pitchProgress,
                scoreForColor: pitchProgress * 100
            )

            Text(verbatim: SettingsCopy.text(
                "*按 100–250 Hz 映射",
                "*Mapped to 100–250 Hz"
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricRow(
        title: Text,
        value: String,
        progress: Double,
        scoreForColor: Double
    ) -> some View {
        let color = scoreColor(scoreForColor)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                title
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(verbatim: value)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { proxy in
                let width = proxy.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.14))
                        .frame(width: width, height: 8)
                    Capsule()
                        .fill(color)
                        .frame(width: min(max(0, width * progress), width), height: 8)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(value)
    }

    private var pitchValue: String {
        guard let meanPitchHz, meanPitchHz.isFinite, meanPitchHz > 0 else { return "—" }
        return "\(meanPitchHz.formatted(.number.precision(.fractionLength(0)))) Hz"
    }

    private var pitchProgress: Double {
        guard let meanPitchHz, meanPitchHz.isFinite else { return 0 }
        let score = masculine
            ? (250 - meanPitchHz) / 150 * 100
            : (meanPitchHz - 100) / 120 * 100
        return min(max(score / 100, 0), 1)
    }

    private func normalized(_ score: Double) -> Double {
        guard score.isFinite else { return 0 }
        return min(max(score / 100, 0), 1)
    }

    private func scoreValue(_ score: Double) -> String {
        score.isFinite
            ? score.formatted(.number.precision(.fractionLength(1)))
            : "—"
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case ..<20:
            Color(red: 213 / 255, green: 83 / 255, blue: 98 / 255)
        case ..<40:
            Color(red: 228 / 255, green: 122 / 255, blue: 54 / 255)
        case ..<60:
            Color(red: 217 / 255, green: 181 / 255, blue: 61 / 255)
        case ..<80:
            Color(red: 87 / 255, green: 167 / 255, blue: 115 / 255)
        default:
            Color(red: 22 / 255, green: 140 / 255, blue: 128 / 255)
        }
    }
}

private struct PitchGenderScale: View {
    let meanHz: Double?
    let rangeHz: ClosedRange<Double>?
    let femaleColor: Color
    let maleColor: Color
    let markerColor: Color
    let valueColor: Color

    private let minimumHz = 100.0
    private let maximumHz = 300.0
    private let thresholdHz = 160.0
    private let designWidth: CGFloat = 160

    private var normalizedValue: CGFloat? {
        guard let meanHz, meanHz.isFinite, meanHz > 0 else { return nil }
        return normalized(meanHz)
    }

    private var normalizedRange: ClosedRange<CGFloat>? {
        guard let rangeHz,
              rangeHz.lowerBound.isFinite, rangeHz.upperBound.isFinite,
              rangeHz.lowerBound > 0 else { return nil }
        return normalized(rangeHz.lowerBound)...normalized(rangeHz.upperBound)
    }

    private func normalized(_ frequency: Double) -> CGFloat {
        CGFloat(min(max((frequency - minimumHz) / (maximumHz - minimumHz), 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / designWidth, proxy.size.height / 430)
            let height = 430 * scale
            let trackWidth = 13 * scale
            let rangeWidth = 48 * scale
            let averageWidth = 81 * scale
            let centerX = 40 * scale
            let labelWidth = 75 * scale
            let blueHeight = height * CGFloat(
                (thresholdHz - minimumHz) / (maximumHz - minimumHz)
            )

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(femaleColor)
                    Rectangle()
                        .fill(maleColor)
                        .frame(height: blueHeight)
                }
                .frame(width: trackWidth, height: height)
                .clipShape(Capsule())
                .position(x: centerX, y: height / 2)

                if let normalizedRange {
                    let top = (1 - normalizedRange.upperBound) * height
                    let bottom = (1 - normalizedRange.lowerBound) * height
                    let rangeHeight = min(height, max(8 * scale, bottom - top))
                    let originY = min(
                        max(0, (top + bottom - rangeHeight) / 2),
                        height - rangeHeight
                    )
                    Rectangle()
                        .fill(Color.gray.opacity(0.59))
                        .frame(width: rangeWidth, height: rangeHeight)
                        .position(x: centerX, y: originY + rangeHeight / 2)
                }

                if let normalizedValue {
                    let markerY = min(max(1, (1 - normalizedValue) * height), height - 1)
                    Rectangle()
                        .fill(markerColor)
                        .frame(width: averageWidth, height: 5 * scale)
                        .position(x: centerX, y: markerY)
                    Text(verbatim: "Avg")
                        .font(.system(size: 24 * scale))
                        .foregroundStyle(valueColor)
                        .frame(width: labelWidth, alignment: .leading)
                        .position(x: (87 + 37.5) * scale, y: markerY)
                }

                Text(verbatim: "300Hz")
                    .font(.system(size: 21 * scale))
                    .foregroundStyle(valueColor)
                    .frame(width: labelWidth, alignment: .leading)
                    .position(x: (79 + 37.5) * scale, y: 11 * scale)
                Text(verbatim: "100Hz")
                    .font(.system(size: 21 * scale))
                    .foregroundStyle(valueColor)
                    .frame(width: labelWidth, alignment: .leading)
                    .position(x: (79 + 37.5) * scale, y: height - 12 * scale)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CompactMetric {
    let title: LocalizedStringKey
    let value: String
    let unit: String
    let symbol: String
}

private struct ResultMetric: View {
    let title: LocalizedStringKey
    let value: String
    let unit: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 5) { number; suffix }
                VStack(alignment: .leading, spacing: 4) { number; suffix }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var number: some View {
        Text(value)
            .font(.title2.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
    private var suffix: some View { Text(unit).font(.caption).foregroundStyle(.secondary) }
}

#if DEBUG
private struct RecordingAnalysisPreview: View {
    @StateObject private var viewModel: AnalysisViewModel

    init(state: AnalysisViewModel.State) {
        _viewModel = StateObject(wrappedValue: .preview(state: state))
    }

    var body: some View {
        NavigationStack {
            RecordingAnalysisView(viewModel: viewModel)
        }
    }
}

#Preview("Mock - Result") {
    RecordingAnalysisPreview(state: .completed)
}

#Preview("Mock - Analyzing") {
    RecordingAnalysisPreview(state: .analyzing)
}

#Preview("Debug - No Result") {
    RecordingAnalysisPreview(state: .idle)
}

#Preview("Mock - Result Save Error") {
    NavigationStack {
        RecordingResultView(
            result: DebugPreviewData.result,
            volumeStatistics: nil,
            saveError: String(localized: "analysis.error.resultSaveFailed")
        )
    }
}

#Preview("Mock - Score Explanation") {
    NavigationStack {
        ScoreExplanationView(
            result: DebugPreviewData.result,
            previousMetrics: DebugPreviewData.previousMetrics
        )
    }
}
#endif
