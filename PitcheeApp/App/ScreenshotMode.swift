#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Opt-in fixtures for XCUITest. Release archives do not contain this code.
/// The store and defaults are isolated from a person's recordings and preferences.
enum ScreenshotMode {
    enum Screen: String, CaseIterable {
        case home, monitor, insights, articles, history
    }

    enum DashboardScenario: String, CaseIterable {
        case single, few, four, fortnight, twoMonths, long, gap, filteredSingle

        var dayOffsets: [Int] {
            switch self {
            case .single: [0]
            case .few: [57, 36, 0]
            case .four: [3, 2, 1, 0]
            case .fortnight: Array((0..<14).reversed())
            case .twoMonths: Array(stride(from: 59, through: 0, by: -2)) + [0]
            case .long: Array(stride(from: 179, through: 0, by: -2)) + [0]
            case .gap: [100, 50, 36, 5, 0]
            case .filteredSingle: [45, 25, 14, 0]
            }
        }
    }

    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-UITestMode")
    static let now = Date(timeIntervalSince1970: 1_793_534_400) // 2026-11-01 12:00 UTC
    static let dashboardScenario: DashboardScenario? = {
        guard isEnabled else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-DashboardScenario") else { return nil }
        guard arguments.indices.contains(index + 1),
              let scenario = DashboardScenario(rawValue: arguments[index + 1]) else {
            preconditionFailure("-DashboardScenario requires a valid dashboard scenario")
        }
        return scenario
    }()
    static let screen: Screen? = {
        guard isEnabled else { return nil }
        if dashboardScenario != nil { return .home }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ScreenshotScreen"),
              arguments.indices.contains(index + 1),
              let screen = Screen(rawValue: arguments[index + 1]) else {
            preconditionFailure("-UITestMode requires a valid -ScreenshotScreen")
        }
        return screen
    }()

    static let defaults: UserDefaults = {
        let suite = "com.lvyzhan.Pitchee.screenshots"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(OnboardingFlow.currentVersion, forKey: AppStorageKey.onboardingCompletedVersion)
        defaults.set(VoicePreference.feminine.rawValue, forKey: AppStorageKey.voicePreference)
        defaults.set(AppThemeOption.twilt.rawValue, forKey: AppStorageKey.themeSelection)
        if let dashboardScenario {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let keys = dashboardScenario.dayOffsets.map { offset in
                let date = now.addingTimeInterval(-Double(offset) * 86_400)
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
            }
            defaults.set(keys.joined(separator: ","), forKey: AppStorageKey.openedDateKeys)
        } else {
            defaults.set((26...31).map { "2026-10-\($0)" }.joined(separator: ",") + ",2026-11-1",
                         forKey: AppStorageKey.openedDateKeys)
        }
        return defaults
    }()

    static func makeContainer() throws -> ModelContainer {
        _ = screen // Validate launch arguments before displaying any UI.
        UIView.setAnimationsEnabled(false)
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        URLProtocol.registerClass(ScreenshotNetworkBlocker.self)
        let container = try ModelContainer(
            for: RecordingAssessment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        if let dashboardScenario {
            for (index, offset) in dashboardScenario.dayOffsets.enumerated() {
                try insertRecording(
                    index: index,
                    recordedAt: now.addingTimeInterval(-Double(offset) * 86_400),
                    result: DebugPreviewData.history[index % DebugPreviewData.history.count],
                    into: container
                )
            }
        } else {
            // Fixed IDs, dates and measurements: no random generator or wall clock.
            // Two short exercises per day illustrate a week of practice, including variation.
            for index in 0..<14 {
                try insertRecording(
                    index: index,
                    recordedAt: now.addingTimeInterval(-Double(6 - index / 2) * 86_400 - Double(index % 2) * 1_800),
                    result: DebugPreviewData.history[min(index / 5, DebugPreviewData.history.count - 1)],
                    into: container
                )
            }
        }
        try container.mainContext.save()
        return container
    }

    private static func insertRecording(
        index: Int, recordedAt: Date, result: PitcheeAnalysisResult, into container: ModelContainer
    ) throws {
        let assessment = try RecordingAssessment(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            recordedAt: recordedAt,
            result: result,
            preference: .feminine,
            quality: RecordingQuality(speechSeconds: 10, speechDBFS: -27,
                                      backgroundDBFS: -40, clippedFraction: 0)
        )
        container.mainContext.insert(assessment)
    }
}

/// Bundle-backed article loading remains available; outbound HTTP is rejected.
nonisolated private final class ScreenshotNetworkBlocker: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

struct ScreenshotRootView: View {
    @ObservedObject private var library = VoiceTrainingLibraryLoader.shared

    var body: some View {
        ContentView()
            .defaultAppStorage(ScreenshotMode.defaults)
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .environment(\.openURL, OpenURLAction { _ in .discarded })
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            // Tests wait for bundled content to finish loading, then assert screen-specific UI.
            .accessibilityIdentifier(library.store.articles.isEmpty
                                     ? "screenshot.loading" : "screenshot.ready.\(ScreenshotMode.screen!.rawValue)")
    }
}
#endif
