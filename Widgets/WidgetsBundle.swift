//
//  WidgetsBundle.swift
//  Widgets
//
//  Created by DannyFeng on 11/14/26.
//

import WidgetKit
import SwiftUI

@main
struct WidgetsBundle: WidgetBundle {
    var body: some Widget {
        Widgets(component: .analysisCount)
        Widgets(component: .openedDays)
        Widgets(component: .compositeScore)
        Widgets(component: .naturalness)
        Widgets(component: .meanPitch)
    }
}
