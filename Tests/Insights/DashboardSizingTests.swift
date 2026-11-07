//
//  DashboardSizingTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import Foundation
import CoreGraphics

@main
enum DashboardSizingTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        let metrics = DashboardWidgetMetrics(
            width: 362, spacing: 12, minimumHeight: 174,
            sizes: [.small, .small, .medium, .small, .small, .large]
        )
        for index in [0, 1, 3, 4] {
            check(metrics.frames[index].size == CGSize(width: 175, height: 175),
                  "All four small metrics have identical square dimensions")
        }
        check(metrics.frames[2].size == CGSize(width: 362, height: 175), "Medium spans one row")
        check(metrics.frames[5].size == CGSize(width: 362, height: 362), "Large spans two rows plus the gap")
        check(metrics.height == 923, "Grid includes only the gaps between rows")
        let odd = DashboardWidgetMetrics(width: 362, spacing: 12, minimumHeight: 174, sizes: [.small, .medium, .small])
        check(odd.frames[0].width == 175 && odd.frames[2].width == 175,
              "An unpaired small widget stays half width")
        check(odd.frames[1].minY == 187 && odd.frames[2].minY == 374,
              "A wide widget starts on the next row")
        let accessible = DashboardWidgetMetrics(width: 300, spacing: 12, minimumHeight: 260, sizes: [.small, .small])
        check(accessible.frames.allSatisfy { $0.height == 260 }, "Larger type expands all compact widgets equally")
        check(DashboardWidgetMetrics(width: 362, spacing: 12, minimumHeight: 174, sizes: []).height == 0,
              "Empty dashboards don't have a negative height")

        let sizes: [String: DashboardComponentSize] = ["pitch": .large, "naturalness": .small]
        check(DashboardComponentSizes.decode(DashboardComponentSizes.encode(sizes)) == sizes, "Sizes survive persistence")
        check(DashboardComponentSizes.decode("invalid").isEmpty, "Malformed saved sizes fall back to defaults")
        check(DashboardComponentSizes.decode("{\"pitch\":\"future\",\"days\":\"medium\"}") == ["days": .medium],
              "An unsupported size doesn't discard the valid preferences")
        check(DashboardComponentSize.small.resized(by: CGSize(width: 50, height: 0)) == .medium, "Dragging right expands")
        check(DashboardComponentSize.small.resized(by: CGSize(width: 0, height: 110)) == .large, "A longer outward drag reaches large")
        check(DashboardComponentSize.large.resized(by: CGSize(width: 0, height: -50)) == .medium, "Dragging up contracts")
        check(DashboardComponentSize.small.resized(by: CGSize(width: -100, height: 0)) == .small, "Resizing clamps at the minimum")
        check(DashboardComponentSize.large.resized(by: CGSize(width: 110, height: 0)) == .large, "Resizing clamps at the maximum")
        check(DashboardComponentSize.small.resized(by: CGSize(width: -20, height: 0)) == .small, "A small finger movement doesn't resize")

        var drag = DashboardDragFeedbackState<String>()
        check(drag.begin("pitch", at: 2), "Activate feedback once per session")
        check(!drag.begin("pitch", at: 2), "Repeated active updates don't repeat the lift feedback")
        check(!drag.move(to: 2), "An unchanged slot doesn't produce selection feedback")
        check(drag.move(to: 1), "Crossing a slot produces selection feedback")
        check(!drag.move(to: 1), "Hover updates don't repeat the feedback")
        check(drag.move(to: 2), "Returning to the original slot is another position change")
        check(drag.end(), "Release produces feedback even without committing a move")
        check(!drag.end(), "Ending and ended phases don't produce duplicate release feedback")
        check(!drag.move(to: 0), "Late drop updates after release are ignored")
        check(drag.begin("days", at: 0) && drag.end(), "An unmoved drag still has activation and release feedback")

        let defaultConfiguration = DashboardConfiguration()
        check(defaultConfiguration.components == [.analysisCount, .openedDays, .compositeScore, .naturalness, .meanPitch],
              "A missing preference restores the established five-widget order")
        check(defaultConfiguration.size(for: .compositeScore) == .medium
              && defaultConfiguration.size(for: .analysisCount) == .small,
              "Default sizing preserves the wide score and compact metrics")
        check(DashboardComponent.allCases.filter(\.supportsResizing) == [.compositeScore, .naturalness, .meanPitch],
              "Only components with charts support resizing")
        var legacySizes = DashboardConfiguration(
            order: "analysisCount,openedDays,naturalness",
            sizes: "{\"analysisCount\":\"large\",\"openedDays\":\"medium\",\"naturalness\":\"large\",\"meanPitch\":\"medium\"}"
        )
        check(legacySizes.size(for: .analysisCount) == .small && legacySizes.size(for: .openedDays) == .small,
              "Previously enlarged statistics return to the fixed small size")
        check(legacySizes.sizes["analysisCount"] == nil && legacySizes.sizes["openedDays"] == nil,
              "Decoding removes obsolete saved size overrides for statistics")
        check(legacySizes.size(for: .naturalness) == .large && legacySizes.size(for: .meanPitch) == .medium,
              "Migrating statistic sizes preserves visible and hidden chart sizes")
        check(!legacySizes.resize(.analysisCount, to: .large) && !legacySizes.resize(.openedDays, to: .medium),
              "Statistics reject resize callbacks instead of saving unsupported dimensions")
        legacySizes.sizes["analysisCount"] = .large
        check(legacySizes.size(for: .analysisCount) == .small,
              "Statistics remain small even if an in-memory configuration has a stale override")
        let sanitized = DashboardConfiguration(order: "meanPitch,futureWidget,meanPitch,,analysisCount")
        check(sanitized.components == [.meanPitch, .analysisCount],
              "Saved layouts retain valid order while dropping unknown and duplicate identifiers")
        check(DashboardConfiguration(order: "").components.isEmpty,
              "An intentionally empty dashboard does not restore hidden widgets")
        check(DashboardConfiguration(sizes: "{\"compositeScore\":\"future\",\"meanPitch\":\"large\"}").size(for: .compositeScore) == .medium,
              "An unsupported saved size falls back to that component's own default")

        var editable = DashboardConfiguration()
        check(!editable.add(.analysisCount), "Adding an existing widget does not alter the layout")
        check(!editable.resize(.meanPitch, to: .small), "Resizing to the effective default is a no-op")
        check(editable.resize(.meanPitch, to: .large), "A changed size is accepted")
        check(!editable.resize(.meanPitch, to: .large), "Repeated resize callbacks do not count as changes")
        check(editable.remove(.meanPitch), "Visible widgets can be hidden")
        check(!editable.remove(.meanPitch), "Repeated removal callbacks are no-ops")
        check(!editable.resize(.meanPitch, to: .medium), "Late resize callbacks cannot change a hidden widget")
        var restored = DashboardConfiguration(order: editable.encodedOrder, sizes: editable.encodedSizes)
        check(restored == editable, "Order and sizes round-trip together after hiding a widget")
        check(restored.add(.meanPitch) && restored.components.last == .meanPitch
              && restored.size(for: .meanPitch) == .large,
              "Re-adding a widget appends it and restores its saved size")
        for component in Array(restored.components) { restored.remove(component) }
        let restoredEmpty = DashboardConfiguration(order: restored.encodedOrder, sizes: restored.encodedSizes)
        check(restoredEmpty.components.isEmpty && restoredEmpty.size(for: .meanPitch) == .large,
              "Hiding all widgets persists the empty layout and their size preferences")

        var native = DashboardConfiguration()
        check(native.move([.analysisCount], before: nil)
              && native.components == [.openedDays, .compositeScore, .naturalness, .meanPitch, .analysisCount],
              "The native end destination moves the first widget after the last widget")
        check(!native.move([.analysisCount], before: nil), "Repeated end-drop callbacks are no-ops")
        check(native.move([.analysisCount], before: .openedDays) && native == defaultConfiguration,
              "Moving the last widget before the first restores the initial order")
        check(!native.move([.analysisCount], before: .openedDays),
              "Dropping before the current successor does not shift a widget")
        check(native.move([.analysisCount], before: .compositeScore)
              && native.components == [.openedDays, .analysisCount, .compositeScore, .naturalness, .meanPitch],
              "A forward insertion gap is resolved after removing the dragged widget")
        check(!native.move([.analysisCount], before: .compositeScore),
              "Repeated before-drop callbacks do not reorder the same gap again")
        check(native.move([.analysisCount], before: .openedDays) && native == defaultConfiguration,
              "The native before destination supports adjacent backward moves")

        let unchanged = native
        check(!native.move([], before: nil), "An empty drag payload cannot change the order")
        check(!native.move([.analysisCount, .analysisCount], before: nil),
              "A duplicate drag identifier is rejected instead of duplicating a widget")
        check(!native.move([.analysisCount], before: .analysisCount),
              "Dropping a widget before itself is a no-op")
        check(!native.move([.analysisCount, .openedDays], before: .openedDays),
              "A destination within a dragged group is a no-op")
        check(native == unchanged, "Rejected drag payloads leave persisted order and sizes intact")
        var partial = DashboardConfiguration(order: "analysisCount,openedDays")
        check(!partial.move([.meanPitch], before: .analysisCount), "Hidden drag sources are rejected")
        check(!partial.move([.analysisCount, .meanPitch], before: nil),
              "One stale source rejects the entire group without moving the valid source")
        check(!partial.move([.analysisCount], before: .meanPitch), "A stale native target is rejected")
        check(partial.components == [.analysisCount, .openedDays], "Stale drops leave the visible layout intact")

        var grouped = DashboardConfiguration()
        check(grouped.move([.naturalness, .openedDays], before: .analysisCount)
              && grouped.components == [.openedDays, .naturalness, .analysisCount, .compositeScore, .meanPitch],
              "A multi-widget drop preserves dashboard order rather than payload order")
        check(grouped.move([.naturalness, .openedDays], before: nil)
              && grouped.components == [.analysisCount, .compositeScore, .meanPitch, .openedDays, .naturalness],
              "A grouped end drop preserves the relative order of dragged and stationary widgets")
        check(!grouped.move([.openedDays, .naturalness], before: nil),
              "Repeated grouped end drops are no-ops")

        var legacy = DashboardConfiguration()
        check(legacy.move(.analysisCount, to: .openedDays)
              && legacy.components == [.openedDays, .analysisCount, .compositeScore, .naturalness, .meanPitch],
              "Legacy occupied-cell drops allow an adjacent forward move")
        check(legacy.move(.analysisCount, to: .openedDays) && legacy == defaultConfiguration,
              "Legacy occupied-cell drops allow an adjacent backward move")
        check(legacy.move(.analysisCount, to: .meanPitch)
              && legacy.components == [.openedDays, .compositeScore, .naturalness, .meanPitch, .analysisCount],
              "Legacy occupied-cell drops can reach the last position")
        check(legacy.move(.analysisCount, to: .openedDays) && legacy == defaultConfiguration,
              "Legacy occupied-cell drops can return from the last to the first position")
        check(!legacy.move(.analysisCount, to: .analysisCount), "Legacy self-drops are no-ops")
        check(!partial.move(.meanPitch, to: .analysisCount) && !partial.move(.analysisCount, to: .meanPitch),
              "Legacy drops reject hidden sources and targets")
        print("Dashboard configuration, sizing, and drag lifecycle: \(checks) checks passed")
    }
}
