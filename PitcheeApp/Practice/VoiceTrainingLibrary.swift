//
//  VoiceTrainingLibrary.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/4.
//

import SwiftUI
import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(LaTeXSwiftUI)
import LaTeXSwiftUI
#endif

enum LibraryTheme {
    static var accent: Color {
        #if os(iOS)
        Color.pitcheeAccent
        #else
        Color.accentColor
        #endif
    }
}

/// Structured model for an article in the Pitchee Voice Training Library.
nonisolated struct VoiceArticle: Identifiable, Codable, Sendable, Hashable {
    nonisolated struct Section: Identifiable, Codable, Sendable, Hashable {
        var id: String { heading }
        let heading: String
        let icon: String?
        let body: String

        init(heading: String, icon: String? = nil, body: String) {
            self.heading = heading
            self.icon = icon
            self.body = body
        }

        var iconName: String {
            if let icon, !icon.isEmpty {
                return icon
            }
            return "doc.text.fill"
        }

        @MainActor var tintColor: Color {
            switch iconName {
            case "gearshape.2.fill":
                return LibraryTheme.accent
            case "stethoscope":
                return .orange
            case "figure.run":
                return .green
            case "books.vertical.fill":
                return .indigo
            default:
                return LibraryTheme.accent
            }
        }
    }

    let id: String
    let language: String
    let title: String
    let category: String
    let filename: String
    let summary: String
    let userPersona: String
    let coreGoal: String
    let targetPreferences: [String]
    let sections: [Section]
    let rawContent: String

    /// Use the published source path, including its language, for reading and sharing.
    var webURL: URL {
        URL(string: "https://github.com/project-pitchee/Articles/blob/4f7af0023a85c773fda0dd0485ca6b0d58b8c062/")!
            .appendingPathComponent(filename)
    }

    var categoryDisplayTitle: String {
        switch category {
        case "rules":
            return String(localized: "voiceLibrary.category.engineRules", defaultValue: "算法规则判定")
        case "timbre":
            return String(localized: "voiceLibrary.category.timbre", defaultValue: "音色专项")
        case "naturalness":
            return String(localized: "voiceLibrary.category.naturalness", defaultValue: "自然度专项")
        case "pitch":
            return String(localized: "voiceLibrary.category.pitch", defaultValue: "基频专项")
        default:
            return category
        }
    }

    var iconName: String {
        switch category {
        case "timbre": "slider.horizontal.3"
        case "naturalness": "leaf.fill"
        case "pitch": "waveform"
        default: "chart.line.uptrend.xyaxis"
        }
    }

    @MainActor var themeColor: Color {
        category == "naturalness" ? .green : LibraryTheme.accent
    }

    var readingTimeMinutes: Int {
        max(1, (rawContent.count / 350))
    }
}

/// One actionable next step, with optional supporting material from the library.
/// Capture problems may not have a suitable article and must still be explainable.
nonisolated struct VoiceTrainingSuggestion: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let article: VoiceArticle?
}

/// A collection of recommendations tailored to an analysis result.
nonisolated struct VoiceTrainingRecommendation: Sendable {
    let prioritySuggestions: [VoiceTrainingSuggestion]
    let primaryArticle: VoiceArticle?
    let secondaryArticles: [VoiceArticle]
    let acousticAlertArticles: [VoiceArticle]
    let deepDiveArticles: [VoiceArticle]
    let matchedRule: String

    init(
        primaryArticle: VoiceArticle?,
        secondaryArticles: [VoiceArticle],
        acousticAlertArticles: [VoiceArticle] = [],
        deepDiveArticles: [VoiceArticle],
        matchedRule: String,
        prioritySuggestions: [VoiceTrainingSuggestion] = []
    ) {
        self.primaryArticle = primaryArticle
        self.secondaryArticles = secondaryArticles
        self.acousticAlertArticles = acousticAlertArticles
        self.deepDiveArticles = deepDiveArticles
        self.matchedRule = matchedRule
        self.prioritySuggestions = prioritySuggestions
    }

    var combinedArticles: [VoiceArticle] {
        var result: [VoiceArticle] = []
        if let primaryArticle {
            result.append(primaryArticle)
        }
        for article in acousticAlertArticles where !result.contains(where: { $0.id == article.id }) {
            result.append(article)
        }
        for article in secondaryArticles where !result.contains(where: { $0.id == article.id }) {
            result.append(article)
        }
        for article in deepDiveArticles where !result.contains(where: { $0.id == article.id }) {
            result.append(article)
        }
        return result
    }
}

/// Storage and access layer for the Voice Training Library.
nonisolated final class VoiceTrainingLibraryStore: Sendable {
    /// Empty data is safe for advice while the library is loading. It performs no I/O.
    static let empty = VoiceTrainingLibraryStore()

    nonisolated struct Category: Identifiable, Sendable {
        let id: String
        let articles: [VoiceArticle]

        // Keep localization at the point of use. The immutable index contains
        // article data, never a title captured in the launch-time language.
        var title: String { articles.first?.categoryDisplayTitle ?? id }
    }

    nonisolated private struct Container: Codable {
        let schemaVersion: String
        let totalArticles: Int
        let articles: [VoiceArticle]
    }

    let articles: [VoiceArticle]
    let categories: [Category]
    private let articleMap: [String: VoiceArticle]
    private let categoryMap: [String: Category]
    private let matchingMatrix: [String: [String]]

    enum LoadError: Error, LocalizedError, Sendable {
        case missingResource(String)
        case invalidResource(String, String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name): "Missing bundled voice library resource: \(name).json"
            case .invalidResource(let name, let reason): "Invalid voice library resource \(name): \(reason)"
            }
        }
    }

    /// Bundle lookup, file reads, decoding and indexing all run outside the UI actor.
    /// Tests can explicitly supply a resource directory instead of relying on a source path.
    static func load(bundle: Bundle = .main, preferredLanguages: [String] = Locale.preferredLanguages) async throws -> VoiceTrainingLibraryStore {
        try await Task.detached(priority: .utility) {
            let libraryURL = try resourceURL(named: "voice-training-library", in: bundle)
            let matrixURL = try resourceURL(named: "voice-rule-matching-matrix", in: bundle)
            return try read(libraryURL: libraryURL, matrixURL: matrixURL, preferredLanguages: preferredLanguages)
        }.value
    }

    static func load(directory: URL, preferredLanguages: [String] = Locale.preferredLanguages) async throws -> VoiceTrainingLibraryStore {
        try await Task.detached(priority: .utility) {
            try read(
                libraryURL: directory.appendingPathComponent("voice-training-library.json"),
                matrixURL: directory.appendingPathComponent("voice-rule-matching-matrix.json"),
                preferredLanguages: preferredLanguages
            )
        }.value
    }

    private static func resourceURL(named name: String, in bundle: Bundle) throws -> URL {
        for subdirectory in [nil, "VoiceTrainingLibrary", "Resources/VoiceTrainingLibrary"] as [String?] {
            if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory) {
                return url
            }
        }
        throw LoadError.missingResource(name)
    }

    private static func read(libraryURL: URL, matrixURL: URL, preferredLanguages: [String]) throws -> VoiceTrainingLibraryStore {
        func readData(at url: URL) throws -> Data {
            do { return try Data(contentsOf: url) }
            catch { throw LoadError.invalidResource(url.lastPathComponent, error.localizedDescription) }
        }
        return try VoiceTrainingLibraryStore(
            libraryData: readData(at: libraryURL), matrixData: readData(at: matrixURL),
            preferredLanguages: preferredLanguages
        )
    }

    init(libraryData: Data, matrixData: Data, preferredLanguages: [String] = Locale.preferredLanguages) throws {
        let container: Container
        let matrix: [String: [String]]
        do {
            container = try JSONDecoder().decode(Container.self, from: libraryData)
            matrix = try JSONDecoder().decode([String: [String]].self, from: matrixData)
        } catch {
            throw LoadError.invalidResource("JSON", error.localizedDescription)
        }
        guard container.schemaVersion == "2.0.0", !container.articles.isEmpty,
              container.totalArticles == container.articles.count else {
            throw LoadError.invalidResource("voice-training-library", "Unsupported schema or article count")
        }
        let translations = Dictionary(grouping: container.articles, by: \.language)
        let ids = Set((translations["en"] ?? []).map(\.id))
        guard Set(translations.keys) == ["en", "zh_cn"],
              translations.values.allSatisfy({ $0.count == ids.count && Set($0.map(\.id)) == ids }),
              container.articles.allSatisfy({ article in
                  let parts = article.id.split(separator: "/")
                  return parts.count == 2 && ["practice", "rules"].contains(String(parts[0]))
                      && article.filename == "\(parts[0])/\(article.language)/\(parts[1]).md"
                      && !article.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !article.rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !article.sections.isEmpty
                      && Set(article.sections.map(\.heading)).count == article.sections.count
                      && article.sections.allSatisfy {
                          !$0.heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      }
                      && !article.targetPreferences.isEmpty
                      && Set(article.targetPreferences).isSubset(of: ["feminine", "masculine", "undecided"])
              }) else {
            throw LoadError.invalidResource("voice-training-library", "Missing content, invalid paths or incomplete language pairs")
        }
        let requiredKeys: Set<String> = [
            "pass_boost", "high_f0_stylized_cap", "high_f0_male_cap", "low_f0_natural_cap",
            "low_f0_stylized_cap", "continuous_below_pass", "continuous_pass", "f0_unavailable",
            "timbre", "naturalness", "low_pitch"
        ]
        guard Set(matrix.keys) == requiredKeys, matrix.allSatisfy({ key, values in
            key == "f0_unavailable" ? values.isEmpty : values.count == 1 && values.allSatisfy(ids.contains)
        }) else {
            throw LoadError.invalidResource("voice-rule-matching-matrix", "Empty rules or unknown article IDs")
        }
        let language = preferredLanguages.compactMap { preference -> String? in
            switch preference.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first {
            case "zh": "zh_cn"
            case "en": "en"
            default: nil
            }
        }.first ?? "en"
        self.articles = translations[language] ?? []
        self.matchingMatrix = matrix
        self.articleMap = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        let groups = Dictionary(grouping: articles, by: \.category)
        self.categories = groups.keys.sorted().map { Category(id: $0, articles: groups[$0] ?? []) }
        self.categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    private init() {
        self.articles = []
        self.articleMap = [:]
        self.categories = []
        self.categoryMap = [:]
        self.matchingMatrix = [:]
    }

    func article(for id: String) -> VoiceArticle? {
        articleMap[id]
    }

    func article(matching key: String) -> VoiceArticle? {
        matchingMatrix[key]?.first.flatMap { articleMap[$0] }
    }

    func article(linkedBy url: URL, from article: VoiceArticle) -> VoiceArticle? {
        guard let resolved = URL(string: url.relativeString, relativeTo: article.webURL)?.absoluteURL else { return nil }
        return articles.first { $0.webURL == resolved }
    }

    func articles(inCategory categoryPrefix: String) -> [VoiceArticle] {
        if let category = categoryMap[categoryPrefix] { return category.articles }
        return articles.filter { $0.category.hasPrefix(categoryPrefix) }
    }

    func categories(matching query: String, category: String? = nil) -> [Category] {
        let candidates: [Category]
        if let category, !category.isEmpty {
            candidates = categoryMap[category].map { [$0] } ?? []
        } else {
            candidates = categories
        }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return candidates }
        let matches = Dictionary(grouping: search(query: query, category: category), by: \.category)
        return candidates.compactMap { category in
            matches[category.id].map { Category(id: category.id, articles: $0) }
        }
    }

    func search(query: String, category: String? = nil, preference: VoicePreference? = nil) -> [VoiceArticle] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates: [VoiceArticle]
        if let category, !category.isEmpty {
            candidates = categoryMap[category]?.articles ?? []
        } else {
            candidates = articles
        }
        guard !trimmed.isEmpty || preference != nil else { return candidates }
        let targetKey = preference?.rawValue
        return candidates.filter { article in
            if let targetKey, !article.targetPreferences.contains(targetKey) { return false }
            if trimmed.isEmpty {
                return true
            }
            return article.title.localizedCaseInsensitiveContains(trimmed)
                || article.summary.localizedCaseInsensitiveContains(trimmed)
                || article.coreGoal.localizedCaseInsensitiveContains(trimmed)
                || article.id.localizedCaseInsensitiveContains(trimmed)
                || article.rawContent.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// Shares one asynchronous load across browsing and result views. The immutable
/// snapshot can also be passed to the nonisolated recommendation engine.
@MainActor
final class VoiceTrainingLibraryLoader: ObservableObject {
    static let shared = VoiceTrainingLibraryLoader()

    @Published private(set) var store = VoiceTrainingLibraryStore.empty
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var hasLoaded = false
    private var loadingTask: Task<Void, Never>?
    private let loadStore: @Sendable () async throws -> VoiceTrainingLibraryStore

    init(loadStore: @escaping @Sendable () async throws -> VoiceTrainingLibraryStore = {
        try await VoiceTrainingLibraryStore.load()
    }) {
        self.loadStore = loadStore
    }

    func load() async {
        guard !hasLoaded else { return }
        if let loadingTask {
            await loadingTask.value
            return
        }
        isLoading = true
        error = nil
        let task = Task {
            defer {
                isLoading = false
                loadingTask = nil
            }
            do {
                store = try await loadStore()
                hasLoaded = true
            } catch {
                self.error = error.localizedDescription
            }
        }
        loadingTask = task
        await task.value
    }

}

/// Loading and resource failures are distinct from a search with no matches.
struct VoiceTrainingLibraryLoadStatusView: View {
    @ObservedObject var loader: VoiceTrainingLibraryLoader

    var body: some View {
        if loader.error != nil {
            ContentUnavailableView {
                Label("voiceLibrary.load.errorTitle", systemImage: "book.closed")
            } description: {
                Text("common.error.tryAgainLater")
            } actions: {
                Button("voiceLibrary.load.retry") { Task { await loader.load() } }
                    .buttonStyle(.bordered)
            }
        } else {
            ProgressView("voiceLibrary.title")
        }
    }
}

/// Chooses at most two useful next steps. Capture reliability comes before
/// acoustic interpretation, and an uncertain goal never inherits a binary rule.
nonisolated enum VoiceLibraryMatcher {
    static func recommend(
        for result: PitcheeAnalysisResult,
        preference: VoicePreference,
        quality: RecordingQuality? = nil,
        volumeStatistics: RecordingVolumeStatistics? = nil,
        store: VoiceTrainingLibraryStore = .empty
    ) -> VoiceTrainingRecommendation {
        if let capture = captureRecommendation(
            for: result, quality: quality, volumeStatistics: volumeStatistics, store: store
        ) {
            return capture
        }

        guard hasUsablePitch(result), let pitch = result.f0.meanHz else {
            return recommendation([suggestion(.pitchUnavailable, store: store)], rule: "f0_unavailable")
        }
        let directionScore = preference.score(for: result)
        guard hasUsableScores(result), directionScore.finalScore.isFinite,
              (0...100).contains(directionScore.finalScore) else {
            return recommendation([suggestion(.analysisUnavailable, store: store)], rule: "analysis_unavailable")
        }

        if preference != .feminine {
            if result.naturalness.score < 50 {
                return recommendation([
                    suggestion(.comfortableVoice, articleKey: "naturalness", preference: preference, store: store),
                    suggestion(.listen, store: store)
                ], rule: preference == .undecided ? "nonbinary_exploration" : directionScore.rule)
            }
            let content: SuggestionContent = preference == .undecided ? .explore
                : pitch < 85 ? .masculineComfort : .masculineBasics
            return recommendation([
                suggestion(content, store: store), suggestion(.listen, store: store)
            ], rule: preference == .undecided ? "nonbinary_exploration" : directionScore.rule)
        }

        let key = directionScore.rule == "continuous"
            ? (directionScore.finalScore < 60 ? "continuous_below_pass" : "continuous_pass")
            : directionScore.rule
        guard let guidance = ruleGuidance[key] else {
            return recommendation([
                suggestion(.oneElement, store: store), suggestion(.listen, store: store)
            ], rule: directionScore.rule)
        }
        var candidates = [suggestion(
            guidance.content, articleKey: key, id: "rule.\(key)", preference: preference, store: store
        )]
        let values = ["timbre": directionScore.standardScore, "naturalness": result.naturalness.score, "low_pitch": pitch]
        let keys = directionScore.rule == "continuous" ? guidance.practice.sorted {
            let left = values[$0] ?? .infinity
            let right = values[$1] ?? .infinity
            return left == right ? $0 == "timbre" : left < right
        } : guidance.practice
        for metric in keys {
            guard let mapping = metricGuidance[metric], let value = values[metric],
                  mapping.range.contains(value) else { continue }
            candidates.append(suggestion(mapping.content, articleKey: metric, preference: preference, store: store))
        }
        candidates.append(suggestion(.listen, store: store))
        return recommendation(candidates, rule: directionScore.rule)
    }

    // The source articles prescribe these next steps; a cap's explanation stays visible alongside practice.
    private static let ruleGuidance: [String: (content: SuggestionContent, practice: [String])] = [
        "continuous_below_pass": (.oneElement, ["timbre", "naturalness"]),
        "continuous_pass": (.dailySpeech, ["timbre", "naturalness"]),
        "pass_boost": (.dailySpeech, []),
        "high_f0_stylized_cap": (.comfortableVoice, ["naturalness"]),
        "low_f0_natural_cap": (.pitchGlide, ["low_pitch"]),
        "low_f0_stylized_cap": (.comfortableVoice, ["naturalness"]),
        "high_f0_male_cap": (.resonance, ["timbre"])
    ]

    private static let metricGuidance: [String: (range: ClosedRange<Double>, content: SuggestionContent)] = [
        "timbre": (0...100, .resonance),
        "naturalness": (0...80, .comfortableVoice),
        "low_pitch": (0...165, .pitchGlide)
    ]

    /// Score-only callers receive listening guidance, without a claim that a
    /// numerical change establishes improvement or successful motor learning.
    static func recommendForPractice(
        scoreA: Double,
        scoreB: Double,
        feedback: PracticeFeedback? = nil,
        store: VoiceTrainingLibraryStore = .empty
    ) -> VoiceTrainingRecommendation {
        guard scoreA.isFinite, scoreB.isFinite,
              (0...100).contains(scoreA), (0...100).contains(scoreB) else {
            return recommendation([suggestion(.analysisUnavailable, store: store)], rule: "analysis_unavailable")
        }
        let first: VoiceTrainingSuggestion
        if feedback == .unsure {
            first = suggestion(.listen, store: store)
        } else if scoreB < scoreA {
            first = suggestion(.compareDrop, store: store)
        } else {
            first = suggestion(.compare, store: store)
        }
        return recommendation([first], rule: "guided_practice_comparison")
    }

    static func recommendForPractice(
        resultA: PitcheeAnalysisResult,
        resultB: PitcheeAnalysisResult,
        preference: VoicePreference = .feminine,
        qualityA: RecordingQuality? = nil,
        qualityB: RecordingQuality? = nil,
        feedback: PracticeFeedback? = nil,
        store: VoiceTrainingLibraryStore = .empty
    ) -> VoiceTrainingRecommendation {
        for (result, quality) in [(resultA, qualityA), (resultB, qualityB)] {
            if let capture = captureRecommendation(for: result, quality: quality, volumeStatistics: nil, store: store) {
                return capture
            }
            guard hasUsableScores(result), hasUsablePitch(result) else {
                return recommendation([suggestion(.analysisUnavailable, store: store)], rule: "analysis_unavailable")
            }
        }
        // The model and scoring profile affect comparability. The caller still
        // owns passage/session checks, which are unavailable on a bare result.
        guard resultA.schemaVersion == resultB.schemaVersion,
              resultA.modelVersion == resultB.modelVersion,
              resultA.scoreProfile == resultB.scoreProfile else {
            return recommendation([suggestion(.compareConditions, store: store)], rule: "comparison_unavailable")
        }
        if preference == .undecided {
            return recommendation([
                suggestion(.listen, preference: preference, store: store)
            ], rule: "guided_practice_comparison")
        }
        return recommendForPractice(
            scoreA: preference.score(for: resultA).finalScore,
            scoreB: preference.score(for: resultB).finalScore,
            feedback: feedback,
            store: store
        )
    }

    private static func hasUsableScores(_ result: PitcheeAnalysisResult) -> Bool {
        result.vfp.windowCount > 0 && result.naturalness.windowCount > 0
            && result.vfp.vfpStandardScore.isFinite && (0...100).contains(result.vfp.vfpStandardScore)
            && result.naturalness.score.isFinite && (0...100).contains(result.naturalness.score)
    }

    private static func hasUsablePitch(_ result: PitcheeAnalysisResult) -> Bool {
        guard let pitch = result.f0.meanHz, pitch.isFinite, pitch > 0,
              result.f0.voicedFrameCount > 0, result.f0.voicedWindowCount > 0,
              result.f0.windowSeconds.isFinite, result.f0.windowSeconds > 0 else { return false }
        // A capture may contain enough speech but only a momentary pitch
        // detection. Require at least one second of voiced windows before
        // prescribing a pitch direction; this is a conservative UI heuristic.
        return Double(result.f0.voicedWindowCount) * result.f0.windowSeconds >= 1
    }

    private static func captureRecommendation(
        for result: PitcheeAnalysisResult,
        quality: RecordingQuality?,
        volumeStatistics: RecordingVolumeStatistics?,
        store: VoiceTrainingLibraryStore
    ) -> VoiceTrainingRecommendation? {
        let effectiveQuality = quality ?? RecordingQuality(
            speechSeconds: result.vad.speechSeconds,
            speechDBFS: volumeStatistics?.medianDBFS,
            backgroundDBFS: volumeStatistics?.measuredBackgroundDBFS,
            clippedFraction: volumeStatistics?.clippedSampleFraction
        )
        var issues = Set(effectiveQuality.issues)
        // Persisted quality can be valid without loading the audio again. When
        // new measurements are supplied, do not discard their failure signals.
        if quality != nil, let volumeStatistics {
            let measured = RecordingQuality(
                speechSeconds: result.vad.speechSeconds,
                speechDBFS: volumeStatistics.medianDBFS,
                backgroundDBFS: volumeStatistics.measuredBackgroundDBFS,
                clippedFraction: volumeStatistics.clippedSampleFraction
            )
            issues.formUnion(measured.issues)
        }
        if !result.vad.speechSeconds.isFinite || result.vad.speechSeconds < 5 {
            issues.insert(.shortSpeech)
        }
        if effectiveQuality.version != RecordingQuality.rulesVersion {
            issues.insert(.unavailable)
        }
        guard !issues.isEmpty else { return nil }

        var suggestions: [VoiceTrainingSuggestion] = []
        if issues.contains(.clipping) {
            suggestions.append(suggestion(.captureClipping, store: store))
        }
        if issues.contains(.lowLevel) || issues.contains(.background) {
            suggestions.append(suggestion(.captureEnvironment, store: store))
        }
        if issues.contains(.shortSpeech) {
            // Ending a recording early does not establish a breathing problem.
            suggestions.append(suggestion(.captureDuration, store: store))
        }
        if suggestions.isEmpty {
            suggestions.append(suggestion(.captureUnavailable, store: store))
        }
        return recommendation(suggestions, rule: "recording_quality")
    }

    private static func recommendation(_ candidates: [VoiceTrainingSuggestion], rule: String) -> VoiceTrainingRecommendation {
        var seenSuggestions = Set<String>()
        var seenArticles = Set<String>()
        let suggestions = Array(candidates.filter { seenSuggestions.insert($0.id).inserted }.prefix(2))
        let articles = suggestions.compactMap(\.article).filter { seenArticles.insert($0.id).inserted }
        return VoiceTrainingRecommendation(
            primaryArticle: articles.first,
            secondaryArticles: Array(articles.dropFirst()),
            deepDiveArticles: [],
            matchedRule: rule,
            prioritySuggestions: suggestions
        )
    }

    private static func suggestion(
        _ content: SuggestionContent,
        articleKey: String? = nil,
        id: String? = nil,
        preference: VoicePreference? = nil,
        store: VoiceTrainingLibraryStore
    ) -> VoiceTrainingSuggestion {
        let article = articleKey.flatMap { store.article(matching: $0) }.flatMap { article in
            guard preference.map({ article.targetPreferences.contains($0.rawValue) }) ?? true else { return nil as VoiceArticle? }
            return article
        }
        return VoiceTrainingSuggestion(id: id ?? content.rawValue, title: content.title, detail: content.detail, article: article)
    }

    private enum SuggestionContent: String {
        case captureClipping, captureEnvironment, captureDuration, captureUnavailable
        case pitchUnavailable, analysisUnavailable, comfortableVoice, explore
        case masculineComfort, masculineBasics, pitchComfort, pitchGlide, resonance
        case oneElement, dailySpeech, listen, compareDrop, compare, compareConditions

        var title: String {
            switch self {
            case .captureClipping: String(localized: "practice.suggestion.captureClipping.title", defaultValue: "先消除录音失真")
            case .captureEnvironment: String(localized: "practice.suggestion.captureEnvironment.title", defaultValue: "先调整录音环境")
            case .captureDuration: String(localized: "practice.suggestion.captureDuration.title", defaultValue: "补录一段完整语音")
            case .captureUnavailable: String(localized: "practice.suggestion.captureUnavailable.title", defaultValue: "先确认录音质量")
            case .pitchUnavailable: String(localized: "practice.suggestion.pitchUnavailable.title", defaultValue: "先获得清晰的音高记录")
            case .analysisUnavailable: String(localized: "practice.suggestion.analysisUnavailable.title", defaultValue: "重新获取完整分析")
            case .comfortableVoice: String(localized: "practice.suggestion.comfortableVoice.title", defaultValue: "先回听，再决定是否调整")
            case .explore: String(localized: "practice.suggestion.explore.title", defaultValue: "探索你喜欢的声音")
            case .masculineComfort: String(localized: "practice.suggestion.masculineComfort.title", defaultValue: "保持舒适，避免用力压低")
            case .masculineBasics: String(localized: "practice.suggestion.masculineBasics.title", defaultValue: "从舒适的共鸣变化开始")
            case .pitchComfort: String(localized: "practice.suggestion.pitchComfort.title", defaultValue: "优先找到舒适音区")
            case .pitchGlide: String(localized: "practice.suggestion.pitchGlide.title", defaultValue: "轻柔探索音高变化")
            case .resonance: String(localized: "practice.suggestion.resonance.title", defaultValue: "先核对音色分与听感")
            case .oneElement: String(localized: "practice.suggestion.oneElement.title", defaultValue: "每次只练一个声音要素")
            case .dailySpeech: String(localized: "practice.suggestion.dailySpeech.title", defaultValue: "把练习带入日常表达")
            case .listen: String(localized: "practice.suggestion.sameSentence.title", defaultValue: "用同一句话听辨变化")
            case .compareDrop: String(localized: "practice.suggestion.compareDrop.title", defaultValue: "先听一听分数变化之外的声音")
            case .compare: String(localized: "practice.suggestion.compare.title", defaultValue: "把分数与听感一起比较")
            case .compareConditions: String(localized: "practice.suggestion.compareConditions.title", defaultValue: "在相同条件下重新比较")
            }
        }

        var detail: String {
            switch self {
            case .captureClipping: String(localized: "practice.suggestion.captureClipping.detail", defaultValue: "录音检查提示可能存在削波。可以稍微拉开麦克风距离，或降低输入增益，用平常音量重录后再选择训练重点。")
            case .captureEnvironment: String(localized: "practice.suggestion.captureEnvironment.detail", defaultValue: "录音检查提示输入偏轻或背景声可能影响结果。可以换到安静位置，保持稳定的麦克风距离后重录，无需刻意提高音量。")
            case .captureDuration: String(localized: "practice.suggestion.captureDuration.detail", defaultValue: "以自然语速读完一段话，保留至少 5 秒有效语音后再分析。")
            case .captureUnavailable: String(localized: "practice.suggestion.captureUnavailable.detail", defaultValue: "这次缺少录音质量信息。重新录一段清晰语音，再选择练习重点。")
            case .pitchUnavailable: String(localized: "practice.suggestion.pitchUnavailable.detail", defaultValue: "音高数据不足。用舒适的声音读一段话后重试。")
            case .analysisUnavailable: String(localized: "practice.suggestion.analysisUnavailable.detail", defaultValue: "部分分析数据不可用，请重新录制并分析。")
            case .comfortableVoice: String(localized: "practice.suggestion.comfortableVoice.detail", defaultValue: "这次自然分偏低，但模型可能误判，不能定位原因或判断嗓音健康。先回听是否符合目标；若建议不合适，可以跳过。若想再试一段，可用舒适音高说几句，暂时不追求更高或更低；如有不适就停下休息。")
            case .explore: String(localized: "practice.suggestion.explore.detail", defaultValue: "选择喜欢的音色或表达方式，一次试一个小变化，以舒适度和喜好为准。")
            case .masculineComfort: String(localized: "practice.suggestion.masculineComfort.detail", defaultValue: "这次音高已经较低。保持轻松清晰，先探索共鸣，无需继续压低。")
            case .masculineBasics: String(localized: "practice.suggestion.masculineBasics.detail", defaultValue: "保持舒适音高，用短句探索更沉稳的共鸣，避免压喉或强行降调。")
            case .pitchComfort: String(localized: "practice.suggestion.pitchComfort.detail", defaultValue: "这次平均音高较高。用更轻松的音区说同一句话，比较舒适度与听感。")
            case .pitchGlide: String(localized: "practice.suggestion.pitchGlide.detail", defaultValue: "如果你也想探索音高变化，可以在舒适范围内做小幅、轻柔的滑音，再带回一句短话，无需达到固定频率。若这项建议不符合你的目标或听感，可以跳过。")
            case .resonance: String(localized: "practice.suggestion.resonance.detail", defaultValue: "音色分（VFP）可能误判，低分不代表共鸣有问题。先回听是否符合你的目标；若分数与听感不符，可以跳过这项建议。只有你也希望改变音色时，再尝试小幅变化。")
            case .oneElement: String(localized: "practice.suggestion.oneElement.detail", defaultValue: "从音高、共鸣或表达中选一项短练，用同一句话检查变化。")
            case .dailySpeech: String(localized: "practice.suggestion.dailySpeech.detail", defaultValue: "把熟悉的练习短句换成日常表达，保持轻松，再逐渐延长。")
            case .listen: String(localized: "practice.suggestion.listen.detail", defaultValue: "用同一句话、相近语速和麦克风距离复测，回听一个变化。")
            case .compareDrop: String(localized: "practice.suggestion.compareDrop.detail", defaultValue: "一次分数下降不能确定进退步。先回听，再在相同条件下复测。")
            case .compare: String(localized: "practice.suggestion.compare.detail", defaultValue: "结合舒适度、目标听感与分数回听，在相同条件下重复比较。")
            case .compareConditions: String(localized: "practice.suggestion.compareConditions.detail", defaultValue: "两次分析的模型或设置不同。请使用相同目标、语句和条件重新比较。")
            }
        }
    }
}

// MARK: - SwiftUI Views for Article Reading and Browsing

/// Sheet presentation for a voice training article.
struct VoiceArticleDetailView: View {
    let article: VoiceArticle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VoiceArticleContentView(article: article)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Label(String(localized: "common.action.close", defaultValue: "关闭"), systemImage: "xmark")
                        }
                        .accessibilityIdentifier("voiceLibrary.closeArticle")
                    }
                }
        }
    }
}

/// Reader content that participates in its caller's navigation stack.
struct VoiceArticleContentView: View {
    let article: VoiceArticle
    @ObservedObject private var library = VoiceTrainingLibraryLoader.shared
    @State private var linkedArticle: VoiceArticle?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                articleHeader
                if isUserPersonaDisplayable || !article.coreGoal.isEmpty {
                    contextSection
                }
                sectionsList
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .navigationTitle(article.categoryDisplayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $linkedArticle) { article in
            VoiceArticleContentView(article: article)
        }
        .task { await library.load() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Link(destination: article.webURL) {
                    Label(String(localized: "voiceLibrary.action.openInBrowser", defaultValue: "在浏览器中打开"), systemImage: "safari")
                }
                .accessibilityIdentifier("voiceLibrary.openArticleInBrowser")

                ShareLink(item: article.webURL, subject: Text(article.title), preview: SharePreview(article.title)) {
                    Label(String(localized: "voiceLibrary.action.share", defaultValue: "分享文章"), systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("voiceLibrary.shareArticle")
            }
        }
    }

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(article.categoryDisplayTitle, systemImage: article.iconName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(article.themeColor)

            Text(article.title)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Label {
                Text(String(localized: "voiceLibrary.article.readingTime", defaultValue: "约 \(article.readingTimeMinutes) 分钟阅读"))
            } icon: {
                Image(systemName: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

        }
    }

    private var isUserPersonaDisplayable: Bool {
        let trimmed = article.userPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let nonPersonaKeywords = ["TruVox", "http://", "https://", "www.", "\\mathrm", "公式", "论文", "算法契约", "物理现象"]
        return !nonPersonaKeywords.contains(where: { trimmed.contains($0) })
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isUserPersonaDisplayable {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.orange)
                        .font(.body)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "voiceLibrary.article.context", defaultValue: "适用情况"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(article.userPersona)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            if !article.coreGoal.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "target")
                        .foregroundStyle(LibraryTheme.accent)
                        .font(.body)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "voiceLibrary.article.goal", defaultValue: "核心训练目标"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(article.coreGoal)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var sectionsList: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(article.sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    if section.heading != article.title {
                        Divider()

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: section.iconName)
                                .font(.headline)
                                .foregroundStyle(section.tintColor)
                                .accessibilityHidden(true)

                            Text(section.heading)
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }

                    ArticleBodyView(bodyText: section.body)
                        .environment(\.openURL, OpenURLAction { url in
                            if let destination = library.store.article(linkedBy: url, from: article) {
                                linkedArticle = destination
                                return .handled
                            }
                            guard let resolved = URL(string: url.relativeString, relativeTo: article.webURL)?.absoluteURL else {
                                return .discarded
                            }
                            return .systemAction(resolved)
                        })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Sheet presentation for browsing the complete voice training library.
struct VoiceTrainingLibraryBrowserView: View {
    var showsDismissButton: Bool = true
    @Environment(\.dismiss) private var dismiss

    init(showsDismissButton: Bool = true) {
        self.showsDismissButton = showsDismissButton
    }

    var body: some View {
        NavigationStack {
            VoiceTrainingLibraryContentView()
                .toolbar {
                    if showsDismissButton {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                dismiss()
                            } label: {
                                Label(String(localized: "common.action.close", defaultValue: "关闭"), systemImage: "xmark")
                            }
                            .accessibilityIdentifier("voiceLibrary.closeBrowser")
                        }
                    }
                }
        }
    }
}

/// Searchable library content that can be pushed from the Practice Hub.
struct VoiceTrainingLibraryContentView: View {
    @State private var searchText = ""
    @State private var selectedCategory: String?

    init(initialCategory: String? = nil) {
        _selectedCategory = State(initialValue: initialCategory)
    }

    @ObservedObject private var library = VoiceTrainingLibraryLoader.shared
    private var store: VoiceTrainingLibraryStore { library.store }

    var body: some View {
        let groups = store.categories(matching: searchText, category: selectedCategory)
        let articleCount = groups.reduce(0) { $0 + $1.articles.count }

        List {
            ForEach(groups) { category in
                Section(category.title) {
                    ForEach(category.articles) { article in
                        NavigationLink {
                            VoiceArticleContentView(article: article)
                        } label: {
                            VoiceLibraryListRow(article: article)
                        }
                        .accessibilityIdentifier("voiceLibrary.article.\(article.id)")
                    }
                }
            }

            if articleCount > 0 {
                Section {
                } footer: {
                    Text(String(localized: "voiceLibrary.articleCount", defaultValue: "共 \(articleCount) 篇教程与说明"))
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .overlay {
            if store.articles.isEmpty {
                VoiceTrainingLibraryLoadStatusView(loader: library)
            } else if articleCount == 0 {
                emptyStateView
            }
        }
        .navigationTitle(selectedCategory == nil ? String(localized: "voiceLibrary.title", defaultValue: "嗓音训练知识库") : selectedCategoryTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: String(localized: "voiceLibrary.search.prompt", defaultValue: "搜索发声技巧、规则或指标"))
        #else
        .searchable(text: $searchText, prompt: String(localized: "voiceLibrary.search.prompt", defaultValue: "搜索发声技巧、规则或指标"))
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(String(localized: "voiceLibrary.filter.category", defaultValue: "分类"), selection: $selectedCategory) {
                        Text(String(localized: "voiceLibrary.filter.all", defaultValue: "全部分类"))
                            .tag(nil as String?)
                        ForEach(categoryOptions, id: \.id) { category in
                            Text(category.title).tag(Optional(category.id))
                        }
                    }
                } label: {
                    Label(
                        String(localized: "voiceLibrary.filter.category", defaultValue: "分类"),
                        systemImage: selectedCategory == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
                    )
                }
                .accessibilityValue(selectedCategoryTitle)
                .accessibilityIdentifier("voiceLibrary.categoryFilter")
            }
        }
        .task { await library.load() }
        .accessibilityIdentifier("voiceLibrary.browser")
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(String(localized: "voiceLibrary.search.emptyTitle", defaultValue: "没有找到文章"), systemImage: "magnifyingglass")
        } description: {
            Text(String(localized: "voiceLibrary.search.emptyDescription", defaultValue: "试试其他关键词，或查看全部分类。"))
        } actions: {
            if selectedCategory != nil {
                Button(String(localized: "voiceLibrary.filter.showAll", defaultValue: "查看全部分类")) {
                    selectedCategory = nil
                }
                .buttonStyle(.bordered)
            }
            if !searchText.isEmpty {
                Button(String(localized: "voiceLibrary.search.clear", defaultValue: "清除搜索")) {
                    searchText = ""
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var categoryOptions: [VoiceTrainingLibraryStore.Category] { store.categories }

    private var selectedCategoryTitle: String {
        categoryOptions.first(where: { $0.id == selectedCategory })?.title
            ?? String(localized: "voiceLibrary.filter.all", defaultValue: "全部分类")
    }
}

/// A plain row whose navigation affordance and background belong to the system List.
private struct VoiceLibraryListRow: View {
    let article: VoiceArticle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AdaptiveRowStack(spacing: 12) {
            Image(systemName: article.iconName)
                .font(.title3)
                .foregroundStyle(article.themeColor)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)



                Text(String(localized: "voiceLibrary.article.readingTime", defaultValue: "约 \(article.readingTimeMinutes) 分钟阅读"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct AdaptiveRowStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var spacing: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        let isAccessibility = dynamicTypeSize.isAccessibilitySize
        let layout = isAccessibility
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        layout { content() }
    }
}

/// Rich inline text renderer supporting LaTeX equations and localized markdown text.
struct RichInlineText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        #if canImport(LaTeXSwiftUI)
        let normalizedText = Self.normalizedMathText(text)
        if Self.isStandaloneDisplayMath(normalizedText) {
            ScrollView(.horizontal, showsIndicators: true) {
                LaTeX(normalizedText.trimmingCharacters(in: .whitespacesAndNewlines))
                    // Own the scroll container instead of nesting the package's block scroller.
                    .blockMode(.alwaysInline)
                    .font(.body)
                    .imageRenderingMode(.template)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.vertical, 4)
            }
            .scrollIndicators(.visible, axes: .horizontal)
            .scrollIndicatorsFlash(onAppear: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if normalizedText.contains("$") {
            LaTeX(normalizedText)
                .font(.body)
                .imageRenderingMode(.template)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } else {
            Text(LocalizedStringKey(text))
                .textSelection(.enabled)
        }
        #else
        Text(LocalizedStringKey(text))
            .textSelection(.enabled)
        #endif
    }

    /// Only a complete, single display block gets an intrinsic-width scroll container.
    nonisolated static func isStandaloneDisplayMath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 else {
            return false
        }
        let content = trimmed.dropFirst(2).dropLast(2)
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.contains("$$")
    }

    nonisolated private static let mathDelimiterExpression = try? NSRegularExpression(
        pattern: #"(?<!\\)\\\((.+?)(?<!\\)\\\)|(?<!\\)\\\[(.+?)(?<!\\)\\\]"#,
        options: .dotMatchesLineSeparators
    )

    /// LaTeXSwiftUI uses dollar delimiters; leave incomplete or nested pairs intact.
    nonisolated static func normalizedMathText(_ text: String) -> String {
        guard text.contains(#"\("#) || text.contains(#"\["#) else {
            return text
        }
        guard let regex = Self.mathDelimiterExpression else {
            return text
        }
        let source = text as NSString
        let result = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let isInline = match.range(at: 1).location != NSNotFound
            let content = source.substring(with: match.range(at: isInline ? 1 : 2))
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ![#"\("#, #"\)"#, #"\["#, #"\]"#].contains(where: { content.contains($0) }) else {
                continue
            }
            let delimiter = isInline ? "$" : "$$"
            result.replaceCharacters(in: match.range, with: delimiter + content + delimiter)
        }
        return result as String
    }
}

/// Structured body renderer for voice articles parsing subheadings, tables, and lists.
struct ArticleBodyView: View {
    let bodyText: String
    @StateObject private var parser = ArticleBodyParser()
    @ScaledMetric(relativeTo: .subheadline) private var tableMinimumColumnWidth: CGFloat = 100
    @ScaledMetric(relativeTo: .subheadline) private var tableMaximumColumnWidth: CGFloat = 280

    nonisolated enum BodyElement: Identifiable, Equatable, Sendable {
        case subheading(id: String, text: String)
        case table(id: String, headers: [String], rows: [[String]])
        case bulletItem(id: String, level: Int, text: String)
        case numberedItem(id: String, number: String, text: String)
        case paragraph(id: String, text: String)
        case divider(id: String)

        var id: String {
            switch self {
            case .subheading(let id, _),
                 .table(let id, _, _),
                 .bulletItem(let id, _, _),
                 .numberedItem(let id, _, _),
                 .paragraph(let id, _),
                 .divider(let id):
                return id
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parser.document(for: bodyText).elements) { element in
                renderElement(element)
            }
        }
    }

    @ViewBuilder
    private func renderElement(_ element: BodyElement) -> some View {
        switch element {
        case .subheading(_, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LibraryTheme.accent)
                    .frame(width: 4, height: 16)
                    .accessibilityHidden(true)

                RichInlineText(text)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 6)

        case .table(_, let headers, let rows):
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow(alignment: .top) {
                        ForEach(headers.indices, id: \.self) { idx in
                            tableCell(headers[idx], isHeader: true)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    .background(Color.secondary.opacity(0.12))
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    ForEach(rows.indices, id: \.self) { rIdx in
                        let row = rows[rIdx]
                        GridRow(alignment: .top) {
                            ForEach(headers.indices, id: \.self) { cIdx in
                                let cellText = cIdx < row.count ? row[cIdx] : ""
                                tableCell(cellText)
                            }
                        }
                        .background(rIdx % 2 == 1 ? Color.secondary.opacity(0.04) : Color.clear)
                        if rIdx < rows.count - 1 {
                            Divider()
                                .gridCellUnsizedAxes(.horizontal)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }
            }
            .scrollIndicators(.visible, axes: .horizontal)
            .scrollIndicatorsFlash(onAppear: true)
            .padding(.vertical, 4)

        case .bulletItem(_, let level, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(LibraryTheme.accent.opacity(level > 0 ? 0.5 : 0.85))
                    .frame(width: level > 0 ? 5 : 6, height: level > 0 ? 5 : 6)
                    .padding(.leading, CGFloat(level * 14))
                    .accessibilityHidden(true)

                RichInlineText(text)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(.primary.opacity(0.9))
            }

        case .numberedItem(_, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(number).")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(LibraryTheme.accent)
                    .frame(minWidth: 18, alignment: .trailing)
                    .accessibilityHidden(true)

                RichInlineText(text)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(.primary.opacity(0.9))
            }

        case .paragraph(_, let text):
            RichInlineText(text)
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.primary.opacity(0.9))

        case .divider:
            Divider()
                .padding(.vertical, 4)
                .accessibilityHidden(true)
        }
    }

    private func tableCell(_ text: String, isHeader: Bool = false) -> some View {
        RichInlineText(text)
            .font(.subheadline.weight(isHeader ? .semibold : .regular))
            .foregroundStyle(.primary.opacity(isHeader ? 1 : 0.9))
            .lineSpacing(3)
            .frame(minWidth: tableMinimumColumnWidth, maxWidth: tableMaximumColumnWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

/// One parsed document per mounted article section. Changes to its source text
/// replace the document immediately; leaving the reader releases the cache.
@MainActor
final class ArticleBodyParser: ObservableObject {
    nonisolated final class Document: Sendable {
        let source: String
        let elements: [ArticleBodyView.BodyElement]

        init(source: String) {
            self.source = source
            self.elements = ArticleBodyParser.parseElements(source)
        }
    }

    private var cachedDocument: Document?

    func document(for source: String) -> Document {
        if let cachedDocument, cachedDocument.source == source { return cachedDocument }
        let document = Document(source: source)
        cachedDocument = document
        return document
    }

    nonisolated private static func parseElements(_ raw: String) -> [ArticleBodyView.BodyElement] {
        var elements: [ArticleBodyView.BodyElement] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        var idCounter = 0

        func nextID() -> String {
            idCounter += 1
            return "elem-\(idCounter)"
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if trimmed == "---" {
                elements.append(.divider(id: nextID()))
                i += 1
                continue
            }

            // Subheadings
            if trimmed.hasPrefix("### ") {
                let title = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                elements.append(.subheading(id: nextID(), text: title))
                i += 1
                continue
            } else if trimmed.hasPrefix("#### ") {
                let title = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                elements.append(.subheading(id: nextID(), text: title))
                i += 1
                continue
            }

            // Table check
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                var tableLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") && lines[i].trimmingCharacters(in: .whitespaces).hasSuffix("|") {
                    tableLines.append(lines[i].trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                if tableLines.count >= 2 {
                    let parseRow = { (r: String) -> [String] in
                        r.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
                    }
                    let headers = parseRow(tableLines[0])
                    let dataLines = tableLines.dropFirst().filter { !$0.contains("---") }
                    let rows = dataLines.map { parseRow($0) }
                    elements.append(.table(id: nextID(), headers: headers, rows: rows))
                    continue
                }
            }

            // Bullet lists: - or *
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let indentLevel = min(3, leadingSpaces / 2)

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let bulletText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                elements.append(.bulletItem(id: nextID(), level: indentLevel, text: bulletText))
                i += 1
                continue
            }

            // Numbered lists: 1. or 2.
            if let numMatch = trimmed.range(of: #"^\d+[\.、]\s*"#, options: .regularExpression) {
                let numPrefix = String(trimmed[numMatch])
                let digits = numPrefix.filter { $0.isNumber }
                let text = String(trimmed[numMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
                elements.append(.numberedItem(id: nextID(), number: digits, text: text))
                i += 1
                continue
            }

            // Regular paragraph
            elements.append(.paragraph(id: nextID(), text: trimmed))
            i += 1
        }

        return elements
    }
}
