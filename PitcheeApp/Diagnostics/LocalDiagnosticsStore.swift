//
//  LocalDiagnosticsStore.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Combine
import CryptoKit
import Foundation

@MainActor
final class LocalDiagnosticsStore: ObservableObject {
    struct AttemptToken: Equatable { fileprivate let id = UUID() }

    static var bundledConfiguration: DiagnosticConfiguration {
        let manifest = Bundle.main.url(forResource: "models", withExtension: nil)?
            .appendingPathComponent("manifest.json")
        let digest = manifest.flatMap { try? Data(contentsOf: $0) }.map {
            SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        } ?? ""
        return DiagnosticConfiguration(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            manifestSHA256: digest, measurementRevision: 1
        )
    }

    static let shared: LocalDiagnosticsStore = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalDiagnosticsStore(
            fileURL: support.appendingPathComponent("LocalDiagnostics/state.json"),
            configuration: bundledConfiguration
        )
    }()

    @Published private(set) var state: LocalDiagnosticState
    @Published private(set) var storageUnavailable = false
    private let fileURL: URL
    private let configuration: DiagnosticConfiguration
    private let now: () -> Date
    private var activeToken: AttemptToken?

    init(fileURL: URL, configuration: DiagnosticConfiguration, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.configuration = configuration
        self.now = now
        state = LocalDiagnosticState(now: now(), configuration: configuration)
        guard configuration.isValid else { storageUnavailable = true; return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 16_384 else { throw CocoaError(.fileReadCorruptFile) }
            let loaded = try JSONDecoder().decode(LocalDiagnosticState.self, from: Data(contentsOf: fileURL))
            guard loaded.isValid else { throw CocoaError(.fileReadCorruptFile) }
            state = loaded
            _ = state.refresh(now: now(), configuration: configuration)
            state.recoverInterruptedAttempt()
            persist()
        } catch {
            // Never salvage arbitrary fields, exception text, or partial records.
            failClosed()
        }
    }

    func refresh() {
        if state.refresh(now: now(), configuration: configuration) {
            activeToken = nil
            persist()
        }
    }

    func setEnabled(_ enabled: Bool) {
        refresh()
        guard configuration.isValid else { storageUnavailable = true; return }
        activeToken = nil
        // Switching on is a fresh consent boundary, even for an old async task.
        state.clearSummary()
        state.setEnabled(enabled)
        persist()
    }

    func clearSummary() {
        activeToken = nil
        state.clearSummary()
        persist()
    }

    func beginAttempt() -> AttemptToken? {
        refresh()
        guard !storageUnavailable, activeToken == nil, state.begin() else { return nil }
        let token = AttemptToken()
        activeToken = token
        persist()
        return storageUnavailable ? nil : token
    }

    func finish(_ token: AttemptToken?, outcome: DiagnosticOutcome, observation: DiagnosticObservation) {
        refresh()
        guard let token, token == activeToken, state.enabled, !storageUnavailable else { return }
        activeToken = nil
        state.finish(outcome, observation: observation)
        persist()
    }

    private func persist() {
        do {
            guard state.isValid else { throw CocoaError(.fileWriteUnknown) }
            try PrivateAppStorage.protectDirectory(fileURL.deletingLastPathComponent())
            let data = try JSONEncoder().encode(state)
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
            storageUnavailable = false
        } catch {
            failClosed()
        }
    }

    private func failClosed() {
        activeToken = nil
        state.setEnabled(false)
        storageUnavailable = true
        // If removal fails (e.g. locked storage), do not claim deletion succeeded.
        try? FileManager.default.removeItem(at: fileURL)
    }
}
