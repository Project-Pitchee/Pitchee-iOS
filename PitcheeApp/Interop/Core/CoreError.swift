//
//  CoreError.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/13.
//

import CPitcheeCore
import Foundation

public struct PitcheeCoreError: LocalizedError, Sendable {
    public let statusCode: Int
    public let message: String

    public var errorDescription: String? { message }

    init(status: pitchee_status_t, message: String) {
        statusCode = Int(status.rawValue)
        self.message = message.isEmpty ? "PitcheeCore failed with status \(status.rawValue)." : message
    }

    init(message: String) {
        statusCode = -1
        self.message = message
    }
}
