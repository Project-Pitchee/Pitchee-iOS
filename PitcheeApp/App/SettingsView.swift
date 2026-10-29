//
//  SettingsView.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/18.
//

import SwiftUI
import UIKit
import Foundation

struct SettingsView: View {
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""
    @AppStorage(AppStorageKey.themeSelection) private var savedThemeSelection = AppThemeOption.twilt.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    #if DEBUG
    @State private var debugRoute: SettingsDebugRoute?
    @State private var didApplyDebugRoute = false
    #endif

    private var selectedVoice: VoicePreference {
        VoicePreference(legacyStoredValue: savedVoicePreference) ?? .undecided
    }

    private var voicePreference: Binding<VoicePreference> {
        Binding(
            get: { selectedVoice },
            set: { savedVoicePreference = $0.rawValue }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    VoicePreferenceSettingsView(selection: voicePreference)
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(systemImage: "waveform", tint: .purple)
                        LabeledContent {
                            Text(selectedVoice.title)
                        } label: {
                            Text("settings.voicePreference.sectionTitle")
                        }
                    }
                }
                .accessibilityLabel("settings.voicePreference.sectionTitle")
                .accessibilityValue(Text(selectedVoice.title))
                .accessibilityIdentifier("settings.voicePreference")

                NavigationLink {
                    PrivacySettingsView()
                } label: {
                    SettingsLabel("voiceProfile.privacyPromise.title", systemImage: "hand.raised.fill", tint: .blue)
                }
                .accessibilityIdentifier("settings.privacy")
            }

            Section {
                NavigationLink {
                    PersonalizationSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        ThemeThumbnail(
                            theme: selectedTheme,
                            appearance: currentAppearance,
                            size: 28
                        )
                        VStack(alignment: .leading) {
                            Text("settings.theme.sectionTitle")
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) {
                            Text(selectedAppIcon.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.trailing, 4)
                        }
                    }
                }
                .accessibilityLabel("settings.personalization.sectionTitle")
                .accessibilityValue(Text(selectedTheme.title(for: currentAppearance)))
                .accessibilityIdentifier("settings.personalization")
            }

            Section {
                NavigationLink {
                    ReadingPassagesSettingsView()
                } label: {
                    SettingsLabel(
                        verbatim: SettingsCopy.text("朗读语料", "Reading Passages"),
                        systemImage: "text.book.closed.fill",
                        tint: .orange
                    )
                }
                .accessibilityIdentifier("settings.passages")

                NavigationLink {
                    F0SettingsView()
                } label: {
                    SettingsLabel(
                        verbatim: SettingsCopy.text("F0 与性能", "F0 & Performance"),
                        systemImage: "tuningfork",
                        tint: .teal
                    )
                }
                .accessibilityIdentifier("settings.f0")
            }

            Section {
                LabeledContent("about.app.version.label", value: appVersion)
                LabeledContent("about.app.analysisEngine.label", value: "PitcheeCore")
            }

            Section {
                Link(destination: repositoryURL) {
                    HStack(spacing: 12) {
                        Image("GitHub")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                            .background(
                                Color.primary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .accessibilityHidden(true)
                        Text(verbatim: SettingsCopy.text("项目仓库", "Repository"))
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityIdentifier("settings.repository")
                }
                Link(destination: licenseURL) {
                    SettingsLabel(
                        verbatim: SettingsCopy.text("开源许可证", "Open-source Licenses"),
                        systemImage: "doc.text.fill",
                        tint: .brown
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("about.screen.title")
        .navigationBarTitleDisplayMode(.large)
        #if DEBUG
        .navigationDestination(item: $debugRoute) { route in
            switch route {
            case .f0:
                F0SettingsView()
            case .passages:
                ReadingPassagesSettingsView()
            case .personalization:
                PersonalizationSettingsView()
            }
        }
        #endif
        .onAppear {
            selectedIconName = UIApplication.shared.alternateIconName
            #if DEBUG
            if !didApplyDebugRoute {
                didApplyDebugRoute = true
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("-f0-settings-preview") {
                    debugRoute = .f0
                } else if arguments.contains("-passages-settings-preview") {
                    debugRoute = .passages
                } else if arguments.contains("-personalization-preview") {
                    debugRoute = .personalization
                }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                selectedIconName = UIApplication.shared.alternateIconName
            }
        }
    }

    private var currentAppearance: GradientAppearance {
        colorScheme == .dark ? .dark : .light
    }

    private var selectedTheme: AppThemeOption {
        AppThemeOption(rawValue: savedThemeSelection) ?? .twilt
    }

    private var selectedAppIcon: AppIconOption {
        AppIconOption(alternateIconName: selectedIconName) ?? .defaultIcon
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/project-pitchee/Pitchee-iOS")!
    }

    private var licenseURL: URL {
        URL(string: "https://github.com/project-pitchee/Pitchee-iOS/blob/main/LICENSE.txt")!
    }
}

#if DEBUG
private enum SettingsDebugRoute: Hashable {
    case f0
    case passages
    case personalization
}
#endif

private struct SettingsLabel: View {
    let text: Text
    let systemImage: String
    let tint: Color

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color) {
        text = Text(title)
        self.systemImage = systemImage
        self.tint = tint
    }

    init(verbatim title: String, systemImage: String, tint: Color) {
        text = Text(verbatim: title)
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: tint)
            text
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    let tint: Color
    @ScaledMetric(relativeTo: .body) private var scaledSize = 28

    private var size: CGFloat { min(scaledSize, 40) }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.6, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size / 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Compact preview used anywhere a theme is represented in a settings row.
/// It follows the same plain or gradient background as the selected theme.
struct ThemeThumbnail: View {
    let theme: AppThemeOption
    let appearance: GradientAppearance
    private let fixedSize: CGFloat?
    @ScaledMetric(relativeTo: .body) private var size = 56

    init(theme: AppThemeOption, appearance: GradientAppearance, size: CGFloat? = nil) {
        self.theme = theme
        self.appearance = appearance
        fixedSize = size
    }

    private var renderedSize: CGFloat {
        min(fixedSize ?? size, 72)
    }

    var body: some View {
        ThemeBackground(theme: theme, appearance: appearance, intensity: 0.95)
            .frame(width: renderedSize, height: renderedSize)
            .clipShape(RoundedRectangle(cornerRadius: renderedSize * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: renderedSize * 0.22, style: .continuous)
                    .strokeBorder(
                        theme == .pure
                            ? (appearance == .light ? Color.black : .white).opacity(0.14)
                            : .white.opacity(appearance == .light ? 0.45 : 0.24),
                        lineWidth: 1
                    )
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

struct VoicePreferenceSettingsView: View {
    @Binding var selection: VoicePreference

    var body: some View {
        Form {
            Section {
                Picker("settings.voicePreference.sectionTitle", selection: $selection) {
                    ForEach(VoicePreference.allCases) { option in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Text(option.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                        .tag(option)
                        .accessibilityIdentifier("settings.voicePreference.\(option.rawValue)")
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("settings.voicePreference.autosaveNote")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("settings.voicePreference.sectionTitle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacySettingsView: View {
    @ScaledMetric(relativeTo: .body) private var iconSize = 22

    var body: some View {
        Form {
            Section {
                promise("voiceProfile.privacyPromise.onDevice.title", detail: "voiceProfile.privacyPromise.onDevice.description", symbol: "iphone")
                promise("voiceProfile.privacyPromise.recordingUsage.title", detail: "practice.audio.lifetime", symbol: "waveform")
                promise("voiceProfile.privacyPromise.userControl.title", detail: "voiceProfile.privacyPromise.userControl.description", symbol: "slider.horizontal.3")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("voiceProfile.privacyPromise.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func promise(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: min(iconSize, 32)))
                .foregroundStyle(Color.pitcheeAccent)
                .frame(width: min(iconSize, 32), height: min(iconSize, 32))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Debug - About Settings") {
    NavigationStack { SettingsView() }
        .defaultAppStorage(DebugPreviewDefaults.store)
}

#Preview("Debug - Voice Preference Settings") {
    @Previewable @State var selection: VoicePreference = .feminine
    NavigationStack { VoicePreferenceSettingsView(selection: $selection) }
}

#Preview("Debug - Privacy Settings") {
    NavigationStack { PrivacySettingsView() }
}
#endif
