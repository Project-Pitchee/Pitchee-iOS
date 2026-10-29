//
//  ReadingPassagesSettingsView.swift
//  Pitchee
//
//  Port of the Android official/custom reading passage picker.
//

import SwiftUI

struct ReadingPassagesSettingsView: View {
    @AppStorage(AppStorageKey.passageSource) private var source = ReadingPassageSource.official.rawValue
    @AppStorage(AppStorageKey.officialPassageIndex) private var officialIndex = 0
    @AppStorage(AppStorageKey.customPassageText) private var customText = ""
    @State private var draftCustomText = ""
    @State private var didSaveCustomText = false

    var body: some View {
        Form {
            Section {
                Picker(selection: $source) {
                    Text(verbatim: SettingsCopy.text("官方语料", "Official"))
                        .tag(ReadingPassageSource.official.rawValue)
                    Text(verbatim: SettingsCopy.text("自定义", "Custom"))
                        .tag(ReadingPassageSource.custom.rawValue)
                } label: {
                    Text(verbatim: SettingsCopy.text("语料来源", "Passage source"))
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.passages.source")
            }

            if source == ReadingPassageSource.official.rawValue {
                Section {
                    ForEach(Array(ReadingPassageLibrary.official.enumerated()), id: \.element.id) { index, passage in
                        Button {
                            officialIndex = index
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: passage.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(verbatim: passage.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                if officialIndex == index {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.passages.official.\(index)")
                    }
                } header: {
                    Text(verbatim: SettingsCopy.text("选择官方语料", "Choose an official passage"))
                }
            } else {
                Section {
                    TextEditor(text: $draftCustomText)
                        .frame(minHeight: 180)
                        .accessibilityIdentifier("settings.passages.customEditor")

                    Button {
                        customText = draftCustomText.trimmingCharacters(in: .whitespacesAndNewlines)
                        didSaveCustomText = true
                    } label: {
                        Text(verbatim: SettingsCopy.text("保存自定义语料", "Save Custom Passage"))
                    }
                    .disabled(draftCustomText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("settings.passages.saveCustom")
                } header: {
                    Text(verbatim: SettingsCopy.text("自定义语料", "Custom passage"))
                } footer: {
                    Text(verbatim: SettingsCopy.text(
                        "保存后会用于下一次录音。有效语音不足 5 秒时不会显示结果。",
                        "The saved passage is used for the next recording. Results require at least five seconds of valid speech."
                    ))
                }

                if didSaveCustomText || !customText.isEmpty {
                    Section {
                        Text(verbatim: customText)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Text(verbatim: SettingsCopy.text("当前自定义语料", "Current custom passage"))
                    }
                }
            }

            if source == ReadingPassageSource.official.rawValue {
                Section {
                    Text(verbatim: ReadingPassageLibrary.official[safeIndex].text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(verbatim: SettingsCopy.text("预览", "Preview"))
                }
            }
        }
        .navigationTitle(Text(verbatim: SettingsCopy.text("朗读语料", "Reading Passages")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draftCustomText = customText
        }
        .onChange(of: source) { _, newValue in
            if newValue == ReadingPassageSource.custom.rawValue {
                draftCustomText = customText
                didSaveCustomText = false
            }
        }
    }

    private var safeIndex: Int {
        min(max(0, officialIndex), ReadingPassageLibrary.official.count - 1)
    }
}
