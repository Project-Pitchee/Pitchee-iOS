//
//  PracticeSpectrumView.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/6.
//

import SwiftUI

/// A separate Practice Hub instrument. The existing live spectrum and pitch
/// destinations keep their own views, sessions, and rendering behavior.
struct PracticeSpectrumView: View {
    @State private var model = makePracticeSpectrumModel()
    @State private var showsHelp = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.monitorAccessoryState) private var accessoryState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PracticeSpectrumReadout(model: model)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            PracticeSpectrumInstrument(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            MonitorSpectrogramLegend()
                .padding(.horizontal, 16)
                .padding(.top, 8)
            if model.hasAudio {
                PracticeSpectrumTimeline(model: model)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("practice.spectrum.title")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PracticeSpectrumSettings(model: model)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("monitor.action.info", systemImage: "info.circle") { showsHelp = true }
                    .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showsHelp) { PracticeSpectrumHelp() }
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
            case .active: model.handleSceneActive()
            case .inactive: model.handleSceneInactive()
            case .background: model.pause()
            @unknown default: model.handleSceneInactive()
            }
        }
    }
}

@MainActor
private func makePracticeSpectrumModel() -> MonitorViewModel {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-monitor-preview-data") {
        return .preview(kind: .spectrum, includesSpectrogram: true)
    }
    #endif
    return MonitorViewModel(kind: .spectrum, includesSpectrogram: true)
}

private struct PracticeSpectrumReadout: View {
    let model: MonitorViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 24))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                Text("monitor.spectrum.peak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: model.currentFrequencyHz.map {
                        $0.formatted(.number.precision(.fractionLength(1)))
                    } ?? "—")
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    Text("monitor.unit.hertz")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("practice.spectrum.frequency")
            VStack(alignment: .leading, spacing: 6) {
                Text("monitor.spectrum.peakLevel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: model.currentSpectrumPeak.map {
                        Double($0.amplitudeDBFS).formatted(.number.precision(.fractionLength(1)))
                    } ?? "—")
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    Text("monitor.unit.dbfs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct PracticeSpectrumInstrument: View {
    let model: MonitorViewModel

    private var emptyKey: String? {
        if model.isBusy { return "monitor.status.preparing" }
        if !model.hasAudio {
            return model.state == .live ? "monitor.signal.waiting" : "monitor.signal.waitingHint"
        }
        return nil
    }

    var body: some View {
        MonitorSpectrogramPlot(columns: model.visibleSpectrogramColumns,
                               timeRange: model.spectrogramTimeRange,
                               cursorTime: model.cursorTime)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("monitor.spectrogram.chart.a11y")
            .accessibilityValue(Text("monitor.chart.range.a11y \(spectrumSeconds(model.spectrogramTimeRange.lowerBound)) \(spectrumSeconds(model.spectrogramTimeRange.upperBound)) \(spectrumSeconds(model.cursorTime))"))
            .overlay {
                if let emptyKey {
                    Text(LocalizedStringKey(emptyKey))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.black.opacity(0.3), in: .rect(cornerRadius: 8))
                        .padding(.horizontal, 60)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct PracticeSpectrumTimeline: View {
    let model: MonitorViewModel

    var body: some View {
        let range = model.availableRange.lowerBound...max(model.availableRange.lowerBound + 0.001,
                                                         model.availableRange.upperBound)
        VStack(spacing: 0) {
            Slider(value: Binding(
                get: { min(range.upperBound, max(range.lowerBound, model.cursorTime)) },
                set: { model.seek(to: $0) }
            ), in: range) {
                Text("monitor.browse.title")
            } onEditingChanged: { editing in
                if editing { model.pause() }
            }
            .disabled(model.isBusy)
            .accessibilityValue(Text("monitor.position.a11y \(spectrumSeconds(model.cursorTime))"))
            .accessibilityHint("monitor.browse.hint")
            .accessibilityIdentifier("practice.spectrum.seek")
            HStack {
                Text(verbatim: spectrumSeconds(range.lowerBound))
                Spacer()
                Text(verbatim: spectrumSeconds(range.upperBound))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

private struct PracticeSpectrumSettings: View {
    let model: MonitorViewModel

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
            Label("monitor.spectrum.settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .disabled(model.isBusy)
        .accessibilityIdentifier("practice.spectrum.settings")
    }
}

private struct PracticeSpectrumHelp: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Label("monitor.spectrogram.readoutHint", systemImage: "waveform")
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

private func spectrumSeconds(_ seconds: TimeInterval) -> String {
    max(0, seconds).formatted(.number.precision(.fractionLength(1)))
}

#Preview("Spectrum · Ready") {
    NavigationStack { PracticeSpectrumView() }
}
