//
//  DashboardWidgetLayout.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import SwiftUI

/// One ForEach owns every card identity, even when a card crosses rows. Both
/// native reorder placeholders and the compatibility path use these metrics.
struct DashboardWidgetLayout: Layout {
    let minimumHeight: CGFloat
    let sizes: [DashboardComponentSize]
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: metrics(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = metrics(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = metrics.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func metrics(width: CGFloat, subviews: Subviews) -> DashboardWidgetMetrics {
        DashboardWidgetMetrics(
            width: width, spacing: spacing, minimumHeight: minimumHeight,
            // reorderable() wraps each child and doesn't forward its layout
            // values. Supply the same ordered sizes used to build the cards.
            sizes: subviews.indices.map { sizes.indices.contains($0) ? sizes[$0] : .small }
        )
    }
}
