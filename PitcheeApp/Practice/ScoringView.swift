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
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            ScoringPitchBackground(model: model)
                .opacity(0.16)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            GeometryReader { geometry in
                let wide = geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize
                ScrollView {
                    if wide {
                        HStack(alignment: .top, spacing: 40) {
                            ScoringReadout(model: model)
                                .frame(width: 240, alignment: .leading)
                            ScoringPassage()
                        }
                        .padding(.vertical, 28)
                    } else {
                        VStack(alignment: .leading, spacing: 28) {
                            ScoringReadout(model: model)
                            ScoringPassage()
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
        }
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
    @State private var clock = RecordingClock.string(0)

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
        .onReceive(model.$elapsedTime.map(RecordingClock.string).removeDuplicates()) { clock = $0 }
    }
}

private struct ScoringPassage: View {
    @AppStorage(AppStorageKey.passageSource) private var passageSource = ReadingPassageSource.official.rawValue
    @AppStorage(AppStorageKey.officialPassageIndex) private var passageIndex = 0
    @AppStorage(AppStorageKey.customPassageText) private var customPassageText = ""

    private var passage: ReadingPassage {
        ReadingPassageLibrary.selected(
            source: passageSource,
            officialIndex: passageIndex,
            customText: customPassageText
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: passage.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: passage.text)
                .font(.body)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScoringPitchBackground: View {
    private static let visibleSeconds: TimeInterval = 3
    private static let displayLag: TimeInterval = 0.08
    private static let frequencyRange: ClosedRange<Double> = 120...300

    let model: AnalysisViewModel
    @State private var snapshot = ScoringPitchSnapshot(samples: [])
    @State private var snapshotUpdatedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(snapshotUpdatedAt))
            let cursorTime = min(
                snapshot.cursorTime,
                max(0, snapshot.cursorTime - Self.displayLag + elapsed)
            )
            let end = max(Self.visibleSeconds, cursorTime)

            MonitorPitchPlot(
                samples: snapshot.samples,
                timeRange: (end - Self.visibleSeconds)...end,
                cursorTime: cursorTime,
                frequencyRange: Self.frequencyRange
            )
            .accessibilityHidden(true)
        }
        .onReceive(model.$livePitchSamples) { samples in
            snapshot = ScoringPitchSnapshot(samples: samples)
            snapshotUpdatedAt = Date()
        }
    }
}
