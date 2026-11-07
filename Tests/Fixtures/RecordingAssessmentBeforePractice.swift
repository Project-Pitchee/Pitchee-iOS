//
//  RecordingAssessmentBeforePractice.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/30.
//

import Foundation
import SwiftData

// Frozen schema before practice metadata was introduced. Keep the property
// names/types identical so this test exercises SwiftData's on-disk migration.
@Model
final class RecordingAssessment {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var schemaVersion: Int
    var modelVersion: String
    var inputSeconds: Double
    var analyzedSeconds: Double
    var speechSeconds: Double
    var meanPitchHz: Double?
    var standardScore: Double
    var naturalnessScore: Double
    var finalScore: Double
    var scoreWasLimited: Bool
    var resultPayload: Data

    init() {
        id = UUID(uuidString: "C0D00000-0000-0000-0000-000000000001")!
        recordedAt = Date(timeIntervalSince1970: 1_700_000_000)
        schemaVersion = 2
        modelVersion = "pre-practice-test"
        inputSeconds = 12
        analyzedSeconds = 12
        speechSeconds = 8
        meanPitchHz = 175
        standardScore = 60
        naturalnessScore = 75
        finalScore = 59
        scoreWasLimited = true
        resultPayload = Data("preserve-original-payload".utf8)
    }
}
