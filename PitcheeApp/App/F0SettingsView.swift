//
//  F0SettingsView.swift
//  Pitchee
//
//  Port of the Android F0, chart and performance settings.
//

import SwiftUI

struct F0SettingsView: View {
    @AppStorage(AnalyzerSettingsKey.minF0Hz) private var minF0 = AnalyzerSettings.defaultMinF0Hz
    @AppStorage(AnalyzerSettingsKey.maxF0Hz) private var maxF0 = AnalyzerSettings.defaultMaxF0Hz
    @AppStorage(AnalyzerSettingsKey.minConfidence) private var minConfidence = AnalyzerSettings.defaultMinConfidence
    @AppStorage(AnalyzerSettingsKey.threads) private var threads = AnalyzerSettings.defaultThreads
    @AppStorage(AnalyzerSettingsKey.pitchChartStyle) private var chartStyle = PitchChartStyle.curve.rawValue
    @AppStorage(AnalyzerSettingsKey.pitchGapMilliseconds) private var gapMilliseconds = 200.0
    @AppStorage(AnalyzerSettingsKey.f0SampleRate) private var f0SampleRate = 30

    var body: some View {
        Form {
            Section {
                Picker(selection: $chartStyle) {
                    Text(verbatim: SettingsCopy.text("曲线", "Curve"))
                        .tag(PitchChartStyle.curve.rawValue)
                    Text(verbatim: SettingsCopy.text("圆点", "Dots"))
                        .tag(PitchChartStyle.dots.rawValue)
                } label: {
                    Text(verbatim: SettingsCopy.text("图表样式", "Chart style"))
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.f0.chartStyle")
            } header: {
                Text(verbatim: SettingsCopy.text("图表", "Chart"))
            }

            Section {
                stepperRow(
                    title: SettingsCopy.text("最低 F0", "Minimum F0"),
                    value: "\(Int(minF0)) Hz",
                    binding: minF0Binding,
                    range: AnalyzerSettings.minF0HzRange,
                    step: 5
                )
                .accessibilityIdentifier("settings.f0.minimum")

                stepperRow(
                    title: SettingsCopy.text("最高 F0", "Maximum F0"),
                    value: "\(Int(maxF0)) Hz",
                    binding: maxF0Binding,
                    range: AnalyzerSettings.maxF0HzRange,
                    step: 5
                )
                .accessibilityIdentifier("settings.f0.maximum")

                stepperRow(
                    title: SettingsCopy.text("置信度", "Confidence"),
                    value: minConfidence.formatted(.percent.precision(.fractionLength(0))),
                    binding: $minConfidence,
                    range: AnalyzerSettings.confidenceRange,
                    step: 0.01
                )
                .accessibilityIdentifier("settings.f0.confidence")
            } header: {
                Text(verbatim: SettingsCopy.text("检测", "Detection"))
            } footer: {
                Text(verbatim: SettingsCopy.text(
                    "最低与最高 F0 至少相差 20 Hz。更改会在下一次录音或监测开始时生效。",
                    "Minimum and maximum F0 must differ by at least 20 Hz. Changes apply to the next recording or monitoring session."
                ))
            }

            Section {
                stepperRow(
                    title: SettingsCopy.text("断点灵敏度", "Gap sensitivity"),
                    value: "\(Int(gapMilliseconds)) ms",
                    binding: $gapMilliseconds,
                    range: 50...1_000,
                    step: 10
                )
                .accessibilityIdentifier("settings.f0.gap")

                stepperRow(
                    title: SettingsCopy.text("F0 采样率", "F0 sample rate"),
                    value: "\(f0SampleRate) fps",
                    binding: Binding(
                        get: { Double(f0SampleRate) },
                        set: { f0SampleRate = Int($0.rounded()) }
                    ),
                    range: 20...60,
                    step: 1
                )
                .accessibilityIdentifier("settings.f0.sampleRate")
            } header: {
                Text(verbatim: SettingsCopy.text("显示", "Display"))
            } footer: {
                Text(verbatim: SettingsCopy.text(
                    "断点灵敏度越小，短暂停顿越早切断曲线。",
                    "A shorter gap cuts the curve sooner when the voice pauses."
                ))
            }

            Section {
                stepperRow(
                    title: SettingsCopy.text("分析线程数", "Analysis threads"),
                    value: "\(threads)",
                    binding: Binding(
                        get: { Double(threads) },
                        set: { threads = Int($0.rounded()) }
                    ),
                    range: 1...Double(AnalyzerSettings.maximumThreads),
                    step: 1
                )
                .accessibilityIdentifier("settings.f0.threads")
            } header: {
                Text(verbatim: SettingsCopy.text("性能", "Performance"))
            } footer: {
                Text(verbatim: SettingsCopy.text(
                    "更多线程会增加耗电。",
                    "More threads use more power."
                ))
            }

            Section {
                Button(role: .destructive) {
                    reset()
                } label: {
                    Text(verbatim: SettingsCopy.text("恢复默认值", "Reset to Defaults"))
                }
                .accessibilityIdentifier("settings.f0.reset")
            }
        }
        .navigationTitle(Text(verbatim: SettingsCopy.text("F0 与性能", "F0 & Performance")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeRange()
        }
        .onChange(of: minF0) { _, _ in
            normalizeRange()
        }
    }

    private var minF0Binding: Binding<Double> {
        Binding(
            get: { minF0 },
            set: { newValue in
                let upper = max(
                    AnalyzerSettings.minF0HzRange.lowerBound,
                    maxF0 - AnalyzerSettings.minimumF0GapHz
                )
                minF0 = min(upper, max(AnalyzerSettings.minF0HzRange.lowerBound, newValue))
            }
        )
    }

    private var maxF0Binding: Binding<Double> {
        Binding(
            get: { maxF0 },
            set: { newValue in
                let lower = min(
                    AnalyzerSettings.maxF0HzRange.upperBound,
                    minF0 + AnalyzerSettings.minimumF0GapHz
                )
                maxF0 = max(lower, min(AnalyzerSettings.maxF0HzRange.upperBound, newValue))
            }
        )
    }

    private func stepperRow(
        title: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Stepper(
                SettingsCopy.text("调整", "Adjust"),
                value: binding,
                in: range,
                step: step
            )
            .labelsHidden()
        }
    }

    private func normalizeRange() {
        if maxF0 < minF0 + AnalyzerSettings.minimumF0GapHz {
            maxF0 = min(
                AnalyzerSettings.maxF0HzRange.upperBound,
                minF0 + AnalyzerSettings.minimumF0GapHz
            )
        }
    }

    private func reset() {
        minF0 = AnalyzerSettings.defaultMinF0Hz
        maxF0 = AnalyzerSettings.defaultMaxF0Hz
        minConfidence = AnalyzerSettings.defaultMinConfidence
        threads = AnalyzerSettings.defaultThreads
        chartStyle = PitchChartStyle.curve.rawValue
        gapMilliseconds = 200
        f0SampleRate = 30
    }
}
