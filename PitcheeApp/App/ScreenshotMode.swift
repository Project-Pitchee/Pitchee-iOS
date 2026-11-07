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

    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-UITestMode")
    static let now = Date(timeIntervalSince1970: 1_793_534_400) // 2026-11-01 12:00 UTC
    static let screen: Screen? = {
        guard isEnabled else { return nil }
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
        defaults.set((26...31).map { "2026-10-\($0)" }.joined(separator: ",") + ",2026-11-1",
                     forKey: AppStorageKey.openedDateKeys)
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
        // Fixed IDs, dates and measurements: no random generator or wall clock.
        // Two short exercises per day illustrate a week of practice, including variation.
        for index in 0..<14 {
            let result = DebugPreviewData.history[min(index / 5, DebugPreviewData.history.count - 1)]
            let assessment = try RecordingAssessment(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                recordedAt: now.addingTimeInterval(-Double(6 - index / 2) * 86_400 - Double(index % 2) * 1_800),
                result: result,
                preference: .feminine,
                quality: RecordingQuality(speechSeconds: 10, speechDBFS: -27,
                                          backgroundDBFS: -40, clippedFraction: 0)
            )
            container.mainContext.insert(assessment)
        }
        try container.mainContext.save()
        return container
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
