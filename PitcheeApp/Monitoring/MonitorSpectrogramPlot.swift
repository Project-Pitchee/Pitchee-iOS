//
//  MonitorSpectrogramPlot.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/6.
//

import SwiftUI

/// Each FFT frame is rasterized once by the capture worker. Retained columns
/// are composed off the main actor into one visible bitmap.
struct MonitorSpectrogramPlot: View {
    let columns: [MonitorSpectrogramColumn]
    let timeRange: ClosedRange<TimeInterval>
    let cursorTime: TimeInterval

    var body: some View {
        ZStack {
            MonitorSpectrogramHeatmap(columns: columns, timeRange: timeRange)
            MonitorSpectrogramFrequencyAxis()
            MonitorSpectrogramTimeAxis(timeRange: timeRange)
            if !columns.isEmpty {
                MonitorSpectrogramCursor(timeRange: timeRange, cursorTime: cursorTime)
            }
        }
        .background(MonitorSpectrogramStyle.background)
        .clipShape(.rect(cornerRadius: 16))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("monitor.spectrogram")
    }
}

private struct MonitorSpectrogramHeatmap: View {
    let columns: [MonitorSpectrogramColumn]
    let timeRange: ClosedRange<TimeInterval>
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 11.0
    @Environment(\.displayScale) private var displayScale
    @State private var rendered: RenderedSpectrogram?

    var body: some View {
        GeometryReader { geometry in
            let layout = MonitorSpectrogramLayout(size: geometry.size, labelSize: labelSize)
            let request = SpectrogramRenderRequest(
                columns: columns, timeRange: timeRange,
                pixelWidth: min(4_096, max(1, Int(ceil(layout.plot.width * displayScale))))
            )
            Canvas { context, _ in
                guard !columns.isEmpty, let rendered else { return }
                context.clip(to: Path(layout.plot))
                let start = layout.x(rendered.timeRange.lowerBound, range: timeRange)
                let end = layout.x(rendered.timeRange.upperBound, range: timeRange)
                let rect = CGRect(x: start, y: layout.plot.minY,
                                  width: end - start, height: layout.plot.height)
                // One draw call, with vertical filtering for narrow harmonics.
                context.draw(Image(decorative: rendered.image, scale: 1).interpolation(.medium), in: rect)
            }
            .task(id: request) {
                let worker = Task.detached(priority: .userInitiated) {
                    MonitorSpectrogramRasterizer.makeImage(
                        columns: request.columns, timeRange: request.timeRange,
                        pixelWidth: request.pixelWidth
                    )
                }
                let image = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled else { return }
                rendered = image.map { RenderedSpectrogram(image: $0, timeRange: request.timeRange) }
            }
        }
    }
}

private struct RenderedSpectrogram {
    let image: CGImage
    let timeRange: ClosedRange<TimeInterval>
}

/// Cursor-only redraws reuse the bitmap. Replacing a frame at an existing
/// timestamp still invalidates the cache because its image identity changed.
nonisolated private struct SpectrogramRenderRequest: Equatable, Sendable {
    let columns: [MonitorSpectrogramColumn]
    let timeRange: ClosedRange<TimeInterval>
    let pixelWidth: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.timeRange == rhs.timeRange && lhs.pixelWidth == rhs.pixelWidth
            && lhs.columns.count == rhs.columns.count
            && zip(lhs.columns, rhs.columns).allSatisfy {
                $0.elapsedTime == $1.elapsedTime && $0.image === $1.image
            }
    }
}

private struct MonitorSpectrogramFrequencyAxis: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 11.0

    var body: some View {
        Canvas { context, size in
            let layout = MonitorSpectrogramLayout(size: size, labelSize: labelSize)
            context.draw(layout.label(String(localized: "monitor.unit.hertz")),
                         at: CGPoint(x: layout.plot.maxX + 10, y: 12), anchor: .leading)

            var previousY = -Double.infinity
            for frequency in [8_000.0, 4_000, 2_000, 1_000, 500, 300, 200, 100, 40] {
                let y = layout.plot.minY + layout.plot.height
                    * MonitorSpectrogramRasterizer.verticalFraction(for: frequency)
                guard y - previousY >= layout.labelSize + 8 else { continue }
                previousY = y
                context.draw(layout.label(frequency.formatted(.number.grouping(.never))),
                             at: CGPoint(x: layout.plot.maxX + 10, y: y), anchor: .leading)
                var tick = Path()
                tick.move(to: CGPoint(x: layout.plot.maxX, y: y))
                tick.addLine(to: CGPoint(x: layout.plot.maxX + 4, y: y))
                context.stroke(tick, with: .color(.white.opacity(0.65)), lineWidth: 1)
                var grid = Path()
                grid.move(to: CGPoint(x: layout.plot.minX, y: y))
                grid.addLine(to: CGPoint(x: layout.plot.maxX, y: y))
                context.stroke(grid, with: .color(.white.opacity(contrast == .increased ? 0.20 : 0.08)),
                               lineWidth: 0.5)
            }

            let scale = CGRect(x: 0, y: layout.plot.minY, width: 4, height: layout.plot.height)
            context.fill(Path(scale), with: .linearGradient(
                Gradient(colors: MonitorSpectrogramStyle.colors.reversed()),
                startPoint: CGPoint(x: 0, y: scale.minY),
                endPoint: CGPoint(x: 0, y: scale.maxY)
            ))
        }
    }
}

private struct MonitorSpectrogramTimeAxis: View {
    let timeRange: ClosedRange<TimeInterval>
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 11.0

    var body: some View {
        Canvas { context, size in
            let layout = MonitorSpectrogramLayout(size: size, labelSize: labelSize)
            let fractions = layout.plot.width > labelSize * 18 ? [0.0, 0.5, 1] : [0.0, 1]
            for fraction in fractions {
                let time = timeRange.lowerBound + (timeRange.upperBound - timeRange.lowerBound) * fraction
                let text = time.formatted(.number.precision(.fractionLength(1)))
                context.draw(layout.label(text),
                             at: CGPoint(x: layout.plot.minX + layout.plot.width * fraction,
                                         y: layout.plot.maxY + layout.labelSize + 4),
                             anchor: fraction == 0 ? .leading : (fraction == 1 ? .trailing : .center))
            }
            context.draw(layout.label(String(localized: "monitor.unit.seconds")),
                         at: CGPoint(x: layout.plot.maxX + 10, y: layout.plot.maxY + layout.labelSize + 4),
                         anchor: .leading)
        }
    }
}

private struct MonitorSpectrogramCursor: View {
    let timeRange: ClosedRange<TimeInterval>
    let cursorTime: TimeInterval
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 11.0

    var body: some View {
        Canvas { context, size in
            guard timeRange.contains(cursorTime) else { return }
            let layout = MonitorSpectrogramLayout(size: size, labelSize: labelSize)
            let x = min(layout.plot.maxX - 0.5, max(layout.plot.minX, layout.x(cursorTime, range: timeRange)))
            var cursor = Path()
            cursor.move(to: CGPoint(x: x, y: layout.plot.minY))
            cursor.addLine(to: CGPoint(x: x, y: layout.plot.maxY))
            context.stroke(cursor, with: .color(.white.opacity(0.75)), lineWidth: 1)
        }
    }
}

struct MonitorSpectrogramLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "−90")
            LinearGradient(colors: MonitorSpectrogramStyle.colors, startPoint: .leading, endPoint: .trailing)
                .frame(width: 88, height: 4)
                .clipShape(.capsule)
                .accessibilityHidden(true)
            Text(verbatim: "0")
            Text("monitor.unit.dbfs")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
    }
}

private enum MonitorSpectrogramStyle {
    // Match the amplitude palette used by MonitorSpectrogramRasterizer.
    static let colors: [Color] = [
        Color(red: 18 / 255.0, green: 11 / 255.0, blue: 112 / 255.0),
        Color(red: 89 / 255.0, green: 15 / 255.0, blue: 164 / 255.0),
        Color(red: 189 / 255.0, green: 33 / 255.0, blue: 151 / 255.0),
        Color(red: 1, green: 128 / 255.0, blue: 55 / 255.0),
        Color(red: 1, green: 250 / 255.0, blue: 74 / 255.0)
    ]
    static let background = colors[0]
}

private struct MonitorSpectrogramLayout {
    let plot: CGRect
    let labelSize: Double

    init(size: CGSize, labelSize: Double) {
        self.labelSize = labelSize
        let rightMargin = max(54, labelSize * 3.4 + 16)
        plot = CGRect(x: 12, y: labelSize + 18,
                      width: max(1, size.width - rightMargin - 12),
                      height: max(1, size.height - labelSize * 3 - 30))
    }

    func x(_ time: TimeInterval, range: ClosedRange<TimeInterval>) -> Double {
        plot.minX + plot.width * (time - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)
    }

    func label(_ text: String) -> Text {
        Text(verbatim: text)
            .font(.system(size: labelSize).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
    }
}
