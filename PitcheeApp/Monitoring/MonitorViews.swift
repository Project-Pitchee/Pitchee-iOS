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
    if ScreenshotMode.isEnabled || ProcessInfo.processInfo.arguments.contains("-monitor-preview-data") {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsHelp = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize
            ScrollView {
                if wide && model.kind == .pitch {
                    HStack(alignment: .top, spacing: 40) {
                        MonitorReadout(model: model)
                            .frame(width: 240, alignment: .leading)
                        MonitorInstrument(model: model, height: max(180, min(340, geometry.size.height - 180)))
                    }
                    .padding(.vertical, 28)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        if model.kind == .pitch { MonitorReadout(model: model) }
                        MonitorInstrument(model: model, height: dynamicTypeSize.isAccessibilitySize
                                          ? 240 : model.kind == .spectrum
                                          ? max(280, geometry.size.height - 220)
                                          : max(220, min(360, geometry.size.height * 0.42)))
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .padding(.horizontal, wide ? 32 : 24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle(LocalizedStringKey(model.kind.titleKey))
        .navigationBarTitleDisplayMode(.inline)
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
            get: { !showsHelp && accessoryState?.isExpanded != true && model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("common.action.ok", role: .cancel) { model.clearError() }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
        .onAppear { accessoryState?.show(model) }
        .onDisappear {
            guard accessoryState?.isExpanded != true else { return }
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
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize = 58.0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 20))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    Text("monitor.pitch.retainedRange")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: monitorPitchRange(model.retainedPitchRange))
                            .font(.system(size: valueSize, weight: .regular, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("monitor.unit.hertz")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("monitor.retainedRange")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("monitor.pitch.current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: model.currentPitchHz.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                            .font(.system(.title3, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                        Text("monitor.unit.hertz")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("monitor.frequency")
            }
        }
    }
}

struct MonitorSpectrumReadout: View {
    let model: MonitorViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 24))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text("monitor.spectrum.peak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: model.smoothedSpectrumPeak.map {
                        $0.frequencyHz.formatted(.number.precision(.fractionLength(1)))
                    } ?? "—")
                    Text("monitor.unit.hertz").foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("monitor.frequency")
            VStack(alignment: .leading, spacing: 4) {
                Text("monitor.spectrum.peakLevel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: model.smoothedSpectrumPeak.map {
                        Double($0.amplitudeDBFS).formatted(.number.precision(.fractionLength(1)))
                    } ?? "—")
                    Text("monitor.unit.dbfs").foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .font(.system(.subheadline, design: .rounded).monospacedDigit())
    }
}

struct MonitorInstrument: View {
    let model: MonitorViewModel
    let height: CGFloat

    private var emptyKey: String? {
        if model.isBusy { return "monitor.status.preparing" }
        if !model.hasAudio { return model.state == .live ? "monitor.signal.waiting" : "monitor.signal.waitingHint" }
        if model.kind == .pitch && model.visiblePitchRange == nil {
            return "monitor.signal.unvoiced"
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                Group {
                    switch model.kind {
                    case .spectrum:
                        MonitorSpectrumPlot(frame: model.currentSpectrum)
                    case .pitch:
                        MonitorPitchPlot(samples: model.visiblePitchSamples,
                                         timeRange: model.visibleRange,
                                         cursorTime: model.cursorTime)
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
                        .background(Color(uiColor: .systemBackground))
                        .padding(.leading, 28)
                        .padding(.horizontal, 28)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: height)

            if model.kind == .spectrum {
                MonitorSpectrumReadout(model: model)
            } else {
                HStack {
                    Text("monitor.pitch.windowRange")
                    Text(verbatim: monitorPitchRange(model.visiblePitchRange))
                    Text("monitor.unit.hertz")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            if model.hasAudio {
                MonitorTimelineControl(model: model)
            }
            Text(LocalizedStringKey(model.kind == .pitch ? "monitor.pitch.readoutHint" : "monitor.spectrum.readoutHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MonitorTimelineControl: View {
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
                if editing { model.pause() }
            }
            .tint(Color.pitcheeAccent)
            .disabled(model.isBusy)
            .accessibilityValue(Text("monitor.position.a11y \(monitorSeconds(model.cursorTime))"))
            .accessibilityHint("monitor.browse.hint")
            .accessibilityIdentifier("monitor.seek")
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: monitorClock(model.availableRange.lowerBound))
                Spacer(minLength: 12)
                Text(verbatim: monitorClock(model.availableRange.upperBound))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Button("monitor.action.replayWindow", systemImage: "arrow.counterclockwise") {
                model.replayWindow()
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .disabled(model.isBusy)
            .accessibilityIdentifier("monitor.replayWindow")
        }
    }
}

struct MonitorWindowMenu: View {
    let model: MonitorViewModel

    private var selectedWindowLabel: Text {
        Text("monitor.time.seconds \(model.windowDuration.formatted(.number.precision(.fractionLength(0))))")
    }

    var body: some View {
        Menu {
            Picker("monitor.window.title", selection: Binding(
                get: { model.windowDuration }, set: { model.setWindowDuration($0) }
            )) {
                ForEach(MonitorViewModel.windowDurations, id: \.self) { duration in
                    Text("monitor.time.seconds \(duration.formatted(.number.precision(.fractionLength(0))))")
                        .tag(duration)
                }
            }
        } label: {
            Label {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("monitor.window.title")
                        .font(.caption2)
                    selectedWindowLabel
                        .font(.subheadline.monospacedDigit())
                }
            } icon: {
                Image(systemName: "clock")
            }
        }
        .disabled(model.isBusy)
        .accessibilityLabel("monitor.window.title")
        .accessibilityValue(selectedWindowLabel)
        .accessibilityIdentifier("monitor.windowDuration")
    }
}

/// The same model keeps the selected window, cursor and audio session through presentation.
struct MonitorExpandedView<Content: View>: View {
    let model: MonitorViewModel
    let titleKey: String
    @ViewBuilder let content: (CGFloat) -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content(max(180, geometry.size.height - 200))
                    .padding(20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Button { dismiss() } label: {
                    Capsule()
                        .fill(.secondary)
                        .frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("monitor.action.collapse")
                .accessibilityIdentifier("monitor.collapse")

                HStack(spacing: 20) {
                    Text(LocalizedStringKey(titleKey))
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    MonitorWindowMenu(model: model)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom) {
            MonitorAccessoryContent(model: model, titleKey: titleKey)
                .background(.bar)
        }
        .alert("monitor.error.title", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("common.action.ok", role: .cancel) { model.clearError() }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
        .accessibilityAction(.escape) { dismiss() }
        .tint(Color.pitcheeAccent)
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

private func monitorPitchRange(_ range: ClosedRange<Double>?) -> String {
    guard let range else { return "—" }
    return "\(range.lowerBound.formatted(.number.precision(.fractionLength(0))))–\(range.upperBound.formatted(.number.precision(.fractionLength(0))))"
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
    @Namespace private var transition

    var body: some View {
        TabView {
            NavigationStack { MonitorPage(model: model) }
                .tabItem { Label("practice.hub.tab", systemImage: "figure.mind.and.body") }
        }
        .modifier(TabBarAccessory(isVisible: accessoryState.model != nil) {
            if let model = accessoryState.model {
                MonitorAccessoryContent(model: model) { accessoryState.isExpanded = true }
                    .monitorTransitionSource(in: transition)
            }
        })
        .environment(\.monitorAccessoryState, accessoryState)
        .fullScreenCover(isPresented: $accessoryState.isExpanded) {
            MonitorExpandedView(model: model, titleKey: model.kind.titleKey) { height in
                MonitorInstrument(model: model, height: height)
            }
            .monitorPlayerTransition(in: transition)
        }
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
