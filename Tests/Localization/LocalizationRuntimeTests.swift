//
//  LocalizationRuntimeTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import Foundation

@main
enum LocalizationRuntimeTests {
    static func main() {
        let pairs = PracticeKind.allCases.flatMap { kind in
            [(kind.title, "practice.kind.\(kind.rawValue).title"),
             (kind.instruction, "practice.kind.\(kind.rawValue).instruction")]
        } + PracticeMetric.allCases.map { ($0.title, "practice.metric.\($0.rawValue)") }
          + PracticeFeedback.allCases.map { ($0.title, "practice.feedback.\($0.rawValue)") }
          + RecordingQuality.Issue.allCases.map { ($0.advice, "practice.quality.\($0.rawValue)") }

        for (actual, key) in pairs {
            let expected = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            precondition(expected != key && actual == expected, "Unresolved practice text: \(key)")
        }

        for count in [1, 2, 5, 49] {
            let readingTime = String(localized: "voiceLibrary.article.readingTime",
                                     defaultValue: "约 \(count) 分钟阅读")
            let articleCount = String(localized: "voiceLibrary.articleCount",
                                      defaultValue: "共 \(count) 篇教程与说明")
            for (actual, key) in [(readingTime, "voiceLibrary.article.readingTime"),
                                  (articleCount, "voiceLibrary.articleCount")] {
                let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
                let expected = String(format: format, count)
                precondition(actual == expected && !actual.contains("%"), "Unformatted count: \(key)")
            }
        }
        print("PASS: \(Bundle.main.preferredLocalizations.first ?? "unknown") practice labels and library counts")
    }
}
