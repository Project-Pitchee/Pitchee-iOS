//
//  PracticeSuggestionsSection.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import SwiftUI

/// One compact group of next steps; the whole row opens its supporting guide.
struct PracticeSuggestionsSection: View {
    let suggestions: [VoiceTrainingSuggestion]
    let onOpenArticle: (VoiceArticle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("analysis.suggestions.title")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(suggestions.prefix(2).enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 { Divider().padding(.horizontal, 16) }
                    if let article = suggestion.article {
                        Button { onOpenArticle(article) } label: {
                            suggestionRow(suggestion, opensArticle: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(article.title)
                    } else {
                        suggestionRow(suggestion, opensArticle: false)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func suggestionRow(_ suggestion: VoiceTrainingSuggestion, opensArticle: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(suggestion.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !opensArticle {
                    Text("voiceLibrary.noSpecialistArticle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("voiceLibrary.noSpecialistArticle")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if opensArticle {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(16)
        .contentShape(Rectangle())
    }
}
