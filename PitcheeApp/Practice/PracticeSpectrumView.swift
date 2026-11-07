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
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PracticeSpectrumInstrument(model: model)
                        .frame(height: max(300, min(640, geometry.size.height - 230)))
                    MonitorSpectrogramLegend()
                    MonitorSpectrumReadout(model: model)
                    if model.hasAudio {
                        MonitorTimelineControl(model: model)
                    }
                    Text("monitor.spectrogram.readoutHint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("practice.spectrum.title")
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
        .sheet(isPresented: $showsHelp) { PracticeSpectrumHelp() }
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

struct PracticeSpectrumInstrument: View {
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
