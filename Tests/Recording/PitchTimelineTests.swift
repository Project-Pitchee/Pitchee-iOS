//
//  PitchTimelineTests.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/19.
//

import AppKit
import SwiftUI
import Accessibility

@main
enum PitchTimelineTests {
    @MainActor
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { fatalError(message) }
        }

        let samples = stride(from: 0.0, through: 37.2, by: 0.05).map { time in
            LivePitchSample(
                elapsedTime: time,
                pitchHz: (17...19).contains(time) ? nil : 200 + 60 * sin(time * 2)
            )
        }
        let timeline = PitchTimeline(samples: samples, duration: 37.2)
        let rows = timeline.imageRows
        check(rows.count == 3, "The export must include audio beyond the live viewport")
        check(rows.first?.range.lowerBound == 0, "The image must begin at recording start")
        check(rows.last?.range.upperBound == 37.2, "The image must include the recording tail")
        check(zip(rows, rows.dropFirst()).allSatisfy { $0.range.upperBound == $1.range.lowerBound },
              "Image rows must have no missing time")
        check(samples.allSatisfy { sample in
            rows.contains { row in
                row.range.contains(sample.elapsedTime) && row.samples.contains { $0.id == sample.id }
            }
        }, "All original samples must appear in an image row")
        check(rows[1].samples.contains { $0.pitchHz == nil }, "Unvoiced gaps must survive export")

        let longTimeline = PitchTimeline(samples: [], duration: 7_201)
        check(longTimeline.imageRows.count <= 24, "Long recordings must use bounded image dimensions")
        check(longTimeline.imageRows.last?.range.upperBound == 7_201,
              "Long recordings must retain their complete time range")

        let renderer = ImageRenderer(content: PitchTimelineImage(timeline: timeline))
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.cgImage else { fatalError("Image rendering failed") }
        check(image.width == 1_920, "PNG must render at full export resolution")
        check(image.height > 1_100, "The renderer must include every row, not a viewport screenshot")
        let output = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/pitchee-pitch-export-preview.png"
        try output.write(to: URL(fileURLWithPath: path))
        let decoded = NSBitmapImageRep(data: output)
        check(decoded?.pixelsHigh == image.height, "Saved PNG must preserve full image height")

        let silence = PitchTimeline(samples: [LivePitchSample(elapsedTime: 0.1, pitchHz: nil)], duration: 0.2)
        let silenceRenderer = ImageRenderer(content: PitchTimelineImage(timeline: silence))
        check(silenceRenderer.cgImage != nil, "Short, unvoiced recordings must still export")

        let snapshot = PitchAccessibilitySnapshot(samples: [
            .init(elapsedTime: 0, pitchHz: 100), // outside the visible window
            .init(elapsedTime: 1, pitchHz: 180),
            .init(elapsedTime: 1.1, pitchHz: 200),
            .init(elapsedTime: 1.2, pitchHz: nil),
            .init(elapsedTime: 1.3, pitchHz: .nan),
            .init(elapsedTime: 1.4, pitchHz: .infinity),
            .init(elapsedTime: 1.5, pitchHz: 0),
            .init(elapsedTime: 1.6, pitchHz: -100),
            .init(elapsedTime: 1.7, pitchHz: 220),
            .init(elapsedTime: 3, pitchHz: 240), // a capture gap must split the line
            .init(elapsedTime: 4, pitchHz: 260),
            .init(elapsedTime: 5, pitchHz: 280), // outside the visible window
            .init(elapsedTime: .nan, pitchHz: 300)
        ], elapsedTime: 4)
        check(snapshot.range == 1...4, "Accessible data must match the three-second viewport")
        check(snapshot.samples.count == 10, "Keep gaps in the table while rejecting out-of-window and invalid times")
        check(snapshot.voicedSegments.map(\.count) == [2, 1, 1, 1], "Silence, invalid pitches, and capture gaps must split audio graph segments")
        let descriptor = PitchChartDescriptor(snapshot: snapshot).makeChartDescriptor()
        check(descriptor.series.count == 4, "The audio graph must preserve voiced segments")
        check(descriptor.series[0].isContinuous, "Adjacent voiced samples form a continuous line")
        check(!descriptor.series[1].isContinuous, "An isolated voiced sample is a discrete point")
        check(descriptor.series.reduce(0) { $0 + $1.dataPoints.count } == 5, "Audio graph points must exclude invalid and unvoiced pitches")
        let empty = PitchAccessibilitySnapshot(samples: [], elapsedTime: .nan)
        check(empty.range == 0...3, "An empty chart still has a valid time axis")
        PitchChartDescriptor(snapshot: empty).updateChartDescriptor(descriptor)
        check(descriptor.series.isEmpty, "Live descriptor updates must clear stale pitch data")
        check((descriptor.xAxis as? AXNumericDataAxisDescriptor)?.range == 0...3, "Live descriptor updates must replace the time axis")
        print("Pitch image checks: \(checks) checks passed; preview: \(path)")
    }
}
