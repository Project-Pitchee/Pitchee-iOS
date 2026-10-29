//
//  SettingsCopy.swift
//  Pitchee
//
//  The settings ported from Android intentionally ships with the same two
//  languages as Android. Everything else continues to use the localized app.
//

import Foundation

enum SettingsCopy {
    static var isChinese: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true
    }

    static func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }
}
