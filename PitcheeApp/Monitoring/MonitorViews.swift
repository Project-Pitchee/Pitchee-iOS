//
//  MonitorViews.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import SwiftUI

struct SpectrumMonitorView: View {
    @State private var model = makeMonitorModel(kind: .spectrum)
    var body: some View { MonitorPage(model: model) }
}

struct PitchMonitorView: View {
    @State private var model = makeMonitorModel(kind: .pitch)
    var body: some View { MonitorPage(model: model) }
}

@MainActor
private func makeMonitorModel(kind: MonitorKind) -> MonitorViewModel {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-monitor-preview-data") {
        return .preview(kind: kind)
    }
    #endif
    return MonitorViewModel(kind: kind)
}

/// The destination renders the instrument; its controls are presented by the tab view.
private struct MonitorPage: View {
    let model: MonitorViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.monitorAccessoryState) private var accessoryState
    @State private var showsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonitorReadout(model: model)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            MonitorInstrument(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            MonitorTimelineControl(model: model)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle(LocalizedStringKey(model.kind.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MonitorWindowMenu(model: model)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("monitor.action.info", systemImage: "info.circle") { showsHelp = true }
                    .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showsHelp) { MonitorHelpView(kind: model.kind) }
        .alert("monitor.error.title", isPresented: Binding(
            get: { !showsHelp && model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("common.action.ok", role: .cancel) { model.clearError() }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
        .onAppear { accessoryState?.show(model) }
        .onDisappear {
            accessoryState?.hide(model)
            model.stopForLeaving()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .inactive: model.handleSceneInactive()
            case .background: model.pause()
            case .active: model.handleSceneActive()
            @unknown default: model.handleSceneInactive()
            }
        }
    }
}

private struct MonitorReadout: View {
    let model: MonitorViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var lastPrimaryFrequency = 0.0
    @State private var lastRangeLow = 0.0
    @State private var lastRangeHigh = 0.0
    @State private var lastSpectrumLevel = 0.0

    private static let valueAnimation = Animation.easeOut(duration: 0.06)

    private var secondaryTitle: LocalizedStringKey {
        model.kind == .pitch ? "monitor.pitch.windowRange" : "monitor.spectrum.peakLevel"
    }

    private var secondaryUnit: LocalizedStringKey {
        model.kind == .pitch ? "monitor.unit.hertz" : "monitor.unit.dbfs"
    }

    private var primaryReading: some View {
        reading(
            title: model.kind == .spectrum ? "monitor.spectrum.peak" : "monitor.pitch.current",
            unit: "monitor.unit.hertz"
        ) {
            DampedNumericText(
                value: model.currentFrequencyHz ?? lastPrimaryFrequency,
                hasValue: model.currentFrequencyHz != nil,
                fractionDigits: 1,
                size: 34
            )
            .animation(Self.valueAnimation, value: model.currentFrequencyHz ?? lastPrimaryFrequency)
        }
    }

    private var secondaryReading: some View {
        reading(
            title: secondaryTitle,
            unit: secondaryUnit
        ) {
            if model.kind == .spectrum {
                DampedNumericText(
                    value: Double(model.currentSpectrumPeak?.amplitudeDBFS ?? Float(lastSpectrumLevel)),
                    hasValue: model.currentSpectrumPeak != nil,
                    fractionDigits: 1,
                    size: 22
                )
                .animation(
                    Self.valueAnimation,
                    value: Double(model.currentSpectrumPeak?.amplitudeDBFS ?? Float(lastSpectrumLevel))
                )
            } else if let range = model.visiblePitchRange {
                HStack(spacing: 0) {
                    DampedNumericText(
                        value: range.lowerBound,
                        hasValue: true,
                        fractionDigits: 0,
                        size: 22
                    )
                    Text(verbatim: "–")
                        .font(.system(size: 22, weight: .regular, design: .rounded).monospacedDigit())
                    DampedNumericText(
                        value: range.upperBound,
                        hasValue: true,
                        fractionDigits: 0,
                        size: 22
                    )
                }
                .animation(Self.valueAnimation, value: range)
            } else {
                DampedNumericText(
                    value: lastRangeHigh,
                    hasValue: false,
                    fractionDigits: 0,
                    size: 22
                )
            }
        }
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 28))
        layout {
            primaryReading
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 154, alignment: .leading)
            .accessibilityIdentifier("monitor.frequency")

            secondaryReading
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 124, alignment: .leading)

            Spacer(minLength: 0)
        }
        .onChange(of: model.currentFrequencyHz, initial: true) { _, value in
            if let value { lastPrimaryFrequency = value }
        }
        .onChange(of: model.visiblePitchRange, initial: true) { _, range in
            guard let range else { return }
            lastRangeLow = range.lowerBound
            lastRangeHigh = range.upperBound
        }
        .onChange(of: model.currentSpectrumPeak?.amplitudeDBFS, initial: true) { _, level in
            if let level { lastSpectrumLevel = Double(level) }
        }
    }

    private func reading<Value: View>(
        title: LocalizedStringKey,
        unit: LocalizedStringKey,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                value()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DampedNumericText: View, Animatable {
    var value: Double
    let hasValue: Bool
    let fractionDigits: Int
    let size: CGFloat

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: hasValue
            ? value.formatted(.number.precision(.fractionLength(fractionDigits)))
            : "—")
            .font(.system(size: size, weight: .regular, design: .rounded).monospacedDigit())
            .contentTransition(.identity)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }
}

private struct MonitorInstrument: View {
    let model: MonitorViewModel
    @AppStorage(AnalyzerSettingsKey.minF0Hz) private var minF0Hz = AnalyzerSettings.defaultMinF0Hz
    @AppStorage(AnalyzerSettingsKey.maxF0Hz) private var maxF0Hz = AnalyzerSettings.defaultMaxF0Hz

    private var pitchFrequencyRange: ClosedRange<Double> {
        AnalyzerSettings.realtimeChartRange(minF0Hz: minF0Hz, maxF0Hz: maxF0Hz)
    }

    private var emptyKey: String? {
        if model.isBusy { return "monitor.status.preparing" }
        if !model.hasAudio { return model.state == .live ? "monitor.signal.waiting" : "monitor.signal.waitingHint" }
        if model.kind == .pitch && model.visiblePitchRange == nil {
            return "monitor.signal.unvoiced"
        }
        return nil
    }

    var body: some View {
        ZStack {
            Group {
                switch model.kind {
                case .spectrum:
                    MonitorSpectrumPlot(frame: model.currentSpectrum)
                case .pitch:
                    MonitorPitchPlot(samples: model.visiblePitchSamples,
                                     timeRange: model.visibleRange,
                                     cursorTime: model.cursorTime,
                                     frequencyRange: pitchFrequencyRange,
                                     averagePitch: model.visibleAveragePitchHz)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LocalizedStringKey(
                model.kind == .spectrum ? "monitor.spectrum.chart.a11y" : "monitor.pitch.chart.a11y"
            ))
            .accessibilityValue(Text("monitor.chart.range.a11y \(monitorSeconds(model.visibleRange.lowerBound)) \(monitorSeconds(model.visibleRange.upperBound)) \(monitorSeconds(model.cursorTime))"))

            if let emptyKey {
                Text(LocalizedStringKey(emptyKey))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, 28)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct MonitorTimelineControl: View {
    let model: MonitorViewModel

    private var sliderRange: ClosedRange<Double> {
        model.availableRange.lowerBound...max(model.availableRange.lowerBound + 0.001,
                                             model.availableRange.upperBound)
    }
    var body: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(
                get: { min(sliderRange.upperBound, max(sliderRange.lowerBound, model.cursorTime)) },
                set: { model.seek(to: $0) }
            ), in: sliderRange) {
                Text("monitor.browse.title")
            } onEditingChanged: { editing in
                if editing { model.beginSeeking() }
            }
            .tint(Color.pitcheeAccent)
            .disabled(model.isBusy || !model.hasAudio)
            .accessibilityValue(Text("monitor.position.a11y \(monitorSeconds(model.cursorTime))"))
            .accessibilityHint("monitor.browse.hint")
            .accessibilityIdentifier("monitor.seek")
        }
    }
}

private struct MonitorWindowMenu: View {
    let model: MonitorViewModel

    private var selectedWindowLabel: String {
        "\(Int(model.windowDuration)) s"
    }

    var body: some View {
        Menu {
            Picker("monitor.window.title", selection: Binding(
                get: { model.windowDuration }, set: { model.setWindowDuration($0) }
            )) {
                ForEach(MonitorViewModel.windowDurations, id: \.self) { seconds in
                    Text(verbatim: "\(Int(seconds)) s").tag(seconds)
                }
            }
        } label: {
            Label {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("monitor.window.title")
                        .font(.caption2)
                    Text(selectedWindowLabel)
                        .font(.subheadline.monospacedDigit())
                }
            } icon: {
                Image(systemName: "clock")
            }
        }
        .disabled(model.isBusy)
        .accessibilityLabel("monitor.window.title")
        .accessibilityValue(Text(verbatim: selectedWindowLabel))
        .accessibilityIdentifier("monitor.windowDuration")
    }
}

private struct MonitorHelpView: View {
    let kind: MonitorKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Label(LocalizedStringKey(kind == .spectrum ? "monitor.spectrum.readoutHint" : "monitor.pitch.readoutHint"),
                      systemImage: kind.symbol)
                Label("monitor.replay.note", systemImage: "play.circle")
                Label("monitor.browse.hint", systemImage: "gobackward.5")
                Label("monitor.retention.note", systemImage: "clock.arrow.circlepath")
            }
            .font(.subheadline)
            .navigationTitle("monitor.action.info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.action.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private func monitorSeconds(_ seconds: Double) -> String {
    max(0, seconds).formatted(.number.precision(.fractionLength(1)))
}

private func monitorClock(_ seconds: Double) -> String {
    let tenths = Int((max(0, seconds) * 10).rounded())
    return String(format: "%02d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
}

#if DEBUG
/// Opt-in simulator review routes keep visual checks independent of navigation and microphone access.
struct MonitorReviewModifier: ViewModifier {
    private let arguments = ProcessInfo.processInfo.arguments

    func body(content: Content) -> some View {
        if arguments.contains("-monitor-review-pitch") || arguments.contains("-monitor-review-spectrum") {
            content
                .tint(Color.pitcheeAccent)
                .preferredColorScheme(arguments.contains("-monitor-review-dark") ? .dark : .light)
                .environment(\.dynamicTypeSize, arguments.contains("-monitor-review-large-text") ? .accessibility2 : .large)
        } else {
            content
        }
    }
}

private struct MonitorScreenPreview: View {
    let model: MonitorViewModel
    @State private var accessoryState = MonitorAccessoryState()

    var body: some View {
        TabView {
            NavigationStack { MonitorPage(model: model) }
                .tabItem { Label("practice.hub.tab", systemImage: "figure.mind.and.body") }
        }
        .modifier(TabBarAccessory(isVisible: accessoryState.model != nil) {
            if let model = accessoryState.model { MonitorAccessoryContent(model: model) }
        })
        .environment(\.monitorAccessoryState, accessoryState)
        .tint(Color.pitcheeAccent)
    }
}

#Preview("Pitch · Ready") {
    MonitorScreenPreview(model: MonitorViewModel(kind: .pitch))
}
#Preview("Pitch · Paused") {
    MonitorScreenPreview(model: .preview(kind: .pitch))
}
#Preview("Spectrum · Paused") {
    MonitorScreenPreview(model: .preview(kind: .spectrum))
}
#Preview("Spectrum · Dark") {
    MonitorScreenPreview(model: .preview(kind: .spectrum))
        .preferredColorScheme(.dark)
}
#Preview("Pitch · Large Text") {
    MonitorScreenPreview(model: .preview(kind: .pitch))
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
