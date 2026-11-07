//
//  LocalScoreStudyView.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import SwiftUI

struct LocalScoreStudyView: View {
    @ObservedObject var study: LocalScoreStudyStore = .shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Toggle("scoreStudy.settings.enable.label", isOn: Binding(
                    get: { study.state.enabled }, set: { study.setEnabled($0) }
                ))
            } footer: {
                Text("scoreStudy.settings.consent.description")
            }

            if study.storageUnavailable {
                Section {
                    Label("scoreStudy.settings.storageError.message", systemImage: "exclamationmark.shield")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("scoreStudy.settings.comparison.description")
                LabeledContent("scoreStudy.settings.remaining.label") {
                    Text(LocalScoreStudyState.invitationLimit - study.state.usedInvitations, format: .number)
                }
            } footer: {
                Text("scoreStudy.settings.limits.description")
            }

            ForEach(ScoreStudyDirection.allCases, id: \.rawValue) { direction in
                directionSummary(direction)
            }

            Section {
                Button("scoreStudy.settings.clear.action", role: .destructive) { study.clear() }
                    .disabled(study.state.summaries.allSatisfy { $0.screened == 0 })
            } footer: {
                Text("scoreStudy.settings.clear.note")
            }
        }
        .navigationTitle("scoreStudy.settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { study.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { study.refresh() } }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                study.refresh()
            }
        }
    }

    private func directionSummary(_ direction: ScoreStudyDirection) -> some View {
        let summary = study.state.summaries[direction.rawValue]
        return Section {
            count("scoreStudy.summary.screened.label", summary.screened)
            count("scoreStudy.summary.invited.label", summary.invited)
            count("scoreStudy.summary.rated.label", summary.responses[ScoreStudyResponse.rated.rawValue])
            count("scoreStudy.summary.paired.label", summary.paired)
            if summary.paired > 0 {
                count("scoreStudy.summary.candidateCloser.label", summary.candidateCloser)
                count("scoreStudy.summary.baselineCloser.label", summary.baselineCloser)
                count("scoreStudy.summary.equalDistance.label", summary.equalDistance)
            }
            DisclosureGroup("scoreStudy.summary.missing.title") {
                count("scoreStudy.summary.unableToJudge.label", summary.responses[ScoreStudyResponse.unableToJudge.rawValue])
                count("scoreStudy.summary.skipped.label", summary.responses[ScoreStudyResponse.skipped.rawValue])
                count("scoreStudy.summary.timedOut.label", summary.responses[ScoreStudyResponse.timedOut.rawValue])
                count("scoreStudy.summary.feedbackInterrupted.label", summary.responses[ScoreStudyResponse.interrupted.rawValue])
                count("scoreStudy.summary.unavailable.label", summary.analyses[ScoreStudyAnalysis.unavailable.rawValue])
                count("scoreStudy.summary.failed.label", summary.analyses[ScoreStudyAnalysis.failed.rawValue])
                count("scoreStudy.summary.analysisInterrupted.label", summary.analyses[ScoreStudyAnalysis.interrupted.rawValue])
            }
        } header: {
            Text(direction == .feminine ? "scoreStudy.summary.feminine.title" : "scoreStudy.summary.masculine.title")
        } footer: {
            Text("scoreStudy.summary.interpretation.note")
        }
    }

    private func count(_ title: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(title) { Text(value, format: .number) }
    }
}

struct ScoreStudyFeedbackView: View {
    let direction: ScoreStudyDirection
    let submit: (ScoreStudyFeedback) -> Void
    @ObservedObject private var study = LocalScoreStudyStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("scoreStudy.feedback.introduction", systemImage: "hand.raised")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("scoreStudy.feedback.question")
                    .font(.title2.weight(.semibold))
                LabeledContent("scoreStudy.feedback.direction.label") {
                    Text(direction == .feminine ? "voiceProfile.option.feminine.title" : "voiceProfile.option.masculine.title")
                }
                VStack(spacing: 10) {
                    ForEach(ScoreStudyRating.allCases, id: \.rawValue) { rating in
                        let labelKey = "scoreStudy.feedback.rating.\(rating.rawValue).label"
                        Button { submit(.rating(rating)) } label: {
                            Text(LocalizedStringKey(labelKey))
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("scoreStudy.rating.\(rating.rawValue)")
                    }
                }
                Button("scoreStudy.feedback.unable.action") { submit(.unableToJudge) }
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("scoreStudy.feedback.skip.action") { submit(.skipped) }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("scoreStudy.skip")
                Text("scoreStudy.feedback.privacy.note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .onAppear {
            if !study.state.enabled || study.storageUnavailable { submit(.skipped) }
        }
        .onChange(of: study.state.enabled) { _, enabled in if !enabled { submit(.skipped) } }
        .onChange(of: study.storageUnavailable) { _, failed in if failed { submit(.skipped) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { submit(.skipped) } }
        .onDisappear { submit(.skipped) }
    }
}
