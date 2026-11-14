import Foundation
import OSLog
import WidgetKit

nonisolated struct DashboardWidgetState: Codable, Equatable, Sendable {
    let snapshot: DashboardSnapshot
    let preference: VoicePreference
    let theme: String

    static let empty = Self(snapshot: .empty, preference: .undecided, theme: "twilt")
}

nonisolated enum DashboardWidgetStore {
    static let groupIdentifier = "group.com.rolvy.Pitchee.963SN9ZCQ5"
    private static let logger = Logger(subsystem: "com.rolvy.Pitchee", category: "Widgets")

    static var sharedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("Dashboard", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    static func load(from url: URL? = sharedURL) -> DashboardWidgetState {
        guard let url, let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(DashboardWidgetState.self, from: data) else {
            return .empty
        }
        return state
    }

    @discardableResult
    static func save(_ state: DashboardWidgetState, to url: URL? = sharedURL) -> Bool {
        guard let url else {
            logger.error("The widget shared container is unavailable.")
            return false
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            guard (try? Data(contentsOf: url)) != data else { return false }
            var directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            if url == sharedURL { WidgetCenter.shared.reloadAllTimelines() }
            return true
        } catch {
            logger.error("The dashboard widget snapshot could not be saved: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }
}
