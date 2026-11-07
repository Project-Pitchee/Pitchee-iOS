//
//  RecordingAnalysisView.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/18.
//

import SwiftUI
import LaTeXSwiftUI
import UIKit

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
                    recordedPreference: viewModel.assessment?.recordedTarget
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
    private let showsBackground: Bool
    private let showsTrainingSuggestions: Bool
    private let pitchStatistics: RecordingPitchStatistics
    private let pitchTimeline: PitchTimeline

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsVoiceDetails = false
    @State private var selectedVoiceArticle: VoiceArticle?
    @State private var showsAllTrainingArticles = false
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""

    private var voicePreference: VoicePreference {
        recordedPreference ?? VoicePreference(legacyStoredValue: savedVoicePreference) ?? .undecided
    }

    private var directionScore: VoiceDirectionScore {
        voicePreference.score(for: result)
    }

    init(
        result: PitcheeAnalysisResult,
        volumeStatistics: RecordingVolumeStatistics?,
        saveError: String?,
        recordingNotice: String? = nil,
        quality: RecordingQuality? = nil,
        recordedPreference: VoicePreference? = nil,
        showsBackground: Bool = true,
        showsTrainingSuggestions: Bool = true
    ) {
        self.result = result
        self.volumeStatistics = volumeStatistics
        self.saveError = saveError
        self.recordingNotice = recordingNotice
        self.quality = quality
        self.recordedPreference = recordedPreference
        self.showsBackground = showsBackground
        self.showsTrainingSuggestions = showsTrainingSuggestions
        self.pitchStatistics = RecordingPitchStatistics(pitch: result.f0)
        self.pitchTimeline = PitchTimeline(result: result)
    }

    var body: some View {
        Group {
            if showsTrainingSuggestions {
                FoldAwareArrangementView(
                    primary: { resultPane(resultOverview) },
                    secondary: { resultPane(resultSecondary) },
                    regular: { resultScroll(allContent) }
                )
            } else {
                resultScroll(resultOverview)
            }
        }
        .background {
            if showsBackground {
                Color(uiColor: .systemGroupedBackground)
            }
        }
        .sheet(isPresented: $showsVoiceDetails) {
            voiceDetailsSheet
        }
        .sheet(item: $selectedVoiceArticle) { article in
            VoiceArticleDetailView(article: article)
        }
        .sheet(isPresented: $showsAllTrainingArticles) {
            VoiceTrainingLibraryBrowserView()
        }
    }

    private var resultOverview: some View {
        VStack(alignment: .leading, spacing: 24) {
            if RecordingQuality.hasSufficientSpeech(result.vad.speechSeconds) {
                scoreSummary
            } else {
                Label("analysis.score.insufficientSpeech", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            scoreMetrics

            pitchTraceSection

            voiceProfileSection

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

    private var scoreMetrics: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            ResultMetric(title: "analysis.result.timbre.title", value: scoreText(directionScore.standardScore), unit: String(localized: "common.unit.pointsOutOf100"), symbol: "slider.horizontal.3", compact: !dynamicTypeSize.isAccessibilitySize)
            ResultMetric(title: "analysis.result.naturalness.title", value: scoreText(directionScore.naturalnessScore), unit: String(localized: "common.unit.pointsOutOf100"), symbol: "leaf", compact: !dynamicTypeSize.isAccessibilitySize)
            ResultMetric(title: "analysis.result.meanF0.title", value: metricNumber(pitchStatistics.averageHz), unit: String(localized: "common.unit.hertz"), symbol: "waveform.path", compact: !dynamicTypeSize.isAccessibilitySize)
        }
        .labelStyle(.titleOnly)
        .accessibilityElement(children: .contain)
    }

    private var pitchTraceSection: some View {
        DisclosureGroup {
            MonitorPitchPlot(
                samples: pitchTimeline.samples,
                timeRange: 0...max(0.001, pitchTimeline.duration),
                cursorTime: pitchTimeline.duration
            )
            .frame(height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("monitor.pitch.chart.title")
            .accessibilityValue(Text("export.pitchImage.chart.duration \(pitchTimeline.duration.formatted())"))
            .padding(.top, 12)
        } label: {
            Label("monitor.pitch.chart.title", systemImage: "waveform.path")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var voiceProfileSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("analysis.voiceProfile.title")
                    .font(.title3.weight(.bold))

                Spacer(minLength: 8)

                Button {
                    showsVoiceDetails = true
                } label: {
                    HStack(spacing: 4) {
                        Text("analysis.voiceDetails.action")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("analysis.voiceDetails.action.a11y")
            }

            VoiceProfileReferenceChart(
                femalePercentage: result.vfp.vfpStandardScore,
                meanPitchHz: result.f0.meanHz,
                pitchRangeHz: pitchRangeHz
            )
        }
    }

    private var resultSecondary: some View {
        VStack(alignment: .leading, spacing: 28) {
            RecordingTrainingSuggestions(
                result: result,
                preference: voicePreference,
                quality: quality,
                volumeStatistics: volumeStatistics,
                onSelectArticle: { selectedVoiceArticle = $0 },
                onBrowseLibrary: { showsAllTrainingArticles = true }
            )
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
                .padding(24)
        }
    }

    private func resultPane<Content: View>(_ content: Content) -> some View {
        resultScroll(content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var voiceDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("analysis.voiceDetails.metrics.title")
                            .font(.title3.weight(.bold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                            ResultMetric(title: "common.metric.naturalness.title", value: scoreText(directionScore.naturalnessScore), unit: String(localized: "common.unit.pointsOutOf100"), symbol: "leaf")
                            ResultMetric(title: voicePreference.standardMetricTitle, value: scoreText(directionScore.standardScore), unit: String(localized: "common.unit.pointsOutOf100"), symbol: "slider.horizontal.3")
                            ResultMetric(title: "common.metric.speechDuration.title", value: result.vad.speechSeconds.formatted(.number.precision(.fractionLength(1))), unit: String(localized: "common.unit.seconds"), symbol: "bubble.left")
                        }
                    }

                    recordingStatistics
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("analysis.voiceDetails.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.action.done") { showsVoiceDetails = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var scoreSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(voicePreference.scoreTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink {
                    ScoreExplanationView(result: result, preference: voicePreference)
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

            ProgressView(value: scoreProgress, total: 1)
                .tint(Color.pitcheeAccent)
                .scaleEffect(x: 1, y: 1.35, anchor: .center)
                .accessibilityLabel("analysis.score.progress.a11y")
                .accessibilityValue("analysis.score.progress.a11yValue \(scoreText(directionScore.finalScore))")

            Text(scoreHeadline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("analysis.score.summary.a11y \(scoreText(directionScore.finalScore))")
    }

    private var scoreProgress: Double {
        min(max(directionScore.finalScore / 100, 0), 1)
    }

    private var scoreHeadline: String {
        switch directionScore.finalScore {
        case 90...: return String(localized: "analysis.score.headlineHigh")
        case 70..<90: return String(localized: "analysis.score.headlineMedium")
        default: return String(localized: "analysis.score.headlineLow")
        }
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

/// Article loading belongs to the optional suggestions, so a result can also
/// render from supplied values alone in the onboarding app preview.
private struct RecordingTrainingSuggestions: View {
    let result: PitcheeAnalysisResult
    let preference: VoicePreference
    let quality: RecordingQuality?
    let volumeStatistics: RecordingVolumeStatistics?
    let onSelectArticle: (VoiceArticle) -> Void
    let onBrowseLibrary: () -> Void

    @ObservedObject private var library = VoiceTrainingLibraryLoader.shared

    private var trainingRecommendation: VoiceTrainingRecommendation {
        VoiceLibraryMatcher.recommend(
            for: result,
            preference: preference,
            quality: quality,
            volumeStatistics: volumeStatistics,
            store: library.store
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PracticeSuggestionsSection(suggestions: trainingRecommendation.prioritySuggestions) { article in
                onSelectArticle(article)
            }

            Button {
                onBrowseLibrary()
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
        .task { await library.load() }
    }
}

private struct ScoreExplanationView: View {
    let result: PitcheeAnalysisResult
    let preference: VoicePreference

    init(result: PitcheeAnalysisResult, preference: VoicePreference = .undecided) {
        self.result = result
        self.preference = preference
    }

    private var directionScore: VoiceDirectionScore {
        preference.score(for: result)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                intro
                commonFormulaSection
                currentRuleSection
                otherRulesSection
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(preference.scoreExplanationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("scoring.explanation.intro.title")
                .font(.title2.weight(.bold))
            if preference == .undecided {
                Text("scoring.explanation.intro.description")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if preference != .undecided {
                Text(preference.scoreDirectionDescription)
                    .font(.subheadline)
                    .foregroundStyle(Color.pitcheeAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var commonFormulaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("scoring.baseFormula.title")
                .font(.title3.weight(.bold))
            Text("scoring.baseFormula.subtitle")
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
            if preference != .masculine {
                Text("scoring.baseFormula.note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var currentRuleSection: some View {
        let rule = currentRuleDocumentation

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("scoring.currentRule.title")
                    .font(.title3.weight(.bold))
                Text("scoring.currentRule.badge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.pitcheeAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.pitcheeAccent.opacity(0.12), in: Capsule())
            }
            Text(rule.guidance)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            ruleDetail(String(localized: "scoring.ruleDetail.condition"), text: rule.condition)
            ruleDetail(String(localized: "scoring.ruleDetail.formula"), text: nil)
            FormulaBlock(lines: rule.formulas)
            ruleDetail(String(localized: "scoring.ruleDetail.result"), text: rule.result)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ruleDocumentation.filter { $0.id != directionScore.rule }) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(rule.title)
                            .font(.subheadline.weight(.semibold))
                        Text(rule.condition)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(rule.result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)

                    if rule.id != ruleDocumentation.filter({ $0.id != directionScore.rule }).last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label("scoring.otherRules.title", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var currentRuleDocumentation: ScoreRuleDocumentation {
        ruleDocumentation.first { $0.id == directionScore.rule } ?? ruleDocumentation[0]
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
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.pitcheeAccent)
                .frame(width: 3)
                .padding(.vertical, 10)
        }
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
    ScoreRuleDocumentation(
        id: "continuous",
        title: String(localized: "scoring.rules.continuous.title"),
        guidance: String(localized: "scoring.rules.continuous.description"),
        condition: String(localized: "scoring.rules.continuous.condition"),
        formulas: [#"\mathrm{Final} = \mathrm{Base}"#],
        result: String(localized: "scoring.rules.continuous.result")
    ),
    ScoreRuleDocumentation(
        id: "pass_boost",
        title: String(localized: "scoring.rules.passBoost.title"),
        guidance: String(localized: "scoring.rules.passBoost.description"),
        condition: String(localized: "scoring.rules.passBoost.condition"),
        formulas: [
            #"s_F = \frac{F_0 - 165}{25}"#,
            #"s_N = \frac{\mathrm{Naturalness} - 80}{20}"#,
            #"s_S = \frac{\mathrm{Standard} - 50}{30}"#,
            #"\mathrm{strength} = \min(s_F, s_N, s_S, 1)"#,
            #"\mathrm{promoted} = 60 + 40 \times \mathrm{strength}"#,
            #"\mathrm{Final} = \max(\mathrm{Base}, \mathrm{promoted})"#
        ],
        result: String(localized: "scoring.rules.passBoost.result")
    ),
    ScoreRuleDocumentation(
        id: "high_f0_stylized_cap",
        title: String(localized: "scoring.rules.highF0StylizedCap.title"),
        guidance: String(localized: "scoring.rules.highF0StylizedCap.description"),
        condition: String(localized: "scoring.rules.highF0StylizedCap.condition"),
        formulas: [#"\mathrm{Final} = \min(\mathrm{Base}, 30)"#],
        result: String(localized: "scoring.rules.highF0StylizedCap.result")
    ),
    ScoreRuleDocumentation(
        id: "low_f0_natural_cap",
        title: String(localized: "scoring.rules.lowF0NaturalCap.title"),
        guidance: String(localized: "scoring.rules.lowF0NaturalCap.description"),
        condition: String(localized: "scoring.rules.lowF0NaturalCap.condition"),
        formulas: [#"\mathrm{Final} = \min(\mathrm{Base}, 59)"#],
        result: String(localized: "scoring.rules.lowF0NaturalCap.result")
    ),
    ScoreRuleDocumentation(
        id: "low_f0_stylized_cap",
        title: String(localized: "scoring.rules.lowF0StylizedCap.title"),
        guidance: String(localized: "scoring.rules.lowF0StylizedCap.description"),
        condition: String(localized: "scoring.rules.lowF0StylizedCap.condition"),
        formulas: [#"\mathrm{Final} = \min(\mathrm{Base}, 20)"#],
        result: String(localized: "scoring.rules.lowF0StylizedCap.result")
    ),
    ScoreRuleDocumentation(
        id: "high_f0_male_cap",
        title: String(localized: "scoring.rules.highF0MaleCap.title"),
        guidance: String(localized: "scoring.rules.highF0MaleCap.description"),
        condition: String(localized: "scoring.rules.highF0MaleCap.condition"),
        formulas: [#"\mathrm{Final} = \min(\mathrm{Base}, 59)"#],
        result: String(localized: "scoring.rules.highF0MaleCap.result")
    ),
    ScoreRuleDocumentation(
        id: "f0_unavailable",
        title: String(localized: "scoring.rules.f0Unavailable.title"),
        guidance: String(localized: "scoring.rules.f0Unavailable.description"),
        condition: String(localized: "scoring.rules.f0Unavailable.condition"),
        formulas: [#"\mathrm{Final} = \mathrm{Standard}"#],
        result: String(localized: "scoring.rules.f0Unavailable.result")
    )
]

private let masculineScoreRuleDocumentation: [ScoreRuleDocumentation] = [
    ScoreRuleDocumentation(
        id: "continuous",
        title: String(localized: "scoring.rules.continuous.title"),
        guidance: String(localized: "scoring.rules.continuous.description"),
        condition: String(localized: "scoring.rules.continuous.condition"),
        formulas: [
            #"d_{F_0} = \min(1, \max(-1, \frac{165 - F_0}{75}))"#,
            #"d_{VFP} = \min(1, \max(-1, \frac{50 - VFP}{50}))"#,
            #"\mathrm{Base} = \mathrm{Final} = \min(100, \max(0, 60 + 25d_{F_0} + 15d_{VFP}))"#
        ],
        result: String(localized: "scoring.rules.continuous.result")
    )
]

private func scoreRuleDocumentation(for preference: VoicePreference) -> [ScoreRuleDocumentation] {
    preference == .masculine ? masculineScoreRuleDocumentation : scoreRuleDocumentation
}

struct VoiceProfileReferenceChart: View {
    let femalePercentage: Double
    let meanPitchHz: Double?
    let pitchRangeHz: ClosedRange<Double>?
    // Backdrop-dependent glass flattens an ImageRenderer PDF into a bitmap.
    // Reports use static surfaces so text and paths remain directly drawable.
    var usesGlassEffects = true

    private let minimumDiameter: CGFloat = 78
    private let maximumDiameter: CGFloat = 150

    private var femaleValue: Double {
        guard femalePercentage.isFinite else { return 0 }
        return min(max(femalePercentage, 0), 100)
    }

    private var maleValue: Double { 100 - femaleValue }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            PitchGenderScale(
                meanHz: meanPitchHz,
                rangeHz: pitchRangeHz,
                usesGlassEffects: usesGlassEffects
            )
                .frame(width: 40)

            GeometryReader { proxy in
                let largestDiameter = max(minimumDiameter, min(maximumDiameter, proxy.size.width - minimumDiameter - 18))
                HStack(alignment: .center, spacing: 18) {
                    glassBubble(title: "analysis.voiceProfile.female.label", percentage: femaleValue, tint: Color.pink.opacity(0.12), maximumDiameter: largestDiameter)
                    glassBubble(title: "analysis.voiceProfile.male.label", percentage: maleValue, tint: Color.blue.opacity(0.10), maximumDiameter: largestDiameter)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: maximumDiameter)
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color.pink, Color.blue].map {
                    VoiceProfileGradientColor.make($0, opacity: 0.025, forPaper: !usesGlassEffects)
                },
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "analysis.voiceProfile.reference.a11y \(meanPitchText) \(pitchRangeText) \(percentageText(femaleValue)) \(percentageText(maleValue))"
        )
    }

    @ViewBuilder
    private func glassBubble(
        title: LocalizedStringKey,
        percentage: Double,
        tint: Color,
        maximumDiameter: CGFloat
    ) -> some View {
        let diameter = minimumDiameter + (maximumDiameter - minimumDiameter) * CGFloat(percentage / 100)

        let bubble = VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(percentageText(percentage))
                .font(.system(size: 25, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)

        if usesGlassEffects {
            bubble
                .modifier(GlassBubbleModifier(tint: tint))
                .shadow(color: tint.opacity(0.08), radius: 14, y: 8)
        } else {
            bubble
                .background(tint, in: Circle())
                .overlay {
                    Circle().stroke(tint.opacity(0.35), lineWidth: 1)
                }
        }
    }

    private func percentageText(_ percentage: Double) -> String {
        percentage.formatted(.percent.scale(1).precision(.fractionLength(0)))
    }

    private var meanPitchText: String {
        guard let meanPitchHz, meanPitchHz.isFinite else { return String(localized: "analysis.voiceProfile.noData") }
        return "\(meanPitchHz.formatted(.number.precision(.fractionLength(0)))) Hz"
    }

    private var pitchRangeText: String {
        guard let pitchRangeHz else { return String(localized: "analysis.voiceProfile.noData") }
        return "\(pitchRangeHz.lowerBound.formatted(.number.precision(.fractionLength(0))))–\(pitchRangeHz.upperBound.formatted(.number.precision(.fractionLength(0)))) Hz"
    }
}

private struct PitchGenderScale: View {
    let meanHz: Double?
    let rangeHz: ClosedRange<Double>?
    var usesGlassEffects = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let minimumHz = 50.0
    private let maximumHz = 350.0
    private let trackHeight: CGFloat = 180

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

    private func rangeFrame(in size: CGSize, range: ClosedRange<CGFloat>) -> CGRect {
        let top = (1 - range.upperBound) * size.height
        let bottom = (1 - range.lowerBound) * size.height
        // A narrow or clipped range keeps a visible lens, centered on the real range.
        let height = min(size.height, max(8, bottom - top))
        let originY = min(max(0, (top + bottom - height) / 2), size.height - height)
        return CGRect(x: (size.width - 30) / 2, y: originY, width: 30, height: height)
    }

    var body: some View {
        VStack(spacing: 7) {
            Text("analysis.pitchScale.maxLabel")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    // Keep the upper band neutral, then blend into the female tint near 300 Hz.
                                    .init(color: gradientColor(.primary, opacity: 0.045), location: 0),
                                    .init(color: gradientColor(.primary, opacity: 0.045), location: 0.08),
                                    .init(color: gradientColor(.pink, opacity: 0.07), location: 0.15),
                                    .init(color: gradientColor(.pink, opacity: 0.16), location: 0.22),
                                    .init(color: gradientColor(.primary, opacity: 0.04), location: 0.58),
                                    .init(color: gradientColor(.blue, opacity: 0.14), location: 1)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 18, height: proxy.size.height)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    if let normalizedRange {
                        let frame = rangeFrame(in: proxy.size, range: normalizedRange)
                        Color.clear
                            .frame(width: frame.width, height: frame.height)
                            .modifier(GlassRangeModifier(usesGlassEffects: usesGlassEffects))
                            // Move the finished glass surface, not only its content.
                            .position(x: frame.midX, y: frame.midY)
                    }

                    if let normalizedValue {
                        let markerY = min(max(1, (1 - normalizedValue) * proxy.size.height), proxy.size.height - 1)

                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.80))
                            .frame(width: 20, height: 2)
                            .position(x: proxy.size.width / 2, y: markerY)

                        Text("analysis.pitchScale.averageMarker")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.7)
                            .fixedSize()
                            .position(x: -7, y: markerY)
                            .zIndex(2)
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: normalizedRange)
                .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: normalizedValue)
            }
            .frame(height: trackHeight)

            Text("analysis.pitchScale.minLabel")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityHidden(true)
    }

    private func gradientColor(_ color: Color, opacity: Double) -> Color {
        VoiceProfileGradientColor.make(color, opacity: opacity, forPaper: !usesGlassEffects)
    }
}

private enum VoiceProfileGradientColor {
    static func make(_ color: Color, opacity: Double, forPaper: Bool) -> Color {
        guard forPaper else { return color.opacity(opacity) }
        // PDF shading can discard alpha on individual gradient stops. Blend
        // onto the report's white paper first, keeping the gradient opaque.
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        let coverage = CGFloat(opacity) * alpha
        return Color(
            .sRGB,
            red: Double(1 - (1 - red) * coverage),
            green: Double(1 - (1 - green) * coverage),
            blue: Double(1 - (1 - blue) * coverage)
        )
    }
}

private struct GlassRangeModifier: ViewModifier {
    var usesGlassEffects = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

        if !usesGlassEffects {
            content
                .background(Color.primary.opacity(0.045), in: shape)
                .overlay {
                    shape.strokeBorder(.primary.opacity(0.18), lineWidth: 0.75)
                }
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.75)
                }
        } else {
            content
                .background(.thinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(.primary.opacity(0.18), lineWidth: 0.75)
                }
        }
    }
}

private struct GlassBubbleModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint), in: Circle())
        } else {
            content
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(tint.opacity(0.35), lineWidth: 1)
                }
        }
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
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 2... : 1...)
                .fixedSize(horizontal: false, vertical: compact)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 5) { number; suffix }
                VStack(alignment: .leading, spacing: 4) { number; suffix }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 16)
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
    NavigationStack { ScoreExplanationView(result: DebugPreviewData.result) }
}
#endif
