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
        case welcome, privacy, preferences

        var title: LocalizedStringKey {
            switch self {
            case .welcome: "onboarding.welcome.title"
            case .privacy: "onboarding.welcome.featurePrivacy.title"
            case .preferences: "onboarding.preferences.title"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .welcome: "onboarding.welcome.subtitle"
            case .privacy: "onboarding.welcome.featurePrivacy.description"
            case .preferences: "onboarding.preferences.subtitle"
            }
        }
    }

    private let onFinished: () -> Void
    private var launchPhase: LaunchPhase = .finished

    @State private var page: Page = .welcome
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
                                if page == .preferences {
                                    textContent
                                    preferences
                                } else {
                                    phonePreview
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

    private var phonePreview: some View {
        GeometryReader { geometry in
            let width = min(300, geometry.size.width - 40, (geometry.size.height - 20) / 2.05)
            let shape = RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach([Page.welcome, .privacy], id: \.self) { previewPage in
                        phoneContent(for: previewPage)
                            .frame(width: 320, height: 656)
                            .background(Color(uiColor: .systemGroupedBackground))
                            .scaleEffect(width / 320)
                            .frame(width: width, height: width * 2.05)
                            .clipShape(shape)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding<Page?>(get: { page }, set: { _ in }))
            .frame(width: width, height: width * 2.05)
            .clipShape(shape)
            .overlay {
                shape.stroke(.white.opacity(0.8), lineWidth: 5)
                shape.stroke(.black, lineWidth: 3)
                shape.stroke(.black, lineWidth: 5).padding(-4)
            }
            .overlay(alignment: .top) {
                Capsule().fill(.black).frame(width: width * 0.3, height: width * 0.075)
                    .padding(.top, 10)
            }
            .compositingGroup()
            .scaleEffect(page == .privacy && !reduceMotion ? 1.08 : 1, anchor: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The phone is an illustration; the full privacy information remains in the form.
        .dynamicTypeSize(.large)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func phoneContent(for previewPage: Page) -> some View {
        VStack(spacing: 24) {
            HStack(spacing: 10) {
                Image("Default")
                    .resizable().scaledToFit()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("common.brand.wordmark")
                    .font(.headline).tracking(2)
                Spacer()
            }

            if previewPage == .welcome {
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.system(size: 110, weight: .light))
                    .foregroundStyle(Color.pitcheeAccent.gradient)
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .background {
                        Circle().fill(Color.pitcheeAccent.opacity(0.25)).blur(radius: 40)
                    }
                Text("onboarding.welcome.artworkBadge")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 12) {
                    Text("onboarding.welcome.featureTrend.title")
                        .font(.title2.bold())
                    Text("onboarding.welcome.featureTrend.description")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .liquidGlass(tint: Color.pitcheeAccent.opacity(0.12), cornerRadius: 24)
            } else {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(Color.pitcheeAccent.gradient)
                    .padding(.top, 12)
                PrivacyPromiseView()
                Spacer(minLength: 0)
            }

            Capsule().fill(.white.opacity(0.7)).frame(width: 100, height: 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 12)
    }

    private var textContent: some View {
        ZStack {
            ForEach(Page.allCases, id: \.self) { item in
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
                Text(page == .preferences ? "onboarding.footer.finishSetup" : "onboarding.footer.nextPage")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .padding(.vertical, 6)
            }
            .modifier(LiquidGlassProminentButtonStyleModifier())
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
    init(previewingPreferences: Bool) {
        onFinished = {}
        _page = State(initialValue: previewingPreferences ? .preferences : .welcome)
        _selectedVoice = State(initialValue: .feminine)
    }
}

#Preview("Debug - Welcome") {
    OnboardingView(onFinished: {})
        .defaultAppStorage(DebugPreviewDefaults.store)
}

#Preview("Debug - Voice Preference") {
    OnboardingView(previewingPreferences: true)
        .defaultAppStorage(DebugPreviewDefaults.store)
}
#endif
