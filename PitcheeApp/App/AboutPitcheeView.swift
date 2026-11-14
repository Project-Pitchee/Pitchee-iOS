import SwiftUI

/// A small, local brand story. The sound sculpture is generative artwork;
/// visiting or touching this page never opens an audio session.
struct AboutPitcheeView: View {
    @AppStorage(AppStorageKey.themeSelection) private var savedTheme = AppThemeOption.twilt.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 42

    private var theme: AppThemeOption {
        AppThemeOption(rawValue: savedTheme) ?? .twilt
    }

    private var palette: AppThemePalette {
        theme.dashboardPalette(for: colorScheme == .dark ? .dark : .light, contrast: contrast)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    hero(viewportHeight: geometry.size.height)
                    story
                    features
                    onDeviceNote
                    communityLinks
                    footer
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 24 : 28)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "aboutPitchee.scroll")
            .accessibilityIdentifier("about.pitchee.scroll")
        }
        .foregroundStyle(palette.primaryText)
        .background {
            // Copy sits directly on this backdrop, so soften the theme to
            // preserve small-text contrast without enclosing every section.
            AppThemeBackground()
                .overlay {
                    Color(uiColor: .systemBackground)
                        .opacity(colorScheme == .dark ? 0.22 : 0.55)
                        .ignoresSafeArea()
                }
        }
        .navigationTitle(Text("screen.title", tableName: "AboutPitchee"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(viewportHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image("Default")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(verbatim: "Pitchee")
                    .font(.title3.weight(.semibold))
                    .tracking(-0.6)
            }
            .padding(.top, 30)

            AboutResonanceArtwork(palette: palette, viewportHeight: viewportHeight)
                .frame(maxWidth: 430)
                .padding(.top, 10)

            Text("hero.tagline", tableName: "AboutPitchee")
                .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                .tracking(-1.6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 20)

            Text("hero.description", tableName: "AboutPitchee")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Rectangle()
                .fill(LinearGradient(colors: [palette.accent.opacity(0.5), palette.accent.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 1, height: 64)
                .padding(.top, 34)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 44)
    }

    private var story: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("story.eyebrow", tableName: "AboutPitchee")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(palette.secondaryText)

            Text("story.title", tableName: "AboutPitchee")
                .font(.largeTitle.weight(.semibold))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("story.body", tableName: "AboutPitchee")
                .font(.body)
                .foregroundStyle(palette.secondaryText)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 42)
    }

    private var features: some View {
        VStack(spacing: 0) {
            AboutStoryRow(number: "01", symbol: "waveform", title: "feature.listen.title",
                          detail: "feature.listen.body", palette: palette)
            Divider().overlay(palette.accent.opacity(0.08))
            AboutStoryRow(number: "02", symbol: "circle.dotted.circle", title: "feature.practice.title",
                          detail: "feature.practice.body", palette: palette)
            Divider().overlay(palette.accent.opacity(0.08))
            AboutStoryRow(number: "03", symbol: "chart.xyaxis.line", title: "feature.progress.title",
                          detail: "feature.progress.body", palette: palette)
        }
        .padding(.bottom, 42)
    }

    private var onDeviceNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("voiceProfile.privacyPromise.onDevice.title", tableName: "Localizable")
                .font(.title2.weight(.semibold))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("voiceProfile.privacyPromise.onDevice.description", tableName: "Localizable")
                .font(.body)
                .foregroundStyle(palette.secondaryText)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 42)
    }

    private var communityLinks: some View {
        VStack(spacing: 0) {
            Divider().overlay(palette.accent.opacity(0.08))
            communityLink("link.github.title",
                          destination: URL(string: "https://github.com/Project-Pitchee/Pitchee-iOS")!,
                          identifier: "about.pitchee.github")
            Divider().overlay(palette.accent.opacity(0.08))
            communityLink("link.discord.title",
                          destination: URL(string: "https://discord.gg/djuAGWAcB")!,
                          identifier: "about.pitchee.discord")
            Divider().overlay(palette.accent.opacity(0.08))
            communityLink("link.qq.title",
                          destination: URL(string: "https://qm.qq.com/q/w0pvVpKEyy")!,
                          identifier: "about.pitchee.qq")
        }
        .padding(.bottom, 42)
    }

    private func communityLink(_ title: String, destination: URL, identifier: String) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Text(LocalizedStringKey(title), tableName: "AboutPitchee")
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var footer: some View {
        Text(verbatim: "Pitchee \(AppVersion.current)｜Made with ❤️ by Ryo")
            .font(.caption)
            .foregroundStyle(palette.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AboutStoryRow: View {
    let number: String
    let symbol: String
    // String keys avoid automatic extraction into the default Localizable catalog.
    let title: String
    let detail: String
    let palette: AppThemePalette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 22))
        layout {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 25, weight: .light))
                    .frame(width: 38, height: 32)
                Text(verbatim: number)
                    .font(.caption2.monospaced())
            }
            .foregroundStyle(palette.accent)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedStringKey(title), tableName: "AboutPitchee")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(LocalizedStringKey(detail), tableName: "AboutPitchee")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .lineSpacing(4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 26)
    }
}

private struct AboutResonanceArtwork: View {
    let palette: AppThemePalette
    let viewportHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var isMounted = false
    @State private var pulseCount = 0
    @State private var epoch = Date()

    var body: some View {
        VStack(spacing: 6) {
            Button {
                pulseCount += 1
            } label: {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isVisible || !isMounted || scenePhase != .active)) { timeline in
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSince(epoch)
                    AboutSoundSculpture(time: time, palette: palette)
                }
                .aspectRatio(1.45, contentMode: .fit)
                .keyframeAnimator(initialValue: CGFloat.zero, trigger: pulseCount) { [reduceMotion] content, value in
                    content
                        .scaleEffect(reduceMotion ? 1 : 1 + value * 0.06)
                        .opacity(reduceMotion ? 1 - value * 0.18 : 1)
                } keyframes: { _ in
                    CubicKeyframe(1, duration: 0.18)
                    SpringKeyframe(0, duration: 0.9, spring: .smooth)
                }
                .contentShape(Ellipse())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: pulseCount)
            .accessibilityLabel(Text("hero.accessibility.label", tableName: "AboutPitchee"))
            .accessibilityHint(Text("hero.accessibility.hint", tableName: "AboutPitchee"))
            .accessibilityIdentifier("about.pitchee.resonance")
        }
        .onGeometryChange(for: Bool.self) { proxy in
            let frame = proxy.frame(in: .named("aboutPitchee.scroll"))
            return frame.maxY > 0 && frame.minY < viewportHeight
        } action: { isVisible = $0 }
        .onAppear { isMounted = true }
        .onDisappear { isMounted = false }
    }
}

/// Projected rings form a living voiceprint. Only this canvas redraws at 30 fps;
/// all copy and navigation stay outside the animation's observation scope.
private struct AboutSoundSculpture: View {
    let time: TimeInterval
    let palette: AppThemePalette

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.49)
            let phase = time * 0.55
            let colors = [palette.tertiary, palette.accent, palette.secondary, palette.accent]
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: colors),
                startPoint: CGPoint(x: size.width * 0.12, y: size.height * 0.15),
                endPoint: CGPoint(x: size.width * 0.86, y: size.height * 0.85)
            )

            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 26))
                glow.fill(Path(ellipseIn: CGRect(x: size.width * 0.2, y: size.height * 0.28,
                                                width: size.width * 0.6, height: size.height * 0.5)),
                          with: .color(palette.accent.opacity(0.19)))
            }

            // A faint orbital line gives the sculpture depth without a container.
            var orbit = Path()
            for step in 0...160 {
                let angle = Double(step) / 160 * .pi * 2
                let x = cos(angle) * size.width * 0.47
                let y = sin(angle) * size.height * 0.23
                let point = CGPoint(x: center.x + x * 0.96 - y * 0.28,
                                    y: center.y + x * 0.28 + y * 0.96)
                if step == 0 { orbit.move(to: point) } else { orbit.addLine(to: point) }
            }
            context.stroke(orbit, with: .color(palette.accent.opacity(0.16)), lineWidth: 0.7)

            for ring in 0..<64 {
                let position = Double(ring) / 63
                let envelope = pow(sin(position * .pi), 0.72)
                let breath = 0.83 + 0.13 * sin(position * .pi * 3 - phase)
                let radius = size.height * 0.40 * envelope * breath
                let axisX = (position - 0.5) * size.width * 0.76
                var line = Path()
                for step in 0...80 {
                    let angle = Double(step) / 80 * .pi * 2
                    let twist = sin(position * .pi * 2 + phase) * 0.16
                    let x = axisX + cos(angle) * radius * 0.32
                    let y = sin(angle) * radius
                    let point = CGPoint(x: center.x + x * 0.98 - y * (0.15 + twist),
                                        y: center.y + y * 0.96 + x * 0.12)
                    if step == 0 { line.move(to: point) } else { line.addLine(to: point) }
                }
                var strand = context
                strand.opacity = 0.30 + envelope * 0.58
                strand.stroke(line, with: shading, lineWidth: ring.isMultiple(of: 4) ? 1.25 : 0.65)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("关于 Pitchee") {
    NavigationStack { AboutPitcheeView() }
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("About Pitchee · dark") {
    NavigationStack { AboutPitcheeView() }
        .environment(\.locale, Locale(identifier: "en"))
        .preferredColorScheme(.dark)
}

#Preview("About Pitchee · large text") {
    NavigationStack { AboutPitcheeView() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
