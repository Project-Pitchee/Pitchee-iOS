//
//  RecordedAudioPlayerView.swift
//  Pitchee
//

import AVFoundation
import Combine
import SwiftUI

struct RecordedAudioPlayerView: View {
    @State private var playback: RecordedAudioPlaybackModel
    @State private var expanded = false
    @Environment(\.colorScheme) private var colorScheme

    private let f0Windows: [PitcheeAnalysisResult.PitchWindow]
    private let vfpWindows: [PitcheeAnalysisResult.VFPWindow]
    private let naturalnessWindows: [PitcheeAnalysisResult.NaturalnessWindow]

    init(
        audioURL: URL?,
        f0Windows: [PitcheeAnalysisResult.PitchWindow],
        vfpWindows: [PitcheeAnalysisResult.VFPWindow],
        naturalnessWindows: [PitcheeAnalysisResult.NaturalnessWindow]
    ) {
        self.f0Windows = f0Windows
        self.vfpWindows = vfpWindows
        self.naturalnessWindows = naturalnessWindows
        _playback = State(initialValue: RecordedAudioPlaybackModel(url: audioURL))
        #if DEBUG
        _expanded = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("-expand-player-preview")
                || ProcessInfo.processInfo.arguments.contains("-player-playing-preview")
                || ProcessInfo.processInfo.arguments.contains("-player-f0-gap-preview")
        )
        #else
        _expanded = State(initialValue: false)
        #endif
    }

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 125 / 255, green: 179 / 255, blue: 1)
            : Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    }

    private var playerBackground: Color {
        colorScheme == .dark
            ? Color(red: 23 / 255, green: 42 / 255, blue: 70 / 255)
            : Color(red: 228 / 255, green: 240 / 255, blue: 1)
    }

    private var playerContent: Color {
        colorScheme == .dark
            ? Color(red: 234 / 255, green: 243 / 255, blue: 1)
            : Color(red: 22 / 255, green: 52 / 255, blue: 92 / 255)
    }

    var body: some View {
        Group {
            if playback.isReady {
                if expanded {
                    expandedPlayer
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                } else {
                    collapsedPlayer
                        .transition(.opacity.combined(with: .scale(scale: 0.90)))
                }
            } else {
                disabledPlayer
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: expanded)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-player-playing-preview") {
                playback.seek(to: min(4.5, playback.duration / 2))
                playback.play()
            } else if ProcessInfo.processInfo.arguments.contains("-player-f0-gap-preview") {
                playback.seek(to: 2.875)
            }
            #endif
        }
        .onDisappear {
            playback.shutdown()
        }
    }

    private var collapsedPlayer: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                expanded = true
            }
            playback.play()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 16 / 255, green: 36 / 255, blue: 67 / 255))
                .frame(width: 52, height: 52)
                .background(accent, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SettingsCopy.text("展开并播放", "Expand and play"))
    }

    private var expandedPlayer: some View {
        VStack(spacing: 12) {
            PlaybackTransportControl(
                playback: playback,
                accent: accent
            )

            AudioPlaybackTimeline(
                playback: playback,
                f0Windows: f0Windows,
                vfpWindows: vfpWindows,
                naturalnessWindows: naturalnessWindows,
                accent: accent,
                content: playerContent
            )
            .frame(height: 248)
            .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            playerBackground,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var disabledPlayer: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color(red: 16 / 255, green: 36 / 255, blue: 67 / 255).opacity(0.55))
            .frame(width: 52, height: 52)
            .background(accent.opacity(0.28), in: Circle())
            .accessibilityLabel(SettingsCopy.text("录音播放不可用", "Recording playback unavailable"))
    }
}

private struct PlaybackTransportControl: View {
    @ObservedObject var playback: RecordedAudioPlaybackModel
    let accent: Color
    @State private var resumeAfterScrub = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                playback.togglePlayback()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 16 / 255, green: 36 / 255, blue: 67 / 255))
                    .frame(width: 44, height: 44)
                    .background(accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                playback.isPlaying
                    ? SettingsCopy.text("暂停", "Pause")
                    : SettingsCopy.text("播放", "Play")
            )

            Slider(
                value: Binding(
                    get: { playback.position },
                    set: { playback.seek(to: $0) }
                ),
                in: 0...max(playback.duration, 0.01),
                onEditingChanged: { editing in
                    if editing {
                        resumeAfterScrub = playback.isPlaying
                        playback.pause()
                    } else if resumeAfterScrub {
                        playback.play()
                        resumeAfterScrub = false
                    }
                }
            )
            .tint(accent)
            .accessibilityLabel(SettingsCopy.text("播放进度", "Playback position"))
        }
    }
}

@MainActor
private final class RecordedAudioPlaybackModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isReady = false
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var waveform: [Double] = []

    private var player: AVAudioPlayer?
    private var clock: Task<Void, Never>?
    private var sessionIsActive = false

    init(url: URL?) {
        super.init()
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player = player
        player.delegate = self
        player.prepareToPlay()
        duration = player.duration
        isReady = duration > 0

        Task { [weak self] in
            let waveform = await Task.detached(priority: .utility) {
                Self.loadWaveform(from: url)
            }.value
            guard let self else { return }
            self.waveform = waveform
        }
    }

    func play() {
        guard let player else { return }
        if position >= duration - 0.1 {
            seek(to: 0)
        }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startClock()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        clock?.cancel()
        clock = nil
        position = player?.currentTime ?? position
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(seconds, 0), duration)
        player?.currentTime = target
        position = target
        if target >= duration {
            isPlaying = false
            clock?.cancel()
            clock = nil
        }
    }

    func shutdown() {
        clock?.cancel()
        clock = nil
        player?.stop()
        isPlaying = false
        if sessionIsActive {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            sessionIsActive = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.clock?.cancel()
            self.clock = nil
            self.isPlaying = false
            self.position = self.duration
        }
    }

    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
                guard let self, let player = self.player, self.isPlaying else { return }
                self.position = min(self.duration, player.currentTime)
            }
        }
    }

    private func activateSessionIfNeeded() {
        guard !sessionIsActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? session.setActive(true)
        sessionIsActive = true
    }

    private nonisolated static func loadWaveform(from url: URL) -> [Double] {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
              ),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData else {
            return []
        }

        let frameCount = Int(buffer.frameLength)
        let sampleRate = file.processingFormat.sampleRate
        guard frameCount > 0, sampleRate > 0 else { return [] }

        let binsPerSecond = 100.0
        let binCount = max(1, Int(ceil(Double(frameCount) / sampleRate * binsPerSecond)))
        let framesPerBin = max(1, Int(ceil(Double(frameCount) / Double(binCount))))
        let channelCount = Int(file.processingFormat.channelCount)
        var peaks: [Double] = []
        peaks.reserveCapacity(binCount)

        var index = 0
        while index < frameCount {
            let end = min(frameCount, index + framesPerBin)
            var peak: Float = 0
            for frame in index..<end {
                for channel in 0..<channelCount {
                    peak = max(peak, abs(channels[channel][frame]))
                }
            }
            peaks.append(Double(peak))
            index = end
        }

        let maximum = peaks.max() ?? 0
        guard maximum > 0 else { return peaks }
        return peaks.map { min(1, $0 / maximum) }
    }
}

private struct PlaybackScoreMarkerView: View, Animatable {
    var score: Double
    let standardText: String
    let naturalnessText: String
    let content: Color

    var animatableData: Double {
        get { score }
        set { score = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let waveformHeight = min(136, size.height)
            let waveformTop = size.height - waveformHeight
            let markerHeight = min(36, waveformHeight)
            let markerWidth = 58.0
            let progress = min(max(score / 100, 0), 1)
            let centerY = waveformTop + waveformHeight * (1 - progress)
            let markerY = min(
                max(centerY - markerHeight / 2, waveformTop),
                waveformTop + waveformHeight - markerHeight
            )
            let rect = CGRect(
                x: max(0, size.width / 2 - markerWidth - 12),
                y: markerY,
                width: markerWidth,
                height: markerHeight
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: 4),
                with: .color(Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255))
            )
            context.draw(
                Text(verbatim: "S \(standardText)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(content),
                at: CGPoint(x: rect.midX, y: rect.minY + 10)
            )
            context.draw(
                Text(verbatim: "N \(naturalnessText)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(content),
                at: CGPoint(x: rect.midX, y: rect.minY + 26)
            )
        }
        .allowsHitTesting(false)
    }
}

private struct AudioPlaybackTimeline: View {
    @ObservedObject var playback: RecordedAudioPlaybackModel
    let f0Windows: [PitcheeAnalysisResult.PitchWindow]
    let vfpWindows: [PitcheeAnalysisResult.VFPWindow]
    let naturalnessWindows: [PitcheeAnalysisResult.NaturalnessWindow]
    let accent: Color
    let content: Color

    private let waveformBinsPerSecond = 100.0
    private let thresholdHz = 165.0

    private var waveform: [Double] { playback.waveform }
    private var position: TimeInterval { playback.position }
    private var duration: TimeInterval { playback.duration }

    private var windowSeconds: Double {
        min(2, max(0.05, duration))
    }

    private var viewportStart: Double {
        position - windowSeconds / 2
    }

    private var maximumFrequency: Double {
        let peak = f0Windows.compactMap(\.f0Hz).max() ?? 300
        return min(600, max(300, ceil(peak / 50) * 50))
    }

    var body: some View {
        GeometryReader { proxy in
            let currentF0 = f0Value(at: position)
            let currentY = currentF0.map {
                proxy.size.height * (1 - min(max($0, 0), maximumFrequency) / maximumFrequency)
            }
            let hasCurrentF0 = currentF0 != nil
            let standardScore = hasCurrentF0 ? vfpValue(at: position) : nil
            let naturalnessScore = hasCurrentF0 ? naturalnessValue(at: position) : nil
            let availableMarkerScores = [standardScore, naturalnessScore].compactMap { $0 }
            let markerScore = availableMarkerScores.isEmpty
                ? 0
                : availableMarkerScores.reduce(0, +) / Double(availableMarkerScores.count)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawTimeline(context: &context, size: size)
                }

                if let currentF0, let currentY {
                    Text(verbatim: "\(Int(currentF0.rounded())) Hz")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(
                            currentF0 > thresholdHz
                                ? Color.pitcheeTendencyPink
                                : Color.pitcheeTendencySky
                        )
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .position(
                            x: proxy.size.width / 2 + 42,
                            y: min(max(currentY + 20, 18), proxy.size.height - 18)
                        )
                }

                PlaybackScoreMarkerView(
                    score: markerScore,
                    standardText: scoreLabel(standardScore),
                    naturalnessText: scoreLabel(naturalnessScore),
                    content: content
                )
                .animation(
                    .spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0),
                    value: markerScore
                )
            }
            .clipped()
        }
    }

    private func drawTimeline(context: inout GraphicsContext, size: CGSize) {
        drawWaveform(context: &context, size: size)
        if hasF0 {
            let thresholdY = size.height * (1 - thresholdHz / maximumFrequency)
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: thresholdY))
                    path.addLine(to: CGPoint(x: size.width, y: thresholdY))
                },
                with: .color(content.opacity(0.34)),
                lineWidth: 1.5
            )
            context.draw(
                Text(verbatim: "165 Hz")
                    .font(.caption2)
                    .foregroundStyle(content.opacity(0.45)),
                at: CGPoint(x: 18, y: thresholdY + 10)
            )
            drawF0(context: &context, size: size)
        }

        var cursor = Path()
        cursor.move(to: CGPoint(x: size.width / 2, y: 0))
        cursor.addLine(to: CGPoint(x: size.width / 2, y: size.height))
        context.stroke(cursor, with: .color(accent), lineWidth: 3)
    }

    private func drawWaveform(context: inout GraphicsContext, size: CGSize) {
        let waveformHeight = min(136, size.height)
        let waveformTop = size.height - waveformHeight
        let centerY = waveformTop + waveformHeight / 2
        let spacing = 5.0
        let barCount = max(1, Int(size.width / spacing))

        for index in 0..<barCount {
            let fraction = (Double(index) + 0.5) / Double(barCount)
            let time = viewportStart + fraction * windowSeconds
            guard time >= 0, time <= duration else { continue }
            let bin = Int(time * waveformBinsPerSecond)
            guard waveform.indices.contains(bin) else { continue }
            let amplitude = waveform[bin]
            let barHeight = max(2, amplitude * waveformHeight * 0.82)
            let x = (Double(index) + 0.5) * spacing
            let recency = Double(index) / Double(max(1, barCount - 1))
            var bar = Path()
            bar.move(to: CGPoint(x: x, y: centerY - barHeight / 2))
            bar.addLine(to: CGPoint(x: x, y: centerY + barHeight / 2))
            context.stroke(
                bar,
                with: .color(accent.opacity(0.18 + 0.58 * recency)),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
            )
        }
    }

    private func drawF0(context: inout GraphicsContext, size: CGSize) {
        for run in f0Runs {
            guard run.count > 1 else { continue }
            for index in 0..<(run.count - 1) {
                let previous = run[index]
                let current = run[index + 1]
                guard current.time >= viewportStart - 0.35,
                      previous.time <= viewportStart + windowSeconds + 0.35 else { continue }

                let before = run[max(0, index - 1)]
                let after = run[min(run.count - 1, index + 2)]
                var previousPoint = CGPoint(
                    x: xPosition(previous.time, width: size.width),
                    y: yPosition(previous.hz, height: size.height)
                )
                var previousHz = previous.hz

                for step in 1...12 {
                    let t = Double(step) / 12
                    let hz = catmullRom(
                        previous: before.hz,
                        start: previous.hz,
                        end: current.hz,
                        after: after.hz,
                        t: t
                    )
                    let point = CGPoint(
                        x: xPosition(
                            previous.time + (current.time - previous.time) * t,
                            width: size.width
                        ),
                        y: yPosition(hz, height: size.height)
                    )
                    let color = (previousHz + hz) / 2 > thresholdHz
                        ? Color.pitcheeTendencyPink
                        : Color.pitcheeTendencySky
                    var line = Path()
                    line.move(to: previousPoint)
                    line.addLine(to: point)
                    context.stroke(
                        line,
                        with: .color(color),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    previousPoint = point
                    previousHz = hz
                }
            }
        }
    }

    private var f0Runs: [[(time: Double, hz: Double)]] {
        var runs: [[(time: Double, hz: Double)]] = []
        var current: [(time: Double, hz: Double)] = []
        var previousTime: Double?

        for window in f0Windows {
            guard let hz = window.f0Hz, hz.isFinite else {
                if !current.isEmpty { runs.append(current) }
                current = []
                previousTime = nil
                continue
            }
            let time = (window.startSeconds + window.endSeconds) / 2
            if let previousTime, time - previousTime > 0.35 {
                if !current.isEmpty { runs.append(current) }
                current = []
            }
            current.append((time, hz))
            previousTime = time
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    private var hasF0: Bool {
        f0Windows.contains { window in
            guard let hz = window.f0Hz else { return false }
            return hz.isFinite && hz > 0
        }
    }

    private func scoreLabel(_ score: Double?) -> String {
        guard let score, score.isFinite else { return "--" }
        return String(Int(score.rounded()))
    }

    private func f0Value(at time: TimeInterval) -> Double? {
        for run in f0Runs {
            guard let first = run.first, let last = run.last else { continue }
            if time < first.time || time > last.time { continue }
            if time == first.time { return first.hz }
            if time == last.time { return last.hz }

            for pair in zip(run, run.dropFirst()) {
                let previous = pair.0
                let next = pair.1
                guard time >= previous.time, time <= next.time else { continue }
                let fraction = (time - previous.time) / max(0.001, next.time - previous.time)
                return previous.hz + (next.hz - previous.hz) * fraction
            }
        }
        return nil
    }

    private func vfpValue(at time: TimeInterval) -> Double? {
        interpolatedValue(
            in: vfpWindows.map {
                (($0.startSeconds + $0.endSeconds) / 2, $0.vfpStandardScore)
            },
            at: time
        )
    }

    private func naturalnessValue(at time: TimeInterval) -> Double? {
        interpolatedValue(
            in: naturalnessWindows.map {
                (($0.startSeconds + $0.endSeconds) / 2, $0.score)
            },
            at: time
        )
    }

    private func interpolatedValue(
        in samples: [(time: Double, value: Double)],
        at time: TimeInterval
    ) -> Double? {
        guard let first = samples.first else { return nil }
        if time <= first.time { return first.value }
        guard let last = samples.last else { return nil }
        if time >= last.time { return last.value }

        for pair in zip(samples, samples.dropFirst()) {
            let previous = pair.0
            let next = pair.1
            guard time >= previous.time, time <= next.time else { continue }
            let duration = max(0.001, next.time - previous.time)
            let fraction = (time - previous.time) / duration
            return previous.value + (next.value - previous.value) * fraction
        }
        return last.value
    }

    private func catmullRom(
        previous: Double,
        start: Double,
        end: Double,
        after: Double,
        t: Double
    ) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        let value = 0.5 * (
            2 * start
                + (-previous + end) * t
                + (2 * previous - 5 * start + 4 * end - after) * t2
                + (-previous + 3 * start - 3 * end + after) * t3
        )
        return min(max(value, 0), 600)
    }

    private func xPosition(_ time: Double, width: CGFloat) -> CGFloat {
        width * CGFloat((time - viewportStart) / windowSeconds)
    }

    private func yPosition(_ hz: Double, height: CGFloat) -> CGFloat {
        height * CGFloat(1 - min(max(hz, 0), maximumFrequency) / maximumFrequency)
    }
}
