//
//  InsightsActivityCalendar.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/4.
//

import SwiftUI
import UIKit

/// The system owns month navigation, date layout, and selection. This adapter
/// supplies only the app's date limits and activity decorations.
struct InsightsActivityCalendar: UIViewRepresentable {
    @Binding var selectedDay: Date
    let availableDates: DateInterval
    let openedDates: Set<Date>
    let recordingDates: Set<Date>
    let openedTint: Color
    let recordingTint: Color
    var calendar = Calendar.current
    @Environment(\.locale) private var locale

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "insights.activity.calendar"
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let previous = context.coordinator.parent
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }

        let calendarChanged = view.calendar != calendar || view.locale != locale
        let rangeChanged = view.availableDateRange != availableDates
        let colorsChanged = previous.openedTint != openedTint || previous.recordingTint != recordingTint
        if view.calendar != calendar { view.calendar = calendar }
        if view.locale != locale { view.locale = locale }
        view.timeZone = calendar.timeZone
        view.tintColor = UIColor(.pitcheeAccent)

        let selection = view.selectionBehavior as? UICalendarSelectionSingleDate
        let day = calendar.startOfDay(for: min(max(selectedDay, availableDates.start), availableDates.end))
        let components = dateComponents(for: day)
        let selectionChanged = selection?.selectedDate.flatMap { calendar.date(from: $0) }
            .map { !calendar.isDate($0, inSameDayAs: day) } ?? true

        if rangeChanged || calendarChanged {
            // Move the visible month and selection while both the old and new
            // ranges are valid, then narrow the range. UIKit rejects dates
            // outside availableDateRange.
            selection?.setSelected(nil, animated: false)
            view.availableDateRange = DateInterval(
                start: min(view.availableDateRange.start, availableDates.start),
                end: max(view.availableDateRange.end, availableDates.end)
            )
            view.setVisibleDateComponents(components, animated: false)
            view.availableDateRange = availableDates
            selection?.setSelected(components, animated: false)
        } else if selectionChanged {
            selection?.setSelected(components, animated: false)
            view.setVisibleDateComponents(components, animated: false)
        }

        let reloadAllDecorations = !context.coordinator.hasLoadedDecorations
            || calendarChanged || rangeChanged || colorsChanged
        let changedDates = reloadAllDecorations
            ? previous.openedDates.union(previous.recordingDates).union(openedDates).union(recordingDates)
            : previous.openedDates.symmetricDifference(openedDates)
                .union(previous.recordingDates.symmetricDifference(recordingDates))
        if !changedDates.isEmpty {
            view.reloadDecorations(
                forDateComponents: changedDates.map(dateComponents),
                animated: false
            )
        }
        context.coordinator.hasLoadedDecorations = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    private func dateComponents(for date: Date) -> DateComponents {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: InsightsActivityCalendar
        var isUpdating = false
        var hasLoadedDecorations = false

        init(_ parent: InsightsActivityCalendar) { self.parent = parent }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard !isUpdating, let dateComponents,
                  let date = parent.calendar.date(from: dateComponents) else { return }
            parent.selectedDay = parent.calendar.startOfDay(for: date)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            guard let dateComponents, let date = parent.calendar.date(from: dateComponents) else { return false }
            return parent.availableDates.contains(date)
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let date = parent.calendar.date(from: dateComponents) else { return nil }
            let day = parent.calendar.startOfDay(for: date)
            guard parent.availableDates.contains(day) else { return nil }
            let isOpened = parent.openedDates.contains(day)
            let hasRecordings = parent.recordingDates.contains(day)
            guard isOpened || hasRecordings else { return nil }
            let tint = UIColor(hasRecordings ? parent.recordingTint : parent.openedTint)

            return .customView {
                // A recording takes precedence over an app open on the same day.
                // UIImageView provides the intrinsic size UICalendarView needs
                // to lay out its decoration; a plain UIStackView does not.
                let decoration = hasRecordings
                    ? Self.marker("waveform", color: tint, size: 10)
                    : Self.marker("circle.fill", color: tint, size: 5)
                decoration.isAccessibilityElement = true
                decoration.accessibilityLabel = hasRecordings
                    ? String(localized: "insights.activity.recorded.label")
                    : String(localized: "insights.activity.opened.label")
                decoration.frame.size = decoration.intrinsicContentSize
                return decoration
            }
        }

        private static func marker(_ symbol: String, color: UIColor, size: CGFloat) -> UIImageView {
            let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .medium))
            let view = UIImageView(image: image)
            view.tintColor = color
            view.tintAdjustmentMode = .normal
            view.isAccessibilityElement = false
            return view
        }
    }
}
