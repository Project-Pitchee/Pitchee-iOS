//
//  DashboardCard.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import SwiftUI

/// A dashboard card fills the grid cell supplied by DashboardWidgetLayout.
/// Its content density follows the chosen size; the glass surface never relies
/// on a label or chart's intrinsic height to determine the widget's bounds.
struct DashboardCard: View {
    let component: DashboardComponent
    let size: DashboardComponentSize
    let snapshot: DashboardSnapshot
    let preference: VoicePreference
    let palette: AppThemePalette
    let isEditing: Bool

    private var title: LocalizedStringKey {
        component == .compositeScore ? preference.scoreTitle : LocalizedStringKey(component.titleKey)
    }

    private var tint: Color {
        switch component {
        case .analysisCount, .compositeScore: palette.accent
        case .openedDays, .naturalness: palette.secondary
        case .meanPitch: palette.tertiary
        }
    }

    private var current: Double? {
        switch component {
        case .analysisCount: Double(snapshot.assessmentCount)
        case .openedDays: Double(snapshot.openedDays)
        case .compositeScore: snapshot.latestScore
        case .naturalness: snapshot.latestNaturalness
        case .meanPitch: snapshot.latestPitch
        }
    }

    private var baseline: Double? {
        switch component {
        case .analysisCount, .openedDays: nil
        case .compositeScore: snapshot.averages.finalScore
        case .naturalness: snapshot.averages.naturalnessScore
        case .meanPitch: snapshot.averages.meanPitchHz
        }
    }

    private var points: [DashboardTrendPoint] {
        switch component {
        case .analysisCount, .openedDays: []
        case .compositeScore: snapshot.scorePoints
        case .naturalness: snapshot.naturalnessPoints
        case .meanPitch: snapshot.pitchPoints
        }
    }

    private var showsDetails: Bool { size != .small }

    /// Missing metrics keep their existing presentation. Complete daily results
    /// use a compact summary until there are enough dates to draw a useful chart.
    static func summaryDayCount(for component: DashboardComponent, snapshot: DashboardSnapshot) -> Int {
        guard (1...3).contains(snapshot.recordDayCount) else { return 0 }
        let points: [DashboardTrendPoint]
        let current: Double?
        switch component {
        case .analysisCount, .openedDays: return 0
        case .compositeScore:
            points = snapshot.scorePoints
            current = snapshot.latestScore
        case .naturalness:
            points = snapshot.naturalnessPoints
            current = snapshot.latestNaturalness
        case .meanPitch:
            points = snapshot.pitchPoints
            current = snapshot.latestPitch
        }
        return current != nil && points.count == snapshot.recordDayCount ? points.count : 0
    }

    private var summaryDayCount: Int { Self.summaryDayCount(for: component, snapshot: snapshot) }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                DashboardCardHeader(
                    title: title,
                    symbol: component.symbol,
                    tint: tint,
                    titleColor: palette.primaryText,
                    detailColor: palette.secondaryText,
                    isCompact: size == .small,
                    isEditing: isEditing
                )
                .padding(.leading, isEditing ? 28 : 0)

                if summaryDayCount > 0 {
                    recordSummary
                } else if size == .medium && !points.isEmpty {
                    HStack(alignment: .center, spacing: 16) {
                        readings
                            .frame(width: max(100, (geometry.size.width - 48) * 0.4), alignment: .leading)
                        chart
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    readings
                    if !points.isEmpty { chart }
                }
            }
            .padding(16)
            .padding(.bottom, isEditing && component.supportsResizing ? 28 : 0)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .liquidGlass(tint: .clear, cornerRadius: 20, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var recordSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if size == .medium {
                HStack(alignment: .bottom, spacing: 12) {
                    valueLabel
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    latestRecordLabel(alignment: .trailing)
                }
            } else {
                valueLabel
                if size == .large || summaryDayCount == 1 {
                    latestRecordLabel(alignment: .leading)
                }
            }

            if summaryDayCount > 1 {
                Divider().overlay(palette.secondaryText.opacity(0.12))
                HStack(alignment: .top, spacing: 8) {
                    ForEach(points) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.date, format: .dateTime.month(.defaultDigits).day(.defaultDigits))
                                .foregroundStyle(palette.secondaryText)
                            Text(point.value.formatted(.number.precision(.fractionLength(component == .meanPitch ? 1 : 0))))
                                .fontWeight(.medium)
                                .foregroundStyle(point.id == points.last?.id ? tint : palette.secondaryText)
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(point.date, format: .dateTime.year().month().day()))
                        .accessibilityValue(formattedValue(point.value))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func latestRecordLabel(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            if let date = snapshot.latestDate {
                Text(date, format: .dateTime.month().day())
            }
            Text("insights.metric.latest.label")
                .font(.caption2)
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
        .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 4) {
            if size == .medium {
                stackedReading
            } else {
                // Keep the full number and unit together. If the change no
                // longer fits beside them, give it a line of its own.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        valueLabel.fixedSize(horizontal: true, vertical: false)
                        baselineChange.fixedSize(horizontal: true, vertical: false)
                    }
                    stackedReading
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showsDetails, let baseline {
                Text("insights.metric.baselineAverage.caption \(formattedValue(baseline))")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .layoutPriority(1)
    }

    private var valueLabel: some View {
        Text(current.map(formattedValue) ?? String(localized: "common.placeholder.noValue"))
            .font(.system(size: size == .large ? 44 : 32, weight: .bold, design: .rounded))
            .foregroundStyle(current == nil ? palette.secondaryText : palette.primaryText)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .monospacedDigit()
    }

    private var baselineChange: some View {
        DashboardBaselineChange(current: current, baseline: baseline, tint: palette.secondaryText)
    }

    private var stackedReading: some View {
        VStack(alignment: .leading, spacing: 4) {
            valueLabel
            baselineChange
        }
    }

    private var chart: some View {
        DashboardTrendChart(
            points: points,
            tint: tint,
            labelColor: palette.secondaryText,
            isPitch: component == .meanPitch,
            showsXAxis: size == .large
        )
        .accessibilityLabel(Text(title))
    }

    private func formattedValue(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if component == .meanPitch {
            return value.formatted(.number.precision(.fractionLength(1)))
                + " " + String(localized: "common.unit.hertz")
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}

private struct DashboardCardHeader: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let titleColor: Color
    let detailColor: Color
    let isCompact: Bool
    let isEditing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(titleColor)
                .lineLimit(isCompact ? 2 : 1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(detailColor)
                .opacity(isEditing ? 0 : 1)
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.medium))
    }
}

private struct DashboardBaselineChange: View {
    let current: Double?
    let baseline: Double?
    let tint: Color

    private var change: Double? {
        guard let current, let baseline, current.isFinite, baseline.isFinite, baseline != 0 else { return nil }
        let percentage = (current - baseline) / abs(baseline) * 100
        return percentage.isFinite && abs(percentage) >= 0.5 ? percentage : nil
    }

    var body: some View {
        if let change {
            Text(verbatim: "\(change > 0 ? "↑" : "↓") \(abs(change).formatted(.number.precision(.fractionLength(0))))%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
