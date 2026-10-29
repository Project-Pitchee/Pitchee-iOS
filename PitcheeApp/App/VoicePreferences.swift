//
//  VoicePreferences.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/18.
//

import SwiftUI

extension VoicePreference {
    /// Option title, looked up in the string catalog at render time.
    var title: LocalizedStringKey {
        switch self {
        case .masculine: "voiceProfile.option.masculine.title"
        case .feminine: "voiceProfile.option.feminine.title"
        case .undecided: "voiceProfile.option.undecided.title"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .masculine: "voiceProfile.option.masculine.description"
        case .feminine: "voiceProfile.option.feminine.description"
        case .undecided: "voiceProfile.option.undecided.description"
        }
    }

    var scoreTitle: LocalizedStringKey {
        switch self {
        case .masculine: "scoring.masculine.title"
        case .feminine: "scoring.feminine.title"
        case .undecided: "common.metric.compositeScore.title"
        }
    }

    var scoreTitleText: String {
        switch self {
        case .masculine: String(localized: "scoring.masculine.title")
        case .feminine: String(localized: "scoring.feminine.title")
        case .undecided: String(localized: "common.metric.compositeScore.title")
        }
    }

    var standardMetricTitle: LocalizedStringKey {
        switch self {
        case .masculine: "scoring.masculine.standard.title"
        case .feminine, .undecided: "common.metric.standardScore.title"
        }
    }

    var scoreExplanationTitle: LocalizedStringKey {
        switch self {
        case .masculine: "scoring.masculine.explanation.title"
        case .feminine, .undecided: "scoring.explanation.title"
        }
    }

    var scoreDirectionDescription: LocalizedStringKey {
        switch self {
        case .masculine: "scoring.masculine.explanation.description"
        case .feminine: "scoring.feminine.explanation.description"
        case .undecided: "scoring.explanation.intro.description"
        }
    }

}

struct VoicePreferenceCard: View {
    let option: VoicePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(option.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.pitcheeAccent : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(
                isSelected ? Color.pitcheeAccent.opacity(0.07) : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? Color.pitcheeAccent : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct PrivacyPromiseView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("voiceProfile.privacyPromise.title", systemImage: "lock.shield")
                .font(.headline)
            promise("voiceProfile.privacyPromise.onDevice.title", detail: "voiceProfile.privacyPromise.onDevice.description", symbol: "iphone")
            promise("voiceProfile.privacyPromise.recordingUsage.title", detail: "practice.audio.lifetime", symbol: "waveform")
            promise("voiceProfile.privacyPromise.userControl.title", detail: "voiceProfile.privacyPromise.userControl.description", symbol: "slider.horizontal.3")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func promise(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.pitcheeAccent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
private struct VoicePreferencesPreview: View {
    @State private var selection: VoicePreference = .feminine

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(VoicePreference.allCases) { option in
                    VoicePreferenceCard(option: option, isSelected: selection == option) {
                        selection = option
                    }
                }
                PrivacyPromiseView()
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

#Preview("Debug - Voice Preferences") {
    VoicePreferencesPreview()
}

#Preview("Debug - Privacy Promise", traits: .sizeThatFitsLayout) {
    PrivacyPromiseView().padding()
}
#endif
