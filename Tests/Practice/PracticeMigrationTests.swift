//
//  PracticeMigrationTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation
import SwiftData

@main
enum PracticeMigrationTests {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = try ModelContainer(for: RecordingAssessment.self, configurations: ModelConfiguration(url: url))
        #if LEGACY_PRACTICE_SCHEMA
        store.mainContext.insert(RecordingAssessment())
        try store.mainContext.save()
        print("Practice migration: original store created")
        #else
        let records = try store.mainContext.fetch(FetchDescriptor<RecordingAssessment>())
        precondition(records.count == 1)
        let old = records[0]
        precondition(old.id == UUID(uuidString: "C0D00000-0000-0000-0000-000000000001"))
        precondition(old.recordedAt == Date(timeIntervalSince1970: 1_700_000_000))
        precondition(old.modelVersion == "pre-practice-test" && old.schemaVersion == 2)
        precondition(old.finalScore == 59 && old.standardScore == 60 && old.naturalnessScore == 75)
        precondition(old.meanPitchHz == 175 && old.speechSeconds == 8 && old.scoreWasLimited)
        precondition(old.resultPayload == Data("preserve-original-payload".utf8))
        precondition(old.recordedTarget == nil && old.capturedFinalScore == nil)
        precondition(old.practice == nil && old.quality == nil && !old.isBaselineEligible)
        precondition(old.scoringRulesVersion == nil && old.comparedToID == nil && old.comparisonFeedbackRawValue == nil)
        try store.mainContext.save()
        print("Practice migration: all original fields preserved; new metadata stays unknown")
        #endif
    }
}
