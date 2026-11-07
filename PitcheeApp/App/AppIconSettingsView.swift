//
//  AppIconSettingsView.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/6.
//

import SwiftUI
import UIKit

/// The primary icon and the six alternate icons shipped with the app.
///
/// The raw values for the alternate icons intentionally match the app icon set
/// names in the asset catalog. They are kept separate from the user-facing
/// titles so the display copy can be translated without changing the icon API.
enum AppIconOption: String, CaseIterable, Identifiable {
    case defaultIcon = "default"
    case aquaEcho = "AquaEcho"
    case aquaWave = "AquaWave"
    case coralNote = "CoralNote"
    case coralSong = "CoralSong"
    case sageCub = "SageCub"
    case sageHaven = "SageHaven"

    var id: String { rawValue }

    /// `nil` asks UIKit to restore the primary app icon.
    var alternateIconName: String? {
        self == .defaultIcon ? nil : rawValue
    }

    /// The image name used for the in-app preview thumbnail.
    var previewAssetName: String {
        self == .defaultIcon ? "Default" : rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .defaultIcon: "about.appIcon.default.title"
        case .aquaEcho: "about.appIcon.aquaEcho.title"
        case .aquaWave: "about.appIcon.aquaWave.title"
        case .coralNote: "about.appIcon.coralNote.title"
        case .coralSong: "about.appIcon.coralSong.title"
        case .sageCub: "about.appIcon.sageCub.title"
        case .sageHaven: "about.appIcon.sageHaven.title"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .defaultIcon: "about.appIcon.default.description"
        case .aquaEcho: "about.appIcon.aquaEcho.description"
        case .aquaWave: "about.appIcon.aquaWave.description"
        case .coralNote: "about.appIcon.coralNote.description"
        case .coralSong: "about.appIcon.coralSong.description"
        case .sageCub: "about.appIcon.sageCub.description"
        case .sageHaven: "about.appIcon.sageHaven.description"
        }
    }

    init?(alternateIconName: String?) {
        guard let alternateIconName else {
            self = .defaultIcon
            return
        }
        self.init(rawValue: alternateIconName)
    }
}

/// Combined appearance picker used by Settings. Theme families and app icons
/// intentionally share the same selectable row treatment, while the theme
/// rows preview their background instead of an image asset.
struct PersonalizationSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStorageKey.themeSelection) private var savedThemeSelection = AppThemeOption.twilt.rawValue
    @AppStorage(AppStorageKey.customThemeColor) private var customThemeColor = ""
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    @State private var isChangingIcon = false

    private var appearance: GradientAppearance {
        colorScheme == .dark ? .dark : .light
    }

    private var selectedTheme: AppThemeOption {
        AppThemeOption(rawValue: savedThemeSelection) ?? .twilt
    }

    private var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    var body: some View {
        List {
            Section {
                ForEach(AppThemeOption.allCases) { option in
                    Button {
                        selectTheme(option)
                    } label: {
                        ThemeOptionRow(
                            option: option,
                            appearance: appearance,
                            isSelected: selectedTheme == option
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.theme.\(option.id)")
                }
            } header: {
                Text("settings.theme.sectionTitle")
            } footer: {
                Text("settings.theme.description")
            }

            Section {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        selectIcon(option)
                    } label: {
                        AppIconOptionRow(
                            option: option,
                            isSelected: selectedIconName == option.alternateIconName
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isChangingIcon || !supportsAlternateIcons)
                    .accessibilityIdentifier("settings.appIcon.\(option.id)")
                }
            } header: {
                Text("about.appIcon.sectionTitle")
            } footer: {
                Text("about.appIcon.footer")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("settings.personalization.sectionTitle")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedIconName = UIApplication.shared.alternateIconName
        }
    }

    private func selectTheme(_ option: AppThemeOption) {
        savedThemeSelection = option.rawValue
        // The old custom-color setting remains in storage for compatibility,
        // but a selected named theme is the source of truth for this picker.
        customThemeColor = ""
    }

    private func selectIcon(_ option: AppIconOption) {
        guard selectedIconName != option.alternateIconName,
              supportsAlternateIcons else { return }

        isChangingIcon = true
        UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
            Task { @MainActor in
                isChangingIcon = false
                if error == nil {
                    selectedIconName = option.alternateIconName
                }
            }
        }
    }
}

private struct ThemeOptionRow: View {
    let option: AppThemeOption
    let appearance: GradientAppearance
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ThemeThumbnail(
                theme: option,
                appearance: appearance
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(option.title(for: appearance))
                    .font(.body.weight(.medium))
                Text(option.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(
                    isSelected
                        ? AppTheme.color(for: option, appearance: appearance)
                        : .secondary
                )
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(LocalizedStringKey(isSelected
            ? "about.appIcon.selected"
            : "about.appIcon.notSelected")))
    }
}

struct AppIconOptionRow: View {
    let option: AppIconOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            AppIconThumbnail(assetName: option.previewAssetName)

            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(.body.weight(.medium))
                Text(option.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.pitcheeAccent : .secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(LocalizedStringKey(isSelected ? "about.appIcon.selected" : "about.appIcon.notSelected")))
    }
}

struct AppIconThumbnail: View {
    let assetName: String
    private let fixedSize: CGFloat?
    @ScaledMetric(relativeTo: .body) private var size = 56

    init(assetName: String, size: CGFloat? = nil) {
        self.assetName = assetName
        fixedSize = size
    }

    private var renderedSize: CGFloat {
        min(fixedSize ?? size, 72)
    }

    var body: some View {
        Group {
            if let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(14)
                    .foregroundStyle(.secondary)
            }
        }
        .scaledToFill()
        .frame(width: renderedSize, height: renderedSize)
        .clipShape(RoundedRectangle(cornerRadius: renderedSize * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Personalization Settings") {
    NavigationStack { PersonalizationSettingsView() }
}
#endif
