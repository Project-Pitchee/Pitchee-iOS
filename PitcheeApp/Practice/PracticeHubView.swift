//
//  PracticeHubView.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/4.
//

import SwiftUI

enum PracticeRoute: Hashable {
    case scoring
    case analysis
    case pitch
    case spectrum
    case spectrogram
    case library
}

/// Live tools and the training library entry point.
struct PracticeHubView: View {
    @Binding var path: [PracticeRoute]
    @AppStorage(AppStorageKey.themeSelection) private var savedTheme = AppThemeOption.twilt.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var palette: AppThemePalette {
        (AppThemeOption(rawValue: savedTheme) ?? .twilt)
            .dashboardPalette(for: colorScheme == .dark ? .dark : .light)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("practice.hub.live.title")
                        .font(.headline)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.leading, sectionTitleLeading)
                    liveGrid
                }
                libraryModule
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { AppThemeBackground() }
        .navigationTitle("practice.hub.tab")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// iOS 26+ gives the native large title a 20pt margin; match it without
    /// widening the 16pt grid margins.
    private var sectionTitleLeading: CGFloat {
        if #available(iOS 26.0, *) { 4 } else { 0 }
    }

    @ViewBuilder
    private var liveGrid: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { liveGridContent }
        } else {
            liveGridContent
        }
    }

    private var liveGridContent: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
            spacing: 12
        ) {
            PracticeLiveCard(
                title: "recording.screen.title",
                systemImage: "checkmark.seal",
                tint: palette.glass,
                accessibilityIdentifier: "practice.openScoring"
            ) {
                path.append(.scoring)
            }
            PracticeLiveCard(
                title: LocalizedStringKey(MonitorKind.pitch.titleKey),
                systemImage: MonitorKind.pitch.symbol,
                tint: palette.glass,
                accessibilityIdentifier: "monitor.openPitch"
            ) {
                path.append(.pitch)
            }
            PracticeLiveCard(
                title: LocalizedStringKey(MonitorKind.spectrum.titleKey),
                systemImage: MonitorKind.spectrum.symbol,
                tint: palette.glass,
                accessibilityIdentifier: "monitor.openSpectrum"
            ) {
                path.append(.spectrum)
            }
            PracticeLiveCard(
                title: "practice.spectrum.title",
                systemImage: "waveform.badge.magnifyingglass",
                tint: palette.glass,
                accessibilityIdentifier: "practice.openSpectrogram"
            ) {
                path.append(.spectrogram)
            }
        }
    }

    private var libraryModule: some View {
        Button {
            path.append(.library)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "books.vertical.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(
                        Color.accentColor.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("voiceLibrary.title")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    Text("voiceLibrary.search.prompt")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(tint: palette.glass, cornerRadius: 20, interactive: true, highlight: true)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("practice.openLibrary")
    }
}

private struct PracticeLiveCard: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(
                        Color.accentColor.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            .liquidGlass(tint: tint, cornerRadius: 20, interactive: true, highlight: true)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
