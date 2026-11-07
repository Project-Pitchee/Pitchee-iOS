//
//  MonitorAccessoryState.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import Observation
import SwiftUI

/// The destination owns the session; the tab view presents its controls.
@MainActor
@Observable
final class MonitorAccessoryState {
    private(set) var model: MonitorViewModel?
    var isExpanded = false

    func show(_ model: MonitorViewModel) {
        guard self.model !== model else { return }
        self.model?.stopForLeaving()
        isExpanded = false
        self.model = model
    }

    func hide(_ model: MonitorViewModel) {
        guard self.model === model else { return }
        isExpanded = false
        self.model = nil
    }

    func leavePractice() {
        isExpanded = false
        model?.stopForLeaving()
        model = nil
    }
}

private struct MonitorAccessoryStateKey: EnvironmentKey {
    static let defaultValue: MonitorAccessoryState? = nil
}

extension EnvironmentValues {
    var monitorAccessoryState: MonitorAccessoryState? {
        get { self[MonitorAccessoryStateKey.self] }
        set { self[MonitorAccessoryStateKey.self] = newValue }
    }
}
