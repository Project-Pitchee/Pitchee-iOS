//
//  OnboardingView.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/13.
//

import SwiftUI

// Adapted from Kavsoft's iOSStyleOnBoarding Updated.zip,
// iOSStyleOnBoarding/iOSStyleOnBoarding/Helpers/iOS26StyleOnBoarding.swift.
struct OnboardingView: View {
    private enum Page: Int, Hashable, CaseIterable {
        case intro, welcome, privacy, preferences

        var title: LocalizedStringKey {
            switch self {
            case .intro: "common.brand.wordmark"
            case .welcome: "onboarding.welcome.title"
            case .privacy: "onboarding.welcome.featurePrivacy.title"
            case .preferences: "onboarding.preferences.title"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .intro: "onboarding.welcome.subtitle"
            case .welcome: "onboarding.welcome.subtitle"
            case .privacy: "onboarding.welcome.featurePrivacy.description"
            case .preferences: "onboarding.preferences.subtitle"
            }
        }
    }

    private let onFinished: () -> Void
    private var launchPhase: LaunchPhase = .finished

    @State private var page: Page = .intro
    @State private var selectedVoice: VoicePreference?
    @State private var captionHeight: CGFloat = 150
    @AppStorage(AppStorageKey.voicePreference) private var savedVoicePreference = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool

    init(launchPhase: LaunchPhase = .finished, onFinished: @escaping () -> Void) {
        self.launchPhase = launchPhase
        self.onFinished = onFinished
    }

    private var animation: Animation? {
        reduceMotion ? nil : .interpolatingSpring(duration: 0.65, bounce: 0, initialVelocity: 0)
    }

    var body: some View {
        OnboardingLaunchView(phase: launchPhase) {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 20) {
                                if page == .intro {
                                    brandWelcome
                                } else if page == .preferences {
                                    textContent
                                    preferences
                                } else {
                                    appPreview
                                        .frame(height: max(240, geometry.size.height - captionHeight - 40))
                                    textContent
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                            .id("top")
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .onChange(of: page) { _, _ in
                            proxy.scrollTo("top", anchor: .top)
                            titleFocused = true
                        }
                    }
                }
                footer
            }
            .padding(.top, 48)
            .overlay(alignment: .topLeading) { backButton }
        }
        .background(.black)
        .preferredColorScheme(.dark)
    }

    private var brandWelcome: some View {
        VStack(spacing: 28) {
            OnboardingBrandIcon()
                // The launch overlay lands here, then hands the same image back to the scroll view.
                .opacity(launchPhase == .finished ? 1 : 0)
                .anchorPreference(key: OnboardingLaunchIconAnchorKey.self, value: .bounds) { $0 }
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(verbatim: "Pitchee")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("onboarding.intro.brand")
                Text("onboarding.intro.welcome", tableName: "Onboarding")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
                    .accessibilityIdentifier("onboarding.intro.welcome")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityFocused($titleFocused)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    private var appPreview: some View {
        GeometryReader { geometry in
            let canvas = OnboardingAppPreview.canvasSize
            let aspectRatio = canvas.height / canvas.width
            let width = max(1, min(300, geometry.size.width - 40, (geometry.size.height - 20) / aspectRatio))
            let cornerRadius = width * 0.13
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach([Page.welcome, .privacy], id: \.self) { previewPage in
                        OnboardingAppPreview(screen: previewPage == .welcome ? .recording : .result)
                            .padding(.top, 24)
                            .padding(.bottom, 16)
                            .background(.black)
                            .frame(width: canvas.width, height: canvas.height)
                            .scaleEffect(width / canvas.width)
                            .frame(width: width, height: width * aspectRatio)
                            .clipShape(shape)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding<Page?>(get: { page }, set: { _ in }))
            .frame(width: width, height: width * aspectRatio)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
            .background {
                RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                    .fill(Color(white: 0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.08), .white.opacity(0.2)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1
                            )
                    }
                    .padding(-4)
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            .compositingGroup()
            .scaleEffect(page == .privacy && !reduceMotion ? 1.08 : 1, anchor: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The app preview is decorative; the full privacy information remains in the form.
        .dynamicTypeSize(.large)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var textContent: some View {
        ZStack {
            ForEach([Page.welcome, .privacy, .preferences], id: \.self) { item in
                VStack(spacing: 8) {
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(item.subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .compositingGroup()
                .blur(radius: item == page || reduceMotion ? 0 : 20)
                .opacity(item == page ? 1 : 0)
                .offset(x: reduceMotion ? 0 : CGFloat(item.rawValue - page.rawValue) * 35)
                .accessibilityHidden(item != page)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityFocused($titleFocused)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captionHeight = $0 }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("onboarding.preferences.voicePrompt")
                .font(.headline)

            ForEach(VoicePreference.allCases, id: \.self) { option in
                VoicePreferenceCard(option: option, isSelected: selectedVoice == option) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        selectedVoice = option
                        savedVoicePreference = option.rawValue
                    }
                }
                .accessibilityIdentifier("onboarding.voice.\(option.rawValue)")
            }

            PrivacyPromiseView().padding(.top, 8)
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { item in
                    Capsule()
                        .fill(.white.opacity(item == page ? 1 : 0.4))
                        .frame(width: item == page ? 25 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("onboarding.pagination.pageIndicator.a11y \(page.rawValue + 1) \(Page.allCases.count)")

            Button(action: advance) {
                Text(continueTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .padding(.vertical, 6)
            }
            .modifier(LiquidGlassProminentButtonStyleModifier())
            .tint(Color(red: 0.10, green: 0.27, blue: 0.83))
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(page == .preferences && selectedVoice == nil)
            .accessibilityIdentifier("onboarding.continue")
            .accessibilityHint(page == .preferences && selectedVoice == nil
                ? String(localized: "onboarding.footer.voiceSelectionRequired.a11y") : "")
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 30)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .blur(radius: 15)
                .padding(-30)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var continueTitle: LocalizedStringKey {
        switch page {
        case .intro: "onboarding.footer.startSetup"
        case .preferences: "onboarding.footer.finishSetup"
        case .welcome, .privacy: "onboarding.footer.nextPage"
        }
    }

    @ViewBuilder
    private var backButton: some View {
        if let previous = Page(rawValue: page.rawValue - 1) {
            Button {
                withAnimation(animation) { page = previous }
            } label: {
                Label { Text(previous.title) } icon: {
                    Image(systemName: "chevron.backward").font(.title3.weight(.medium))
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .liquidGlass(tint: .clear, cornerRadius: 22, interactive: true)
            .accessibilityIdentifier("onboarding.back")
            .padding(.leading, 16)
        }
    }

    private func advance() {
        if page == .preferences {
            guard let selectedVoice else { return }
            savedVoicePreference = selectedVoice.rawValue
            onFinished()
        } else if let next = Page(rawValue: page.rawValue + 1) {
            withAnimation(animation) { page = next }
        }
    }
}

private struct LiquidGlassProminentButtonStyleModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

#if DEBUG
private extension OnboardingView {
    init(previewingPreferences: Bool, launchPhase: LaunchPhase) {
        onFinished = {}
        self.launchPhase = launchPhase
        _page = State(initialValue: previewingPreferences ? .preferences : .intro)
        _selectedVoice = State(initialValue: .feminine)
    }
}

private struct OnboardingPreview: View {
    var showsPreferences = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchPhase: LaunchPhase = .initial

    var body: some View {
        OnboardingView(previewingPreferences: showsPreferences, launchPhase: launchPhase)
            .defaultAppStorage(DebugPreviewDefaults.store)
            .task(id: reduceMotion) {
                guard launchPhase != .finished else { return }
                await LaunchAnimation.run(showsOnboarding: true, reduceMotion: reduceMotion) {
                    launchPhase = $0
                }
            }
    }
}

#Preview("Debug - Welcome") {
    OnboardingPreview()
}

#Preview("Debug - Voice Preference") {
    OnboardingPreview(showsPreferences: true)
}
#endif
