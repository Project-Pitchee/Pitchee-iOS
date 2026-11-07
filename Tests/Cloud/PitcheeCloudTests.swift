import SwiftData
import XCTest
@testable import Pitchee

/// Small in-process checks run by Xcode Cloud, alongside the broader regression scripts.
@MainActor
final class PitcheeCloudTests: XCTestCase {
    func testAppVersionUsesTheRunningAppBundle() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let marketing = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        let build = try XCTUnwrap(info["CFBundleVersion"] as? String)
        XCTAssertFalse(marketing.isEmpty)
        XCTAssertFalse(build.isEmpty)
        XCTAssertEqual(AppVersion.current, "\(marketing) (\(build))")
    }

    func testAppVersionFormatsBothFieldsWithoutInventingMissingVersions() {
        XCTAssertEqual(AppVersion.display(infoDictionary: [
            "CFBundleShortVersionString": "12.4.7", "CFBundleVersion": "507"
        ]), "12.4.7 (507)")
        XCTAssertEqual(AppVersion.display(infoDictionary: [
            "CFBundleShortVersionString": "2.0.0", "CFBundleVersion": "508"
        ]), "2.0.0 (508)")
        XCTAssertEqual(AppVersion.display(infoDictionary: nil), "— (—)")
        XCTAssertEqual(AppVersion.display(infoDictionary: [
            "CFBundleShortVersionString": "", "CFBundleVersion": "45"
        ]), "— (45)")
    }

    func testScreenshotHistoryIsDeterministicAndIsolated() throws {
        let first = try ScreenshotMode.makeContainer()
        let second = try ScreenshotMode.makeContainer()
        let query = FetchDescriptor<RecordingAssessment>(sortBy: [SortDescriptor(\.recordedAt)])
        let firstRows = try first.mainContext.fetch(query)
        let secondRows = try second.mainContext.fetch(query)
        XCTAssertEqual(firstRows.count, 14)
        XCTAssertEqual(Set(firstRows.map { Calendar.current.startOfDay(for: $0.recordedAt) }).count, 7)
        XCTAssertEqual(firstRows.map(\.id), secondRows.map(\.id))
        XCTAssertEqual(firstRows.map(\.recordedAt), secondRows.map(\.recordedAt))
        XCTAssertEqual(firstRows.map(\.meanPitchHz), secondRows.map(\.meanPitchHz))
        XCTAssertEqual(firstRows.map(\.finalScore), secondRows.map(\.finalScore))
        first.mainContext.delete(firstRows[0])
        try first.mainContext.save()
        XCTAssertEqual(try second.mainContext.fetch(query).count, 14)
    }

    func testShortSpeechCannotBecomeComparable() {
        let quality = RecordingQuality(speechSeconds: 4.99, speechDBFS: -27,
                                       backgroundDBFS: -40, clippedFraction: 0)
        XCTAssertFalse(quality.canCompare)
        XCTAssertEqual(quality.issues, [.shortSpeech])
    }

    func testBundledArticlesLoadInBothEditorialLanguages() async throws {
        for language in ["en", "zh-Hans"] {
            let store = try await VoiceTrainingLibraryStore.load(preferredLanguages: [language])
            XCTAssertFalse(store.articles.isEmpty)
            XCTAssertFalse(store.articles(inCategory: "pitch").isEmpty)
        }
    }
}
