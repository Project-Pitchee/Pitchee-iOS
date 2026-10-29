//
//  RecordingAudioStore.swift
//  Pitchee
//

import Foundation

nonisolated enum RecordingAudioStore {
    static func store(_ source: URL, id: UUID) throws -> String {
        let directory = try directory()
        let fileName = "\(id.uuidString).wav"
        let destination = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: destination.path
        )
        #endif
        return fileName
    }

    static func url(for fileName: String) -> URL? {
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              let directory = try? directory() else { return nil }
        let url = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(fileName: String) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func directory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("PitcheeRecordings", isDirectory: true)
        try PrivateAppStorage.protectDirectory(directory)
        return directory
    }
}
