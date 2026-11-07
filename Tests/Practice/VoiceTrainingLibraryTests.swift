//
//  VoiceTrainingLibraryTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import Foundation

@main
enum VoiceTrainingLibraryTests {
    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the test resource directory explicitly") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = try await VoiceTrainingLibraryStore.load(directory: directory, preferredLanguages: ["zh-CN"])
        await testLoading(store: store)
        try await testLanguages(directory: directory, chinese: store)
        try testInvalidResources(directory: directory)
        for heading in ["机制", "Understanding", "Comprendre", "الفهم"] {
            assert(VoiceArticle.Section(heading: heading, body: "Body").iconName == "doc.text.fill")
            assert(VoiceArticle.Section(heading: heading, icon: "figure.run", body: "Body").iconName == "figure.run")
        }
        assert(store.articles.count == 10)
        for article in store.articles {
            assert(article.sections.allSatisfy { $0.iconName == "doc.text.fill" && !$0.body.isEmpty })
            assert(article.sections.first?.heading == article.title)
            assert(article.sections.count == (article.id.hasPrefix("practice/") ? 6 : article.id == "rules/03-pass-boost" ? 2 : 3))
            assert(article.sections.allSatisfy { article.rawContent.contains($0.body) })
            assert(article.webURL.host == "github.com")
            assert(article.webURL.path.hasSuffix("/blob/4f7af0023a85c773fda0dd0485ca6b0d58b8c062/" + article.filename))
        }

        assert(store.categories.map(\.id) == Set(store.articles.map(\.category)).sorted())
        for category in store.categories {
            let expected = store.articles.filter { $0.category == category.id }
            assert(category.articles == expected)
            assert(store.articles(inCategory: category.id) == expected)
            assert(category.title == expected.first?.categoryDisplayTitle)
        }
        for query in ["", "  \n", "吸管", "RULE", "f0", "no-matching-article-xyz"] {
            for category in [nil, "", "rules", "timbre", "naturalness", "pitch", "missing"] as [String?] {
                for preference in [nil, .feminine, .masculine, .undecided] as [VoicePreference?] {
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let expected = store.articles.filter { article in
                        if let category, !category.isEmpty, article.category != category { return false }
                        if let preference, !article.targetPreferences.contains(preference.rawValue) { return false }
                        return trimmed.isEmpty || [article.title, article.summary, article.coreGoal, article.id, article.rawContent]
                            .contains { $0.localizedCaseInsensitiveContains(trimmed) }
                    }
                    assert(store.search(query: query, category: category, preference: preference) == expected)
                    if preference == nil {
                        let groups = store.categories(matching: query, category: category)
                        let expectedGroups = Dictionary(grouping: expected, by: \.category)
                        assert(groups.map(\.id) == expectedGroups.keys.sorted())
                        assert(groups.allSatisfy { $0.articles == expectedGroups[$0.id] })
                    }
                }
            }
        }
        print("✓ Indexed categories and searches preserve article order, category prefixes, goal filters and current localized titles")

        let parser = ArticleBodyParser()
        let markdown = """
        ### 小标题
        一段 **强调** 文字。
        - 一级条目
          * 二级条目
        2. 编号条目
        3、另一个编号
        | 指标 | 说明 |
        | --- | --- |
        | F0 | 频率 |
        ---
        #### 第二标题
        """
        let document = parser.document(for: markdown)
        assert(document === parser.document(for: markdown))
        assert(document.elements == [
            .subheading(id: "elem-1", text: "小标题"),
            .paragraph(id: "elem-2", text: "一段 **强调** 文字。"),
            .bulletItem(id: "elem-3", level: 0, text: "一级条目"),
            .bulletItem(id: "elem-4", level: 1, text: "二级条目"),
            .numberedItem(id: "elem-5", number: "2", text: "编号条目"),
            .numberedItem(id: "elem-6", number: "3", text: "另一个编号"),
            .table(id: "elem-7", headers: ["指标", "说明"], rows: [["F0", "频率"]]),
            .divider(id: "elem-8"),
            .subheading(id: "elem-9", text: "第二标题")
        ])
        let translated = parser.document(for: "### Updated heading\nChanged **content**.")
        assert(translated !== document)
        assert(translated.elements == [.subheading(id: "elem-1", text: "Updated heading"),
                                        .paragraph(id: "elem-2", text: "Changed **content**.")])
        assert(parser.document(for: "").elements.isEmpty)
        assert(parser.document(for: markdown) !== document) // The cache retains one source, not all prior articles.
        for article in store.articles {
            for section in article.sections {
                let parsed = parser.document(for: section.body)
                assert(!parsed.elements.isEmpty && Set(parsed.elements.map(\.id)).count == parsed.elements.count)
                assert(parser.document(for: section.body) === parsed)
            }
        }
        print("✓ Markdown is reused for unchanged sections; changed or localized text immediately replaces the single cached document")

        for _ in 0..<3 {
            assert(RichInlineText.normalizedMathText(#"Inline \(f_0\), display \[x + y\]."#)
                   == "Inline $f_0$, display $$x + y$$.")
            assert(RichInlineText.normalizedMathText(#"Incomplete \(x"#) == #"Incomplete \(x"#)
            assert(RichInlineText.normalizedMathText(#"Nested \(x \(y\)\)"#) == #"Nested \(x \(y\)\)"#)
            assert(RichInlineText.normalizedMathText(#"Escaped \\(x\\)"#) == #"Escaped \\(x\\)"#)
            assert(RichInlineText.normalizedMathText(#"Empty \( \)"#) == #"Empty \( \)"#)
        }
        assert(RichInlineText.isStandaloneDisplayMath(" $$x + y$$ "))
        assert(!RichInlineText.isStandaloneDisplayMath("$$x$$ and $$y$$"))
        print("✓ Shared math matching preserves inline, display, escaped, incomplete and nested delimiters")

        func quality(_ speech: Double = 8, level: Double? = -25, background: Double? = -50, clipped: Double? = 0) -> RecordingQuality {
            RecordingQuality(speechSeconds: speech, speechDBFS: level, backgroundDBFS: background, clippedFraction: clipped)
        }
        func result(
            pitch: Double? = 200, deviation: Double? = 22, standard: Double = 80,
            naturalness: Double = 85, speech: Double = 8, score: Double? = nil,
            rule: String? = nil, scoreProfile: String? = nil, model: String = "test",
            pitchFrames: Int? = nil, pitchWindows: Int? = nil,
            standardWindows: Int = 10, naturalnessWindows: Int = 10
        ) -> PitcheeAnalysisResult {
            let calculated = scoreProfile == "masculinization"
                ? VoiceDirectionScore.masculineComposite(feminineScore: standard, naturalness: naturalness, pitchHz: pitch)
                : VoiceDirectionScore.feminineComposite(standardScore: standard, naturalness: naturalness, pitchHz: pitch)
            return PitcheeAnalysisResult(
                schemaVersion: 3, modelVersion: model, scoreProfile: scoreProfile,
                audio: .init(sourceSampleRate: 16_000, sourceChannels: 1, inputSeconds: speech, analyzedSeconds: speech),
                vad: .init(segmentCount: 1, speechSeconds: speech, sileroSegmentCount: 1, discardedBreathLikeCount: 0, trimmedSegmentCount: 0, segments: []),
                f0: .init(windowSeconds: 0.5, meanHz: pitch, standardDeviationHz: deviation,
                          voicedFrameCount: pitchFrames ?? (pitch == nil ? 0 : 100),
                          voicedWindowCount: pitchWindows ?? (pitch == nil ? 0 : 10), windows: []),
                vfp: .init(vfpStandardScore: standard, windowCount: standardWindows, windowDurationSeconds: 1, windows: []),
                naturalness: .init(score: naturalness, windowCount: naturalnessWindows, windowDurationSeconds: 1, windows: []),
                composite: .init(baseScore: calculated.baseScore, finalScore: score ?? calculated.finalScore,
                                 cap: calculated.cap, rule: rule ?? calculated.rule,
                                 limited: calculated.limited, boosted: calculated.boosted)
            )
        }
        func recommend(_ sample: PitcheeAnalysisResult, _ preference: VoicePreference = .feminine, quality capture: RecordingQuality? = RecordingQuality(speechSeconds: 8, speechDBFS: -25, backgroundDBFS: -50, clippedFraction: 0), volume: RecordingVolumeStatistics? = nil) -> VoiceTrainingRecommendation {
            VoiceLibraryMatcher.recommend(for: sample, preference: preference, quality: capture, volumeStatistics: volume, store: store)
        }
        func IDs(_ recommendation: VoiceTrainingRecommendation) -> [String] {
            recommendation.prioritySuggestions.map(\.id)
        }
        func articles(_ recommendation: VoiceTrainingRecommendation) -> [String] {
            recommendation.combinedArticles.map(\.id)
        }
        func assertCaptureOnly(_ recommendation: VoiceTrainingRecommendation) {
            assert(recommendation.matchedRule == "recording_quality")
            assert(recommendation.prioritySuggestions.allSatisfy { $0.id.hasPrefix("capture") })
            assert(recommendation.combinedArticles.isEmpty)
            assert(recommendation.prioritySuggestions.allSatisfy { $0.article == nil })
            assert(recommendation.acousticAlertArticles.isEmpty && recommendation.deepDiveArticles.isEmpty)
        }

        let good = result()
        let pass = recommend(good)
        assert(pass.primaryArticle?.id == "rules/03-pass-boost")
        assertCaptureOnly(recommend(good, quality: nil))
        assertCaptureOnly(recommend(good, quality: quality(level: nil, clipped: nil)))
        let staleQuality = try JSONDecoder().decode(RecordingQuality.self, from: Data("""
        {"version":"capture-quality-old","issues":[],"backgroundMeasured":true}
        """.utf8))
        assertCaptureOnly(recommend(good, quality: staleQuality))
        print("✓ Valid persisted quality supports personalization; unavailable or stale quality does not")

        let short = recommend(result(speech: 3), quality: quality(3))
        assert(IDs(short) == ["captureDuration"])
        assert(short.prioritySuggestions.first?.article == nil)
        assertCaptureOnly(short)
        assertCaptureOnly(recommend(result(speech: 3))) // Contradictory persisted quality cannot hide short speech.
        assertCaptureOnly(recommend(result(speech: .nan)))
        let simultaneous = recommend(result(speech: 3), quality: quality(3, level: -48, background: -50, clipped: 0.02))
        assert(IDs(simultaneous) == ["captureClipping", "captureEnvironment"])
        assertCaptureOnly(simultaneous)
        assert(IDs(recommend(good, quality: quality(background: -28))) == ["captureEnvironment"])
        assert(IDs(recommend(good, quality: quality(level: -50))) == ["captureEnvironment"])
        print("✓ Short, quiet, noisy and clipped recordings yield up to two capture steps without physiological guesses")

        let cleanVolume = RecordingVolumeStatistics(environmentDBFS: -50, averageDBFS: -25, medianDBFS: -25,
            high95DBFS: -20, low5DBFS: -30, windows: [.init(centerSeconds: 0, voiceDBFS: nil, backgroundDBFS: -50)], clippedSampleFraction: 0)
        var clippedVolume = cleanVolume
        clippedVolume.clippedSampleFraction = 0.1
        assert(IDs(recommend(good, quality: nil, volume: cleanVolume)) == IDs(pass))
        assertCaptureOnly(recommend(good, volume: clippedVolume))
        print("✓ Fresh measurements can establish quality or reveal a failure despite a saved passing assessment")

        for preference in VoicePreference.allCases {
            for invalidPitch in [nil, Double.nan, Double.infinity, -5, 0] as [Double?] {
                let unavailable = recommend(result(pitch: invalidPitch), preference)
                assert(IDs(unavailable) == ["pitchUnavailable"])
                assert(unavailable.combinedArticles.isEmpty)
            }
            assert(IDs(recommend(result(pitchFrames: 0), preference)) == ["pitchUnavailable"])
            assert(IDs(recommend(result(pitchWindows: 0), preference)) == ["pitchUnavailable"])
            assert(IDs(recommend(result(pitchWindows: 1), preference)) == ["pitchUnavailable"])
            for invalidScore in [Double.nan, Double.infinity, -1, 101] {
                assert(IDs(recommend(result(standard: invalidScore), preference)) == ["analysisUnavailable"])
                assert(IDs(recommend(result(naturalness: invalidScore), preference)) == ["analysisUnavailable"])
            }
            assert(IDs(recommend(result(standardWindows: 0), preference)) == ["analysisUnavailable"])
            assert(IDs(recommend(result(naturalnessWindows: 0), preference)) == ["analysisUnavailable"])
        }
        assert(IDs(recommend(result(score: .nan))) == ["analysisUnavailable"])
        print("✓ Missing pitch, non-finite scores and absent measurement windows never trigger corrective voice training")

        for rule in ["pass_boost", "high_f0_stylized_cap", "high_f0_male_cap", "low_f0_natural_cap", "continuous"] {
            let neutral = recommend(result(rule: rule), .undecided)
            assert(IDs(neutral) == ["explore", "listen"])
            assert(neutral.matchedRule == "nonbinary_exploration")
            assert(neutral.combinedArticles.isEmpty)
        }
        for pitch in [90.0, 140, 180, 270] {
            let masculine = recommend(result(pitch: pitch), .masculine)
            assert(IDs(masculine) == ["masculineBasics", "listen"])
            assert(masculine.combinedArticles.isEmpty)
        }
        assert(IDs(recommend(result(pitch: 80), .masculine)) == ["masculineComfort", "listen"])
        print("✓ Goal changes do not inherit feminine rules, a lower-pitch prescription, or assumed hormone status")

        for preference in [VoicePreference.masculine, .undecided] {
            for sample in [result(pitch: 135, naturalness: 35), result(pitch: 280, naturalness: 49.9)] {
                let ease = recommend(sample, preference)
                assert(IDs(ease) == ["comfortableVoice", "listen"])
                assert(ease.primaryArticle?.id == "practice/02-naturalness")
            }
            assert(recommend(result(naturalness: 50), preference).combinedArticles.isEmpty)
        }
        let ruleCases: [(String, String, String?, PitcheeAnalysisResult)] = [
            ("pass_boost", "rules/03-pass-boost", nil, result()),
            ("high_f0_stylized_cap", "rules/04-high-f0-stylized-cap", "practice/02-naturalness", result(naturalness: 35)),
            ("low_f0_natural_cap", "rules/05-low-f0-natural-cap", "practice/03-low-f0", result(pitch: 150)),
            ("low_f0_stylized_cap", "rules/06-low-f0-stylized-cap", "practice/02-naturalness", result(pitch: 150, naturalness: 35)),
            ("high_f0_male_cap", "rules/07-high-f0-male-cap", "practice/01-vfp", result(standard: 35)),
        ]
        for (rule, articleID, practiceID, sample) in ruleCases {
            let recommendation = recommend(sample)
            assert(recommendation.primaryArticle?.id == articleID)
            assert(recommendation.matchedRule == rule)
            assert(recommendation.prioritySuggestions.first?.id == "rule." + rule)
            if let practiceID {
                assert(articles(recommendation) == [articleID, practiceID])
            } else {
                assert(articles(recommendation) == [articleID])
            }
        }
        assert(recommend(result(pitch: 280, rule: "pass_boost")).primaryArticle?.id == "rules/03-pass-boost")
        for (sample, expectedRule) in [
            (result(pitch: 165, naturalness: 85), "low_f0_natural_cap"),
            (result(pitch: 165.001, naturalness: 85), "pass_boost"),
            (result(pitch: 165, naturalness: 49.999), "low_f0_stylized_cap"),
            (result(pitch: 165.001, naturalness: 49.999), "high_f0_stylized_cap"),
            (result(pitch: 165, naturalness: 50), "low_f0_natural_cap"),
            (result(pitch: 165.001, naturalness: 50), "continuous"),
            (result(standard: 49.999, naturalness: 85), "high_f0_male_cap"),
            (result(standard: 50, naturalness: 85), "continuous"),
            (result(standard: 50.001, naturalness: 85), "pass_boost"),
            (result(naturalness: 80), "continuous"),
            (result(naturalness: 80.001), "pass_boost"),
            (result(pitch: 280), "pass_boost"),
        ] {
            let recommendation = recommend(sample)
            assert(recommendation.matchedRule == expectedRule)
            if expectedRule == "continuous" {
                let expected = sample.composite.finalScore < 60
                    ? "rules/01-feminization-continuous-nopass" : "rules/02-feminization-continuous-pass"
                assert(recommendation.primaryArticle?.id == expected)
            } else {
                assert(recommendation.primaryArticle?.id == ruleCases.first { $0.0 == expectedRule }?.1)
            }
        }
        assert(IDs(recommend(result(deviation: 3))) == IDs(pass))
        assert(IDs(recommend(result(deviation: 80))) == IDs(pass))
        print("✓ Core rules select their actual guides and applicable practice; pitch deviation does not invent a rule")

        for (score, articleID) in [(0.0, "rules/01-feminization-continuous-nopass"), (59.9, "rules/01-feminization-continuous-nopass"), (60.0, "rules/02-feminization-continuous-pass"), (100.0, "rules/02-feminization-continuous-pass")] {
            assert(recommend(result(score: score, rule: "continuous")).primaryArticle?.id == articleID)
        }
        assert(articles(recommend(result(standard: 55, naturalness: 85, score: 55, rule: "continuous"))).last == "practice/01-vfp")
        assert(articles(recommend(result(standard: 80, naturalness: 55, score: 55, rule: "continuous"))).last == "practice/02-naturalness")
        assert(articles(recommend(result(standard: 85, naturalness: 80, rule: "continuous"))).last == "practice/02-naturalness")
        assert(articles(recommend(result(standard: 85, naturalness: 80.001, rule: "continuous"))).last == "practice/01-vfp")
        assert(articles(recommend(result(standard: 60, naturalness: 60, rule: "continuous"))).last == "practice/01-vfp")
        let unknown = recommend(result(rule: "future_rule"))
        assert(IDs(unknown) == ["oneElement", "listen"] && unknown.combinedArticles.isEmpty)

        let libraryData = try Data(contentsOf: directory.appendingPathComponent("voice-training-library.json"))
        let matrixData = try Data(contentsOf: directory.appendingPathComponent("voice-rule-matching-matrix.json"))
        var sharedArticleMatrix = try JSONSerialization.jsonObject(with: matrixData) as! [String: [String]]
        sharedArticleMatrix["high_f0_stylized_cap"] = ["practice/02-naturalness"]
        let sharedArticleStore = try VoiceTrainingLibraryStore(
            libraryData: libraryData,
            matrixData: JSONSerialization.data(withJSONObject: sharedArticleMatrix),
            preferredLanguages: ["zh-CN"]
        )
        let sharedArticleRecommendation = VoiceLibraryMatcher.recommend(
            for: result(naturalness: 35), preference: .feminine,
            quality: quality(), store: sharedArticleStore
        )
        assert(sharedArticleRecommendation.prioritySuggestions.count == 2)
        assert(sharedArticleRecommendation.prioritySuggestions.allSatisfy { $0.article?.id == "practice/02-naturalness" })
        assert(articles(sharedArticleRecommendation) == ["practice/02-naturalness"])
        print("✓ Shared supporting articles never remove distinct suggestions; unknown rules keep article-free guidance")
        let samples = [good, result(pitch: 145), result(pitch: 280), result(naturalness: 40), result(pitch: 80), result(standard: 30)]
        for preference in VoicePreference.allCases {
            for sample in samples {
                let recommendation = recommend(sample, preference)
                assert((1...2).contains(recommendation.prioritySuggestions.count))
                assert(Set(IDs(recommendation)).count == recommendation.prioritySuggestions.count)
                assert(Set(articles(recommendation)).count == recommendation.combinedArticles.count)
                assert(recommendation.combinedArticles.count <= 2)
                assert(recommendation.combinedArticles.allSatisfy { $0.targetPreferences.contains(preference.rawValue) })
                assert(recommendation.prioritySuggestions.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
                assert(IDs(recommendation) == IDs(recommend(sample, preference)))
            }
        }
        print("✓ Score boundaries, deterministic ordering, direction filtering and the two-suggestion limit hold")

        let drop = VoiceLibraryMatcher.recommendForPractice(scoreA: 90, scoreB: 40, store: store)
        assert(IDs(drop) == ["compareDrop"])
        assert(drop.combinedArticles.isEmpty)
        assert(IDs(VoiceLibraryMatcher.recommendForPractice(scoreA: 40, scoreB: 90, store: store)) == ["compare"])
        assert(IDs(VoiceLibraryMatcher.recommendForPractice(scoreA: 90, scoreB: 40, feedback: .unsure, store: store)) == ["listen"])
        assert(IDs(VoiceLibraryMatcher.recommendForPractice(scoreA: .nan, scoreB: 40, store: store)) == ["analysisUnavailable"])
        assertCaptureOnly(VoiceLibraryMatcher.recommendForPractice(resultA: good, resultB: good, store: store))
        assertCaptureOnly(VoiceLibraryMatcher.recommendForPractice(resultA: good, resultB: good, qualityA: quality(), qualityB: quality(clipped: 0.1), store: store))
        let changedModel = VoiceLibraryMatcher.recommendForPractice(resultA: good, resultB: result(model: "other"), qualityA: quality(), qualityB: quality(), store: store)
        assert(IDs(changedModel) == ["compareConditions"])
        let undecided = VoiceLibraryMatcher.recommendForPractice(resultA: good, resultB: result(naturalness: 40), preference: .undecided, qualityA: quality(), qualityB: quality(), store: store)
        assert(IDs(undecided) == ["listen"])
        // Raw feminine scores fall as pitch falls; the selected masculine score rises.
        let masculineComparison = VoiceLibraryMatcher.recommendForPractice(resultA: result(pitch: 220), resultB: result(pitch: 110), preference: .masculine, qualityA: quality(), qualityB: quality(), store: store)
        assert(IDs(masculineComparison) == ["compare"])
        print("✓ A/B guidance respects capture quality, scoring compatibility, goal and listening feedback")

        assert(!store.search(query: "F0").isEmpty)
        assert(store.articles(inCategory: "rules").count == 7)
        print("All Voice Training Library tests passed.")
    }

    @MainActor
    private static func testLoading(store: VoiceTrainingLibraryStore) async {
        actor Attempts {
            private var count = 0
            let failFirst: Bool
            init(failFirst: Bool = false) { self.failFirst = failFirst }
            func load(_ store: VoiceTrainingLibraryStore) async throws -> VoiceTrainingLibraryStore {
                count += 1
                if failFirst && count == 1 {
                    throw VoiceTrainingLibraryStore.LoadError.missingResource("test")
                }
                // Yield so overlapping callers can join the same load.
                await Task.yield()
                return store
            }
            func total() -> Int { count }
        }
        let attempts = Attempts()
        let loader = VoiceTrainingLibraryLoader { try await attempts.load(store) }
        assert(loader.store.articles.isEmpty && !loader.isLoading && loader.error == nil)
        let initialAttempts = await attempts.total()
        assert(initialAttempts == 0, "Initializing a view's shared loader must not start disk I/O")
        async let first: Void = loader.load()
        async let second: Void = loader.load()
        _ = await (first, second)
        assert(loader.store.articles.count == 10 && !loader.isLoading && loader.error == nil)
        await loader.load()
        let loadedAttempts = await attempts.total()
        assert(loadedAttempts == 1, "Concurrent and later callers must reuse the loaded snapshot")

        let failing = Attempts(failFirst: true)
        let retryLoader = VoiceTrainingLibraryLoader { try await failing.load(store) }
        await retryLoader.load()
        assert(retryLoader.error != nil && retryLoader.store.articles.isEmpty && !retryLoader.isLoading)
        await retryLoader.load()
        assert(retryLoader.error == nil && retryLoader.store.articles.count == 10)
        let retryAttempts = await failing.total()
        assert(retryAttempts == 2, "A failed load must allow an explicit retry")

        do {
            _ = try await VoiceTrainingLibraryStore.load(bundle: .main)
            assertionFailure("The standalone test bundle has no JSON resources; source-path fallback must not occur")
        } catch {
            assert(error is VoiceTrainingLibraryStore.LoadError)
        }
        print("✓ Loading is asynchronous, shared, explicit about missing resources, and retryable")
    }

    private static func testLanguages(directory: URL, chinese: VoiceTrainingLibraryStore) async throws {
        assert(chinese.articles.allSatisfy { $0.language == "zh_cn" })
        try testArticleLinks(store: chinese)
        let expectedIDs = Set(chinese.articles.map(\.id))
        for (preferred, expectedLanguage) in [
            (["en-US", "zh-CN"], "en"),
            (["zh-Hans-CN", "en"], "zh_cn"),
            (["fr-FR", "zh-CN", "en"], "zh_cn"),
            (["fr-FR"], "en"),
            ([], "en"),
        ] {
            let localized = try await VoiceTrainingLibraryStore.load(directory: directory, preferredLanguages: preferred)
            assert(localized.articles.count == 10)
            assert(Set(localized.articles.map(\.id)) == expectedIDs)
            assert(localized.articles.allSatisfy { $0.language == expectedLanguage })
            for article in localized.articles {
                let parts = article.id.split(separator: "/")
                assert(article.filename == "\(parts[0])/\(expectedLanguage)/\(parts[1]).md")
                if expectedLanguage == "en" {
                    assert(article.title != chinese.article(for: article.id)?.title)
                }
            }
            if preferred == ["en-US", "zh-CN"] { try testArticleLinks(store: localized) }
        }
        print("✓ Ten logical articles select the first supported language without duplicates; unsupported preferences use English")
    }

    private static func testArticleLinks(store: VoiceTrainingLibraryStore) throws {
        let links = try NSRegularExpression(pattern: #"\[[^\]]+\]\(([^)]+)\)"#)
        var internalLinkCount = 0
        for article in store.articles(inCategory: "rules") {
            for match in links.matches(in: article.rawContent, range: NSRange(article.rawContent.startIndex..., in: article.rawContent)) {
                let target = String(article.rawContent[Range(match.range(at: 1), in: article.rawContent)!])
                assert(target.hasPrefix("../../practice/" + article.language + "/") && target.hasSuffix(".md"))
                let expectedID = "practice/" + target.split(separator: "/").last!.dropLast(3)
                let linked = store.article(linkedBy: URL(string: target)!, from: article)
                assert(linked?.id == expectedID && linked?.language == article.language)
                internalLinkCount += 1
            }
            assert(store.article(linkedBy: URL(string: "https://example.com/guide")!, from: article) == nil)
            assert(store.article(linkedBy: URL(string: "../../practice/\(article.language)/missing.md")!, from: article) == nil)
        }
        assert(internalLinkCount == 9)
        assert(store.article(matching: "f0_unavailable") == nil)
        assert(store.article(matching: "unknown") == nil)
        print("✓ Nine relative guide links resolve within each language; external and missing destinations remain external")
    }

    private static func testInvalidResources(directory: URL) throws {
        let library = try Data(contentsOf: directory.appendingPathComponent("voice-training-library.json"))
        let matrix = try Data(contentsOf: directory.appendingPathComponent("voice-rule-matching-matrix.json"))
        func rejects(_ libraryData: Data, _ matrixData: Data) {
            do {
                _ = try VoiceTrainingLibraryStore(libraryData: libraryData, matrixData: matrixData)
                assertionFailure("Malformed library data must report a load failure")
            } catch {
                assert(error is VoiceTrainingLibraryStore.LoadError)
            }
        }
        rejects(Data("broken JSON".utf8), matrix)
        rejects(library, Data("{}".utf8))
        rejects(library, Data(#"{"missing": ["UNKNOWN-ARTICLE"]}"#.utf8))
        var payload = try JSONSerialization.jsonObject(with: library) as! [String: Any]
        payload["schemaVersion"] = "unsupported"
        rejects(try JSONSerialization.data(withJSONObject: payload), matrix)
        payload["schemaVersion"] = "2.0.0"
        payload["totalArticles"] = 0
        rejects(try JSONSerialization.data(withJSONObject: payload), matrix)
        var articles = payload["articles"] as! [[String: Any]]
        payload["totalArticles"] = articles.count
        articles[1] = articles[0]
        payload["articles"] = articles
        rejects(try JSONSerialization.data(withJSONObject: payload), matrix)
        payload = try JSONSerialization.jsonObject(with: library) as! [String: Any]
        articles = payload["articles"] as! [[String: Any]]
        articles.removeLast()
        payload["articles"] = articles
        payload["totalArticles"] = articles.count
        rejects(try JSONSerialization.data(withJSONObject: payload), matrix)
        payload = try JSONSerialization.jsonObject(with: library) as! [String: Any]
        articles = payload["articles"] as! [[String: Any]]
        articles[0]["language"] = "fr"
        payload["articles"] = articles
        rejects(try JSONSerialization.data(withJSONObject: payload), matrix)
        var rules = try JSONSerialization.jsonObject(with: matrix) as! [String: [String]]
        assert(rules["f0_unavailable"] == [])
        rules["pass_boost"] = ["missing-article"]
        rejects(library, try JSONSerialization.data(withJSONObject: rules))
        rules["pass_boost"] = []
        rejects(library, try JSONSerialization.data(withJSONObject: rules))
        print("✓ Invalid JSON, schema, counts, duplicate language IDs, incomplete translations and broken references are rejected")
    }

}
