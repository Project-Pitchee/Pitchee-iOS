//
//  AppStorage.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/26.
//

import Foundation

/// Stable identifiers for everything the app persists in `UserDefaults`.
///
/// Keys are semantic and hierarchical — `<feature>.<context>.<semantic>` — and are
/// never derived from user-visible copy, so wording and translations can change
/// without orphaning the values people already have on their devices.
enum AppStorageKey {
    /// Highest onboarding-flow revision the person has completed.
    static let onboardingCompletedVersion = "onboarding.progress.completedVersion"

    /// The person's voice-direction preference, stored as `VoicePreference.rawValue`.
    static let voicePreference = "voiceProfile.selection.preference"

    /// Legacy optional custom theme color, stored as an sRGB hex string. New
    /// selections in Personalization clear this value.
    static let customThemeColor = "appearance.theme.customHex"

    /// The selected theme, stored as an `AppThemeOption` raw value.
    /// Each theme automatically follows the system's light or dark appearance.
    static let themeSelection = "appearance.theme.selection"

    /// Comma-separated `yyyy-M-d` strings, one per day the app was opened.
    static let openedDateKeys = "insights.activity.openedDates"

    /// Comma-separated dashboard component identifiers in the person's order.
    /// An empty value is valid and means every optional component is hidden.
    static let dashboardComponentOrder = "insights.dashboard.componentOrder"

    /// JSON mapping of component identifiers to their selected widget size.
    static let dashboardComponentSizes = "insights.dashboard.componentSizes"
}

/// The onboarding flow revision the app currently ships.
enum OnboardingFlow {
    /// Bump this to walk everyone through onboarding again.
    static let currentVersion = 2
}

/// Moves values written under the pre-1.1 key names onto the semantic keys.
///
/// Identifiers are meant to be stable, so this runs once at launch and can be
/// deleted after every install has migrated.
enum AppStorageMigration {
    private static let legacyOnboardingCompleted = "pitchee.onboarding.completed"
    private static let legacyVoicePreference = "pitchee.voice.preference"
    private static let legacyOpenedDateKeys = "pitchee.opened.calendar.days"

    static func run(in defaults: UserDefaults = .standard) {
        migrateOnboarding(in: defaults)
        migrateVoicePreference(in: defaults)
        migrateOpenedDateKeys(in: defaults)

        for legacy in [legacyOnboardingCompleted, legacyVoicePreference, legacyOpenedDateKeys] {
            defaults.removeObject(forKey: legacy)
        }
    }

    /// The legacy Boolean also encoded "onboarding flow revision 2".
    private static func migrateOnboarding(in defaults: UserDefaults) {
        guard defaults.object(forKey: AppStorageKey.onboardingCompletedVersion) == nil,
              defaults.object(forKey: legacyOnboardingCompleted) != nil else { return }
        let completed = defaults.bool(forKey: legacyOnboardingCompleted)
        defaults.set(completed ? OnboardingFlow.currentVersion : 0,
                     forKey: AppStorageKey.onboardingCompletedVersion)
    }

    /// The legacy value was the option's display text; rewrite it as an identifier.
    private static func migrateVoicePreference(in defaults: UserDefaults) {
        guard defaults.object(forKey: AppStorageKey.voicePreference) == nil,
              let legacy = defaults.string(forKey: legacyVoicePreference) else { return }
        let migrated = VoicePreference(legacyStoredValue: legacy) ?? .undecided
        defaults.set(migrated.rawValue, forKey: AppStorageKey.voicePreference)
    }

    private static func migrateOpenedDateKeys(in defaults: UserDefaults) {
        guard defaults.object(forKey: AppStorageKey.openedDateKeys) == nil,
              let legacy = defaults.string(forKey: legacyOpenedDateKeys) else { return }
        defaults.set(legacy, forKey: AppStorageKey.openedDateKeys)
    }
}
