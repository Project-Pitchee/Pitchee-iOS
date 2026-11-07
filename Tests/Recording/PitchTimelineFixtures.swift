// Legacy export and accessibility adapters retained only for timeline regression tests.
// The application uses MonitorPitchPlot and RecordingExportView.
import Foundation
import SwiftUI
import Accessibility

nonisolated struct PitchAccessibilitySnapshot: Identifiable, Sendable {
    let id = UUID()
    let range: ClosedRange<TimeInterval>
    let samples: [LivePitchSample]

    init(samples: [LivePitchSample], elapsedTime: TimeInterval) {
        let end = max(PitchTimeline.visibleSeconds, elapsedTime.isFinite ? elapsedTime : 0)
        let range = (end - PitchTimeline.visibleSeconds)...end
        self.range = range
        self.samples = samples.filter { $0.elapsedTime.isFinite && range.contains($0.elapsedTime) }
            .sorted { $0.elapsedTime < $1.elapsedTime }
    }

    var voicedSegments: [[LivePitchSample]] {
        var segments: [[LivePitchSample]] = []
        var current: [LivePitchSample] = []
        for sample in samples {
            guard let pitch = sample.pitchHz, pitch.isFinite, pitch > 0 else {
                if !current.isEmpty { segments.append(current); current = [] }
                continue
            }
            if let last = current.last, sample.elapsedTime - last.elapsedTime > 0.4 {
                segments.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}

struct PitchChartDescriptor {
    let snapshot: PitchAccessibilitySnapshot

    func makeChartDescriptor() -> AXChartDescriptor {
        AXChartDescriptor(
            __title: String(localized: "recording.timeline.a11y"),
            summary: nil,
            xAxisDescriptor: xAxis,
            yAxisDescriptor: yAxis,
            series: series
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        descriptor.xAxis = xAxis
        descriptor.yAxis = yAxis
        descriptor.series = series
    }

    private var xAxis: AXNumericDataAxisDescriptor {
        AXNumericDataAxisDescriptor(
            title: String(localized: "recording.timeline.timeAxis"), range: snapshot.range,
            gridlinePositions: [], valueDescriptionProvider: { value in
                value.formatted(.number.precision(.fractionLength(1)))
            }
        )
    }

    private var yAxis: AXNumericDataAxisDescriptor {
        AXNumericDataAxisDescriptor(
            title: String(localized: "recording.timeline.pitchAxis"), range: 75...600,
            gridlinePositions: [75, 150, 300, 600], valueDescriptionProvider: { value in
                value.formatted(.number.precision(.fractionLength(0)))
            }
        )
    }

    private var series: [AXDataSeriesDescriptor] {
        snapshot.voicedSegments.map { segment in
            AXDataSeriesDescriptor(
                name: String(localized: "recording.timeline.series"),
                isContinuous: segment.count > 1,
                dataPoints: segment.compactMap { sample in
                    guard let pitch = sample.pitchHz, pitch.isFinite, pitch > 0 else { return nil }
                    return AXDataPoint(x: sample.elapsedTime, y: pitch)
                }
            )
        }
    }
}

struct PitchPlot: View {
    let samples: [LivePitchSample]
    let timeRange: ClosedRange<TimeInterval>
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 11.0
    @ScaledMetric(relativeTo: .caption2) private var labelWidth = 52.0

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(
                x: labelWidth, y: labelSize,
                width: max(1, size.width - labelWidth - 12),
                height: max(1, size.height - labelSize * 4)
            )
            for (index, label) in ["600 Hz", "300", "150", "75"].enumerated() {
                let y = plot.minY + plot.height * CGFloat(index) / 3
                context.draw(
                    Text(verbatim: label)
                        .font(.system(size: labelSize).monospacedDigit())
                        .foregroundStyle(.secondary),
                    at: CGPoint(x: plot.minX - 8, y: y),
                    anchor: .trailing
                )
                var grid = Path()
                grid.move(to: CGPoint(x: plot.minX, y: y))
                grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }

            let duration = max(0.001, timeRange.upperBound - timeRange.lowerBound)
            for index in 0...3 {
                let fraction = Double(index) / 3
                let seconds = timeRange.lowerBound + duration * fraction
                let label = seconds.formatted(.number.precision(.fractionLength(1))) + " s"
                context.draw(
                    Text(verbatim: label)
                        .font(.system(size: labelSize).monospacedDigit())
                        .foregroundStyle(.secondary),
                    at: CGPoint(x: plot.minX + plot.width * fraction, y: plot.maxY + labelSize * 1.6),
                    anchor: index == 0 ? .leading : (index == 3 ? .trailing : .center)
                )
            }

            var line = Path()
            var previousTime: TimeInterval?
            for sample in TimelineSearch.samples(in: samples, range: timeRange, time: \.elapsedTime,
                                                 includingNeighbors: true) {
                guard let pitch = sample.pitchHz, pitch.isFinite, pitch > 0 else {
                    previousTime = nil
                    continue
                }
                let progress = (log2(min(max(pitch, 75), 600)) - log2(75)) / 3
                let point = CGPoint(
                    x: plot.minX + plot.width * (sample.elapsedTime - timeRange.lowerBound) / duration,
                    y: plot.minY + plot.height * (1 - progress)
                )
                if let previousTime, sample.elapsedTime - previousTime <= 0.4 {
                    line.addLine(to: point)
                } else {
                    line.move(to: point)
                }
                previousTime = sample.elapsedTime
            }
            context.clip(to: Path(plot.insetBy(dx: 0, dy: -1)))
            context.stroke(line, with: .color(.pitcheeAccent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .clipped()
    }
}

struct PitchTimelineImage: View {
    let timeline: PitchTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("export.pitchImage.chart.title").font(.system(size: 26, weight: .semibold))
                    Text("export.pitchImage.chart.duration \(timeline.duration.formatted(.number.precision(.fractionLength(1))))")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("common.brand.name").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
            }
            ForEach(timeline.imageRows) { row in
                PitchPlot(samples: row.samples, timeRange: row.range)
                    .frame(height: 150)
            }
            Text("export.pitchImage.chart.gapNote")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 960)
        .background(.white)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .medium)
        .tint(Color.pitcheeAccent)
    }
}
