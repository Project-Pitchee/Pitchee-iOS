//
//  MonitorCharts.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/5.
//

import SwiftUI

/// Chart surfaces deliberately have no surrounding chrome. The monitor page
/// supplies their size and background so the data remains the dominant element.
struct MonitorSpectrumPlot: View {
    let frame: MonitorSpectrumFrame?
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption2) private var scaledLabelSize = 11.0

    var body: some View {
        Canvas { context, size in
            let layout = MonitorChartLayout(size: size, labelSize: scaledLabelSize,
                                            increasedContrast: contrast == .increased)
            let plot = layout.plot
            layout.drawUnits(
                vertical: String(localized: "monitor.unit.dbfs"),
                horizontal: String(localized: "monitor.unit.hertz"),
                in: &context
            )

            let levels = plot.height < 140 ? [0, -50, -100] : [0, -25, -50, -75, -100]
            for level in levels {
                let y = plot.minY + plot.height * Double(-level) / 100
                context.draw(layout.label(level.formatted()),
                             at: CGPoint(x: plot.minX - 8, y: y), anchor: .trailing)
                layout.drawGrid(from: CGPoint(x: plot.minX, y: y),
                                to: CGPoint(x: plot.maxX, y: y),
                                baseline: level == -100, in: &context)
            }

            // A logarithmic axis puts 40 and 100 Hz close together. Dropping
            // the latter on compact plots keeps their labels from colliding.
            let frequencies: [Double] = plot.width < 260 ? [40, 1_000, 8_000] : [40, 100, 1_000, 8_000]
            for (index, frequency) in frequencies.enumerated() {
                let x = spectrumX(frequency, in: plot)
                context.draw(layout.label(MonitorChartLayout.frequencyLabel(frequency)),
                             at: CGPoint(x: x, y: plot.maxY + layout.tickOffset),
                             anchor: index == 0 ? .leading : (index == frequencies.count - 1 ? .trailing : .center))
            }

            guard let frame, frame.isValid else { return }
            var trace = Path()
            var firstPoint: CGPoint?
            var lastPoint: CGPoint?
            for (index, magnitude) in frame.magnitudesDB.enumerated() {
                let frequency = Double(index) * frame.binWidthHz
                guard MonitorSpectrumFrame.frequencyRange.contains(frequency) else { continue }
                let point = CGPoint(
                    x: spectrumX(frequency, in: plot),
                    y: plot.minY + plot.height * -Double(min(0, max(-100, magnitude))) / 100
                )
                if firstPoint == nil {
                    trace.move(to: point)
                    firstPoint = point
                } else {
                    trace.addLine(to: point)
                }
                lastPoint = point
            }

            context.clip(to: Path(plot.insetBy(dx: -6, dy: -6)))
            if let firstPoint, let lastPoint {
                var fill = trace
                fill.addLine(to: CGPoint(x: lastPoint.x, y: plot.maxY))
                fill.addLine(to: CGPoint(x: firstPoint.x, y: plot.maxY))
                fill.closeSubpath()
                context.fill(fill, with: .linearGradient(
                    Gradient(colors: [.pitcheeAccent.opacity(0.20), .pitcheeAccent.opacity(0.015)]),
                    startPoint: CGPoint(x: plot.midX, y: plot.minY),
                    endPoint: CGPoint(x: plot.midX, y: plot.maxY)
                ))
            }
            context.stroke(trace, with: .color(.pitcheeAccent),
                           style: StrokeStyle(lineWidth: contrast == .increased ? 2.6 : 2,
                                              lineCap: .round, lineJoin: .round))

            // The marker matches the strongest visible FFT bin. Silence has
            // no marker, consistent with the page's frequency readout.
            if let peak = frame.peak {
                let point = CGPoint(
                    x: spectrumX(peak.frequencyHz, in: plot),
                    y: plot.minY + plot.height * -Double(min(0, max(-100, peak.amplitudeDBFS))) / 100
                )
                var guide = Path()
                guide.move(to: CGPoint(x: point.x, y: point.y + 7))
                guide.addLine(to: CGPoint(x: point.x, y: plot.maxY))
                context.stroke(guide, with: .color(.pitcheeAccent.opacity(0.24)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                layout.drawMarker(at: point, in: &context)
            }
        }
        .clipped()
    }

    private func spectrumX(_ frequency: Double, in plot: CGRect) -> Double {
        plot.minX + plot.width * log(frequency / 40) / log(8_000.0 / 40)
    }
}

struct MonitorPitchPlot: View {
    let samples: [LivePitchSample]
    let timeRange: ClosedRange<Double>
    let cursorTime: Double
    let frequencyRange: ClosedRange<Double>
    let averagePitch: Double?

    init(
        samples: [LivePitchSample],
        timeRange: ClosedRange<Double>,
        cursorTime: Double,
        frequencyRange: ClosedRange<Double> = 50...1_000,
        averagePitch: Double? = nil
    ) {
        self.samples = samples
        self.timeRange = timeRange
        self.cursorTime = cursorTime
        self.frequencyRange = frequencyRange
        self.averagePitch = averagePitch
    }

    var body: some View {
        ZStack {
            // Grid text is independent of live samples. Keep it on its own
            // surface so a new trace does not resolve and lay it out again.
            MonitorPitchGrid(frequencyRange: frequencyRange)
            MonitorPitchTimeAxis(
                start: timeLabel(timeRange.lowerBound),
                middle: timeLabel((timeRange.lowerBound + timeRange.upperBound) / 2),
                end: timeLabel(timeRange.upperBound)
            )
            MonitorPitchAverageLine(
                averagePitch: averagePitch,
                frequencyRange: frequencyRange
            )
            MonitorPitchTrace(
                samples: samples,
                timeRange: timeRange,
                cursorTime: cursorTime,
                frequencyRange: frequencyRange
            )
            .animation(
                .easeOut(duration: 0.06),
                value: timeRange.upperBound
            )
        }
        .clipped()
    }

    private func timeLabel(_ seconds: Double) -> String {
        max(0, seconds).formatted(.number.precision(.fractionLength(1)))
    }
}

private struct MonitorPitchGrid: View {
    let frequencyRange: ClosedRange<Double>
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption2) private var scaledLabelSize = 11.0

    var body: some View {
        Canvas { context, size in
            let layout = MonitorChartLayout(size: size, labelSize: scaledLabelSize,
                                            increasedContrast: contrast == .increased,
                                            frequencyRange: frequencyRange)
            let plot = layout.plot
            layout.drawUnits(
                vertical: String(localized: "monitor.unit.hertz"),
                horizontal: String(localized: "monitor.unit.seconds"),
                in: &context
            )

            let frequencies = frequencyTicks(compact: plot.height < 140)
            for frequency in frequencies {
                let y = layout.pitchY(frequency)
                context.draw(layout.label(MonitorChartLayout.frequencyLabel(frequency)),
                             at: CGPoint(x: plot.minX - 8, y: y), anchor: .trailing)
                layout.drawGrid(from: CGPoint(x: plot.minX, y: y),
                                to: CGPoint(x: plot.maxX, y: y),
                                baseline: frequency == frequencyRange.lowerBound, in: &context)
            }

        }
    }

    private func frequencyTicks(compact: Bool) -> [Double] {
        let span = max(1, frequencyRange.upperBound - frequencyRange.lowerBound)
        let step = span <= 120 ? 20.0
            : span <= 250 ? 50
            : span <= 600 ? 100
            : 200
        var ticks: [Double] = []
        var frequency = ceil(frequencyRange.lowerBound / step) * step
        while frequency <= frequencyRange.upperBound {
            ticks.append(frequency)
            frequency += step
        }
        if frequencyRange.contains(165), !ticks.contains(where: { abs($0 - 165) < 0.5 }) {
            ticks.append(165)
            ticks.sort()
        }
        if compact, ticks.count > 3 {
            let middle = ticks[ticks.count / 2]
            ticks = [ticks[0], middle, ticks[ticks.count - 1]]
        }
        return ticks
    }
}

private struct MonitorPitchTimeAxis: View {
    let start: String
    let middle: String
    let end: String
    @ScaledMetric(relativeTo: .caption2) private var scaledLabelSize = 11.0

    var body: some View {
        Canvas { context, size in
            let layout = MonitorChartLayout(size: size, labelSize: scaledLabelSize,
                                            increasedContrast: false)
            let plot = layout.plot
            let longestTimeLabel = max(start.count, middle.count, end.count)
            let labelWidth = Double(longestTimeLabel) * layout.labelSize * 0.65
            let fractions: [Double] = plot.width >= labelWidth * 3 + 40 ? [0, 0.5, 1] : [0, 1]
            for fraction in fractions {
                let x = plot.minX + plot.width * fraction
                let label = fraction == 0 ? start : (fraction == 1 ? end : middle)
                context.draw(layout.label(label),
                             at: CGPoint(x: x, y: plot.maxY + layout.tickOffset),
                             anchor: fraction == 0 ? .leading : (fraction == 1 ? .trailing : .center))
            }

        }
    }
}

private struct MonitorPitchAverageLine: View {
    let averagePitch: Double?
    let frequencyRange: ClosedRange<Double>
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption2) private var scaledLabelSize = 11.0

    var body: some View {
        GeometryReader { geometry in
            if let averagePitch,
               averagePitch.isFinite,
               frequencyRange.contains(averagePitch) {
                let layout = MonitorChartLayout(
                    size: geometry.size,
                    labelSize: scaledLabelSize,
                    increasedContrast: contrast == .increased,
                    frequencyRange: frequencyRange
                )
                let y = layout.pitchY(averagePitch)
                let labelY = max(layout.plot.minY + layout.labelSize * 0.7, y - 15)

                Group {
                    Rectangle()
                        .fill(Color.pitcheeAccent.opacity(contrast == .increased ? 0.95 : 0.78))
                        .frame(width: layout.plot.width, height: contrast == .increased ? 2.5 : 1.5)
                        .position(x: layout.plot.midX, y: y)

                    HStack(spacing: 3) {
                        Text("analysis.pitchScale.averageMarker")
                        Text(verbatim: "\(Int(averagePitch.rounded())) Hz")
                    }
                    .font(.system(size: layout.labelSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.pitcheeAccent)
                    .monospacedDigit()
                    .frame(width: layout.plot.width, alignment: .trailing)
                    .position(x: layout.plot.midX, y: labelY)
                }
                .transition(.identity)
                .animation(
                    .easeOut(duration: 0.1),
                    value: averagePitch
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MonitorPitchTrace: View, Animatable {
    let samples: [LivePitchSample]
    var timeRange: ClosedRange<Double>
    var cursorTime: Double
    let frequencyRange: ClosedRange<Double>
    @AppStorage(AnalyzerSettingsKey.pitchChartStyle) private var chartStyle = PitchChartStyle.curve.rawValue
    @AppStorage(AnalyzerSettingsKey.pitchGapMilliseconds) private var gapMilliseconds = 200.0
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption2) private var scaledLabelSize = 11.0

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get {
            AnimatablePair(
                timeRange.lowerBound,
                AnimatablePair(timeRange.upperBound, cursorTime)
            )
        }
        set {
            timeRange = newValue.first...max(newValue.first + 0.001, newValue.second.first)
            cursorTime = newValue.second.second
        }
    }

    var body: some View {
        Canvas { context, size in
            let layout = MonitorChartLayout(size: size, labelSize: scaledLabelSize,
                                            increasedContrast: contrast == .increased,
                                            frequencyRange: frequencyRange)
            let plot = layout.plot
            let duration = max(0.001, timeRange.upperBound - timeRange.lowerBound)
            let drawsDots = chartStyle == PitchChartStyle.dots.rawValue
            let maximumGap = max(0.05, min(1.0, gapMilliseconds / 1_000))
            var trace = Path()
            var dots = Path()
            var previousTime: Double?
            for sample in TimelineSearch.samples(in: samples, range: timeRange, time: \.elapsedTime) {
                guard let pitch = sample.pitchHz,
                      pitch.isFinite, frequencyRange.contains(pitch) else {
                    previousTime = nil
                    continue
                }
                let point = CGPoint(
                    x: plot.minX + plot.width * (sample.elapsedTime - timeRange.lowerBound) / duration,
                    y: layout.pitchY(pitch)
                )
                if drawsDots {
                    dots.addEllipse(in: CGRect(x: point.x - 2.2, y: point.y - 2.2,
                                               width: 4.4, height: 4.4))
                } else {
                    if let previousTime, (0...maximumGap).contains(sample.elapsedTime - previousTime) {
                        trace.addLine(to: point)
                    } else {
                        trace.move(to: point)
                    }
                }
                previousTime = sample.elapsedTime
            }

            context.clip(to: Path(plot.insetBy(dx: -6, dy: -6)))
            if drawsDots {
                context.fill(dots, with: .color(.pitcheeAccent))
            } else {
                context.stroke(trace, with: .color(.pitcheeAccent),
                               style: StrokeStyle(lineWidth: contrast == .increased ? 3 : 2.4,
                                                  lineCap: .round, lineJoin: .round))
            }

            guard !samples.isEmpty, timeRange.contains(cursorTime) else { return }
            let cursorX = plot.minX + plot.width * (cursorTime - timeRange.lowerBound) / duration
            var cursor = Path()
            cursor.move(to: CGPoint(x: cursorX, y: plot.minY))
            cursor.addLine(to: CGPoint(x: cursorX, y: plot.maxY))
            context.stroke(cursor, with: .color(.secondary.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

            // Use the real sample position rather than drawing an interpolated
            // point under the cursor or carrying a pitch through silence.
            if let sample = TimelineSearch.latest(in: samples, at: cursorTime, time: \.elapsedTime),
               cursorTime - sample.elapsedTime <= 0.15,
               timeRange.contains(sample.elapsedTime), let pitch = sample.pitchHz,
               pitch.isFinite, frequencyRange.contains(pitch) {
                let point = CGPoint(
                    x: plot.minX + plot.width * (sample.elapsedTime - timeRange.lowerBound) / duration,
                    y: layout.pitchY(pitch)
                )
                layout.drawMarker(at: point, in: &context)
            }
        }
        .clipped()
    }

}

private struct MonitorChartLayout {
    let plot: CGRect
    let labelSize: Double
    let increasedContrast: Bool
    let frequencyRange: ClosedRange<Double>
    var tickOffset: Double { labelSize / 2 + 11 }

    func pitchY(_ frequency: Double) -> Double {
        let fraction = (frequency - frequencyRange.lowerBound)
            / (frequencyRange.upperBound - frequencyRange.lowerBound)
        return plot.minY + plot.height * (1 - min(1, max(0, fraction)))
    }

    init(
        size: CGSize,
        labelSize: Double,
        increasedContrast: Bool,
        frequencyRange: ClosedRange<Double> = 50...1_000
    ) {
        // Tick labels supplement the fully scalable readout and accessible
        // range description. Capping these preserves space for the trace.
        self.labelSize = min(14, max(10, labelSize))
        self.increasedContrast = increasedContrast
        self.frequencyRange = frequencyRange
        let leftMargin = max(34, self.labelSize * 3.1)
        let topMargin = self.labelSize + 17
        let bottomMargin = self.labelSize + 19
        plot = CGRect(x: leftMargin, y: topMargin,
                      width: max(1, size.width - leftMargin - 7),
                      height: max(1, size.height - topMargin - bottomMargin))
    }

    func label(_ value: String) -> Text {
        Text(verbatim: value)
            .font(.system(size: labelSize, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundColor(.secondary)
    }

    func drawUnits(vertical: String, horizontal: String, in context: inout GraphicsContext) {
        context.draw(label(vertical), at: CGPoint(x: plot.minX, y: 0), anchor: .topLeading)
        context.draw(label(horizontal), at: CGPoint(x: plot.maxX, y: 0), anchor: .topTrailing)
    }

    func drawGrid(from start: CGPoint, to end: CGPoint, baseline: Bool = false,
                  in context: inout GraphicsContext) {
        var grid = Path()
        grid.move(to: start)
        grid.addLine(to: end)
        let opacity = increasedContrast ? 0.20 : (baseline ? 0.12 : 0.06)
        context.stroke(grid, with: .color(.primary.opacity(opacity)), lineWidth: 0.5)
    }

    func drawMarker(at point: CGPoint, in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)),
                     with: .color(.pitcheeAccent.opacity(0.13)))
        context.fill(Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)),
                     with: .color(.pitcheeAccent))
        context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)),
                     with: .color(Color(uiColor: .systemBackground)))
    }

    static func frequencyLabel(_ frequency: Double) -> String {
        if frequency >= 1_000 {
            return "\(Int(frequency / 1_000))k"
        }
        return Int(frequency).formatted()
    }
}
