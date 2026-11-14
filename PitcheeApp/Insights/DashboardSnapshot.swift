//
//  DashboardSnapshot.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import Foundation

nonisolated struct DashboardTrendPoint: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let value: Double
    let position: Double
}

/// The app and WidgetKit render the same immutable display values.
nonisolated struct DashboardSnapshot: Codable, Equatable, Sendable {
    struct Averages: Codable, Equatable, Sendable {
        let finalScore: Double?
        let naturalnessScore: Double?
        let meanPitchHz: Double?
    }

    let assessmentCount: Int
    let recordDayCount: Int
    let openedDays: Int
    let referenceDate: Date
    let latestDate: Date?
    let latestScore: Double?
    let latestNaturalness: Double?
    let latestPitch: Double?
    let averages: Averages
    let scorePoints: [DashboardTrendPoint]
    let naturalnessPoints: [DashboardTrendPoint]
    let pitchPoints: [DashboardTrendPoint]

    static let empty = Self(
        assessmentCount: 0, recordDayCount: 0, openedDays: 0,
        referenceDate: Date(timeIntervalSince1970: 0), latestDate: nil,
        latestScore: nil, latestNaturalness: nil, latestPitch: nil,
        averages: Averages(finalScore: nil, naturalnessScore: nil, meanPitchHz: nil),
        scorePoints: [], naturalnessPoints: [], pitchPoints: []
    )
}
