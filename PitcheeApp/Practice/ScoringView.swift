//
//  ScoringView.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/6.
//

import SwiftUI
import Combine

/// The original one-take recording flow presented with the realtime pitch
/// monitor's visual language. Analysis and the score report stay unchanged.
struct ScoringView: View {
    let model: AnalysisViewModel
    @Binding var practicePath: [PracticeRoute]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsRecordingError = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize
            ScrollView {
                if wide {
                    HStack(alignment: .top, spacing: 40) {
                        ScoringReadout(model: model)
                            .frame(width: 240, alignment: .leading)
                        ScoringInstrument(model: model,
                                          height: max(180, min(340, geometry.size.height - 180)))
                    }
                    .padding(.vertical, 28)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        ScoringReadout(model: model)
                        ScoringInstrument(model: model,
                                          height: dynamicTypeSize.isAccessibilitySize
                                          ? 240 : max(220, min(360, geometry.size.height * 0.42)))
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
        .navigationTitle("recording.screen.title")
        .navigationBarTitleDisplayMode(.inline)
        .alert("recording.error.startFailed.title", isPresented: $showsRecordingError) {
            Button("common.action.ok", role: .cancel) { model.clearRecordingError() }
        } message: {
            Text(model.recordingError ?? String(localized: "common.error.tryAgainLater"))
        }
        .onAppear {
            model.prepareForRecording()
            syncModelState()
        }
        .onDisappear { model.interruptCapture() }
        .onReceive(model.$state.removeDuplicates()
            .combineLatest(model.$recordingError.removeDuplicates())
            .receive(on: RunLoop.main)) { _ in
            // Only navigation and error changes need this work. Delivery on
            // the next run-loop turn reads committed @Published values.
            syncModelState()
        }
    }

    private func syncModelState() {
        pushAnalysisIfNeeded()
        let shouldShowError = model.recordingError != nil
            && !model.needsAnalysisScreen
            && !model.hasResult
        if shouldShowError != showsRecordingError {
            showsRecordingError = shouldShowError
        }
    }

    private func pushAnalysisIfNeeded() {
        guard model.needsAnalysisScreen, practicePath.last == .scoring else { return }
        practicePath.append(.analysis)
    }
}

/// Each live leaf subscribes to its own input. A clock tick must not rebuild
/// the trace, and a pitch frame must not relayout the passage or controls.
private struct ScoringReadout: View {
    let model: AnalysisViewModel
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize = 58.0
    @State private var currentPitch: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("monitor.pitch.current")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: currentPitch?.formatted(.number.precision(.fractionLength(1))) ?? "—")
                        .font(.system(size: valueSize, weight: .regular, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("monitor.unit.hertz")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scoring.frequency")
            }

            ScoringElapsedTime(model: model)
        }
        .onReceive(model.$livePitchSamples.combineLatest(model.$state)
            .map { samples, state in
                state == .recording ? ScoringPitchSnapshot.currentPitch(in: samples) : nil
            }
            .removeDuplicates()) { currentPitch = $0 }
    }
}

private struct ScoringElapsedTime: View {
    let model: AnalysisViewModel
    @State private var clock = scoringClock(0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("recording.timeline.time.label")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: clock)
                .font(.system(.title3, design: .rounded).monospacedDigit())
            Text("monitor.unit.seconds")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .onReceive(model.$elapsedTime.map(scoringClock).removeDuplicates()) { clock = $0 }
    }
}

private struct ScoringInstrument: View {
    let model: AnalysisViewModel
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScoringPitchChart(model: model)
                .frame(height: height)

            VStack(alignment: .leading, spacing: 12) {
                Text("recording.reference.title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("recording.reference.passage")
                    .font(.body)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("recording.controls.startRecording.subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScoringPitchChart: View {
    let model: AnalysisViewModel
    @State private var snapshot = ScoringPitchSnapshot(samples: [])

    var body: some View {
        ZStack {
            MonitorPitchPlot(samples: snapshot.samples,
                             timeRange: snapshot.timeRange,
                             cursorTime: snapshot.cursorTime)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("monitor.pitch.chart.a11y")
                .accessibilityValue(Text("monitor.chart.range.a11y \(snapshot.timeRange.lowerBound.formatted()) \(snapshot.timeRange.upperBound.formatted()) \(snapshot.cursorTime.formatted())"))

            if snapshot.samples.isEmpty {
                Text("monitor.signal.waitingHint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .systemBackground))
                    .allowsHitTesting(false)
            }
        }
        .onReceive(model.$livePitchSamples) { samples in
            snapshot = ScoringPitchSnapshot(samples: samples)
        }
    }
}

private func scoringClock(_ seconds: TimeInterval) -> String {
    let tenths = Int((max(0, seconds) * 10).rounded())
    return String(format: "%02d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
}
