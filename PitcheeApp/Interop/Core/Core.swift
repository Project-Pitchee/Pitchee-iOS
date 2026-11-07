//
//  Core.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/13.
//

import CPitcheeCore
import Foundation

nonisolated public enum PitcheeCore {
    public static func bundledModelDirectory(in bundle: Bundle = .main) throws -> URL {
        guard let directory = bundle.url(forResource: "models", withExtension: nil) else {
            throw PitcheeCoreError(
                message: "The PitcheeCore model directory is missing from the app bundle."
            )
        }
        return directory
    }
}
