//
//  LocalDiagnosticsView.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import SwiftUI

struct LocalDiagnosticsView: View {
    @ObservedObject var diagnostics: LocalDiagnosticsStore = .shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Toggle("settings.localDiagnostics.enable.label", isOn: Binding(
                    get: { diagnostics.state.enabled },
                    set: { diagnostics.setEnabled($0) }
                ))
            } footer: {
                Text("settings.localDiagnostics.privacy.description")
            }

            if diagnostics.storageUnavailable {
                Section {
                    Label("settings.localDiagnostics.storageError.message", systemImage: "exclamationmark.shield")
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("settings.localDiagnostics.attempts.label") {
                    Text(diagnostics.state.summary.attempts, format: .number)
                }
                LabeledContent("settings.localDiagnostics.remaining.label") {
                    Text(LocalDiagnosticState.attemptLimit - diagnostics.state.usedAttempts, format: .number)
                }
                if diagnostics.state.summary.pending > 0 {
                    Label("settings.localDiagnostics.pending.label", systemImage: "hourglass")
                }
            } header: {
                Text("settings.localDiagnostics.summary.title")
            } footer: {
                Text("settings.localDiagnostics.retention.description")
            }

            if diagnostics.state.summary.completed > 0 {
                histogram("settings.localDiagnostics.outcome.title", counts: diagnostics.state.summary.outcomes,
                          keys: ["success", "noSpeech", "unreadableAudio", "modelUnavailable", "analysisFailed",
                                 "historySaveFailed", "cancelled", "interrupted"], category: "outcome")
                histogram("settings.localDiagnostics.duration.title", counts: diagnostics.state.summary.durations,
                          keys: ["under5", "from5To10", "from10To20", "from20To60", "atLeast60", "unavailable"], category: "duration")
                histogram("settings.localDiagnostics.speechRatio.title", counts: diagnostics.state.summary.speechRatios,
                          keys: ["underQuarter", "quarterToHalf", "halfToThreeQuarters", "atLeastThreeQuarters", "unavailable"], category: "speechRatio")
                histogram("settings.localDiagnostics.quality.title", counts: diagnostics.state.summary.qualities,
                          keys: ["lowLevel", "lowSeparation", "sufficientSeparation", "unavailable"], category: "quality")
                histogram("settings.localDiagnostics.latency.title", counts: diagnostics.state.summary.latencies,
                          keys: ["under1", "from1To3", "from3To10", "from10To30", "atLeast30", "unavailable"], category: "latency")
            }

            Section {
                Button("settings.localDiagnostics.clear.action", role: .destructive) {
                    diagnostics.clearSummary()
                }
                .disabled(diagnostics.state.summary.attempts == 0)
            } footer: {
                Text("settings.localDiagnostics.clear.note")
            }

            Section {
                DisclosureGroup("settings.localDiagnostics.version.title") {
                    LabeledContent("settings.localDiagnostics.version.app.label") {
                        Text(verbatim: "\(diagnostics.state.configuration.appVersion) (\(diagnostics.state.configuration.appBuild))")
                    }
                    Text("settings.localDiagnostics.version.manifest.label")
                    Text(verbatim: diagnostics.state.configuration.manifestSHA256)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("settings.localDiagnostics.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { diagnostics.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { diagnostics.refresh() }
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                diagnostics.refresh()
            }
        }
    }

    private func histogram(_ title: LocalizedStringKey, counts: [Int], keys: [String], category: String) -> some View {
        Section {
            ForEach(keys.indices, id: \.self) { index in
                let labelKey = "settings.localDiagnostics.\(category).\(keys[index]).label"
                LabeledContent(LocalizedStringKey(labelKey)) {
                    Text(counts[index], format: .number)
                }
            }
        } header: {
            Text(title)
        }
    }
}
