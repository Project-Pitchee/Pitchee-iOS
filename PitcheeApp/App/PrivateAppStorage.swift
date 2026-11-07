//
//  PrivateAppStorage.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation

nonisolated enum PrivateAppStorage {
    /// Call with the app sandbox's Library directory, never a shared user Library.
    /// Directory exclusions cover SQLite sidecars and future atomic replacements.
    static func prepare(libraryDirectory: URL) throws {
        for name in ["Application Support", "Preferences"] {
            let directory = libraryDirectory.appendingPathComponent(name, isDirectory: true)
            try protectDirectory(directory)
            #if os(iOS)
            // Existing SQLite files/sidecars and preferences predate these defaults.
            for file in try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey]
            ) where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path
                )
            }
            #endif
        }
    }

    static func protectDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path
        )
        #endif
    }

    /// Only called on launch, before capture starts. Preserve all unrelated files.
    static func removeAbandonedRecordings(in directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        )
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            guard file.pathExtension == "wav", name.hasPrefix("pitchee-"),
                  UUID(uuidString: String(name.dropFirst("pitchee-".count))) != nil,
                  try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }
}
