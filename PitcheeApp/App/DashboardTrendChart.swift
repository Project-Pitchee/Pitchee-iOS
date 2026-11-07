//
//  DashboardTrendChart.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import Charts
import SwiftUI

struct DashboardTrendChart: View {
    let points: [DashboardTrendPoint]
    let tint: Color
    let labelColor: Color
    let isPitch: Bool
    let showsXAxis: Bool

    private var xDomain: ClosedRange<Double> {
        guard let first = points.first?.position, let last = points.last?.position else { return 0...1 }
        let padding = first == last ? 0.5 : 0.15
        return (first - padding)...(last + padding)
    }

    private var yDomain: ClosedRange<Double> {
        guard isPitch, let first = points.first else { return 0...100 }
        let minimum = points.dropFirst().reduce(first.value) { min($0, $1.value) }
        let maximum = points.dropFirst().reduce(first.value) { max($0, $1.value) }
        let padding = max((maximum - minimum) * 0.2, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }

    /// A large card needs only a few date labels even when the selected range
    /// contains months of history. Points themselves retain every daily value.
    private var axisPoints: [DashboardTrendPoint] {
        guard points.count > 3 else { return points }
        return [points[0], points[(points.count - 1) / 2], points[points.count - 1]]
    }

    private var accessibilityValue: Text {
        guard let first = points.first, let last = points.last else { return Text(verbatim: "") }
        return Text("insights.chart.scoreTrend.a11y \(formattedValue(first.value)) \(formattedValue(last.value))")
    }

    var body: some View {
        let chartDomain = yDomain
        let dateLabel = String(localized: "insights.chart.date.label")
        let baselineLabel = String(localized: "insights.chart.baseline.label")
        let valueLabel = String(localized: "insights.chart.value.label")

        Chart(points) { point in
            if points.count > 1 {
                AreaMark(
                    x: .value(dateLabel, point.position),
                    yStart: .value(baselineLabel, chartDomain.lowerBound),
                    yEnd: .value(valueLabel, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(
                    colors: [tint.opacity(0.14), tint.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }

            LineMark(
                x: .value(dateLabel, point.position),
                y: .value(valueLabel, point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            if points.count <= 12 || point.id == points.last?.id {
                PointMark(
                    x: .value(dateLabel, point.position),
                    y: .value(valueLabel, point.value)
                )
                .foregroundStyle(tint)
                .symbolSize(22)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: chartDomain, range: .plotDimension(startPadding: 4, endPadding: 6))
        .chartYAxis(.hidden)
        .chartXAxis {
            if showsXAxis {
                AxisMarks(values: axisPoints.map(\.position)) { value in
                    AxisValueLabel(anchor: .top) {
                        if let position = value.as(Double.self),
                           let point = axisPoints.first(where: { $0.position == position }) {
                            Text(point.date, format: .dateTime.month(.defaultDigits).day(.defaultDigits))
                        }
                    }
                    .foregroundStyle(labelColor)
                }
            }
        }
        .chartPlotStyle { $0.clipped() }
        .frame(minHeight: 0, maxHeight: .infinity)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityValue(accessibilityValue)
    }

    private func formattedValue(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(isPitch ? 1 : 0)))
        return isPitch ? formatted + " " + String(localized: "common.unit.hertz") : formatted
    }
}
