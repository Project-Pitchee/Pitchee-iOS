import SwiftData
import SwiftUI

/// Readiness owns its page lifecycle; recording and dashboard snapshots do not
/// trigger the provider. The provider owns daily caching and all input assembly.
@MainActor
struct ReadinessView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var provider: ReadinessProvider?
    @State private var result: ReadinessResult?
    @State private var failed = false

    var body: some View {
        List {
            if let result {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text(result.score, format: .number.precision(.fractionLength(0...2)))
                            .font(.system(.largeTitle, design: .rounded).bold())
                        Spacer()
                        Text(verbatim: result.level)
                            .font(.largeTitle.bold())
                    }
                    .accessibilityElement(children: .combine)

                    if result.isColdStart {
                        Text("readiness.coldStart", tableName: "Readiness")
                            .foregroundStyle(.secondary)
                    } else if let reason = result.reason {
                        Text(LocalizedStringKey(reasonKey(reason)), tableName: "Readiness")
                    }
                } footer: {
                    Text("readiness.refreshTime", tableName: "Readiness")
                }

                Section {
                    DisclosureGroup {
                        ForEach(result.contributions, id: \.factorId) { contribution in
                            HStack {
                                Text(LocalizedStringKey(contributionKey(contribution.factorId)), tableName: "Readiness")
                                Spacer()
                                Text(contribution.contribution, format: .number
                                    .precision(.fractionLength(0...2))
                                    .sign(strategy: .always()))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(contribution.isTriggered ? .primary : .secondary)
                            .accessibilityElement(children: .combine)
                        }
                    } label: {
                        Text("readiness.contributions", tableName: "Readiness")
                    }
                }
            } else if failed {
                Section {
                    Text("common.error.tryAgainLater")
                    Button { refresh() } label: {
                        Text("voiceLibrary.load.retry")
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(Text("readiness.title", tableName: "Readiness"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // Reopening/foregrounding uses the daily cache. Staying on the page
            // crosses Beijing 04:00 without relying on local-midnight notices.
            while !Task.isCancelled {
                refresh()
                let day = ReadinessPracticeDay.start(containing: .now)
                let nextDay = ReadinessPracticeDay.adding(days: 1, to: day)
                do {
                    try await Task.sleep(for: .seconds(max(0.1, nextDay.timeIntervalSinceNow)))
                } catch {
                    return
                }
            }
        }
    }

    private func refresh() {
        if provider == nil { provider = ReadinessProvider(modelContext: modelContext) }
        do {
            result = try provider?.result()
            failed = false
        } catch {
            result = nil
            failed = true
        }
    }

    private func reasonKey(_ reason: ReadinessReason) -> String {
        switch reason {
        case .voiceTired: "readiness.reason.voiceTired"
        case .welcomeBack: "readiness.reason.welcomeBack"
        case .heavyYesterday: "readiness.reason.heavyYesterday"
        }
    }

    private func contributionKey(_ factorID: String) -> String {
        switch factorID {
        case "coldStart": "readiness.initialScore"
        case "decision.4": "readiness.reason.voiceTired"
        case "decision.5": "readiness.restAllowance"
        case "decision.6": "readiness.reason.heavyYesterday"
        case "decision.7": "readiness.reason.welcomeBack"
        default: "readiness.factor.\(factorID)"
        }
    }
}
