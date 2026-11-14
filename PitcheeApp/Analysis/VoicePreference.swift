import Foundation

nonisolated enum VoicePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case masculine
    case feminine
    case undecided

    var id: String { rawValue }

    /// Accept the display strings persisted by builds before semantic keys.
    init?(legacyStoredValue: String) {
        switch legacyStoredValue {
        case "男性向声音": self = .masculine
        case "女性向声音": self = .feminine
        case "暂不确定": self = .undecided
        default:
            guard let value = Self(rawValue: legacyStoredValue) else { return nil }
            self = value
        }
    }
}
