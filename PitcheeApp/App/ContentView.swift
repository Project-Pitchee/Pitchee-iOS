//
//  ContentView.swift
//  Pitchee
//
//  Created by Lvy Zhan on 2026/6/12.
//

import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage(AppStorageKey.onboardingCompletedVersion) private var completedOnboardingVersion = 0
    @AppStorage(AppStorageKey.customThemeColor) private var customThemeColor = ""
    @AppStorage(AppStorageKey.themeSelection) private var savedThemeSelection = AppThemeOption.twilt.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchPhase: LaunchPhase = .initial

    private var selectedTheme: AppThemeOption {
        AppThemeOption(rawValue: savedThemeSelection) ?? .twilt
    }

    private var themeColor: Color {
        if let customColor = Color(hex: customThemeColor) {
            return customColor
        }
        return AppTheme.color(
            for: selectedTheme,
            appearance: colorScheme == .dark ? .dark : .light
        )
    }

    var body: some View {
        Group {
            if completedOnboardingVersion >= OnboardingFlow.currentVersion {
                MainTabView(
                    themeColor: themeColor,
                    dashboardTint: selectedTheme.dashboardPalette(
                        for: colorScheme == .dark ? .dark : .light,
                        contrast: colorSchemeContrast
                    ).accent
                )
            } else {
                OnboardingView(launchPhase: launchPhase) {
                    completedOnboardingVersion = OnboardingFlow.currentVersion
                }
            }
        }
        .allowsHitTesting(launchPhase == .finished)
        .accessibilityHidden(launchPhase != .finished)
        .overlay {
            if completedOnboardingVersion >= OnboardingFlow.currentVersion,
               launchPhase != .finished {
                ReturningLaunchView(phase: launchPhase)
            }
        }
        .task(id: reduceMotion) {
            guard launchPhase != .finished else { return }
            #if DEBUG
            if ScreenshotMode.isEnabled {
                launchPhase = .finished
                return
            }
            #endif
            await LaunchAnimation.run(
                showsOnboarding: completedOnboardingVersion < OnboardingFlow.currentVersion,
                reduceMotion: reduceMotion
            ) { launchPhase = $0 }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: completedOnboardingVersion)
        .tint(themeColor)
    }
}

private struct MainTabView: View {
    let themeColor: Color
    let dashboardTint: Color
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    // Keep the reference stable without making the whole TabView observe every
    // realtime pitch frame. ScoringView and the accessory subscribe locally.
    @State private var recordingModel = AnalysisViewModel()
    @State private var selectedTab: AppTab = .trends
    @State private var insightsRange: InsightsRange = .sevenDays
    @State private var dashboardRanges = InsightsRange.allCases
    @State private var isDashboardVisible = false
    @State private var isInsightsBarMinimized = false
    @State private var monitorAccessoryState = MonitorAccessoryState()
    @Namespace private var monitorTransition
    @State private var practicePath: [PracticeRoute] = []
    @State private var keyboardIsVisible = false
    #if DEBUG
    @State private var showsScreenshotHistory = false
    #endif

    init(themeColor: Color, dashboardTint: Color) {
        self.themeColor = themeColor
        self.dashboardTint = dashboardTint
        #if DEBUG
        // Lets the isolated review simulator open this page without altering saved preferences.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-practice-hub-preview")
            || arguments.contains("-monitor-review-pitch")
            || arguments.contains("-monitor-review-spectrum")
            || arguments.contains("-practice-spectrum-preview") {
            _selectedTab = State(initialValue: .practice)
        }
        if arguments.contains("-practice-spectrum-preview") {
            _practicePath = State(initialValue: [.spectrogram])
        } else if arguments.contains("-monitor-review-pitch") {
            _practicePath = State(initialValue: [.pitch])
        } else if arguments.contains("-monitor-review-spectrum") {
            _practicePath = State(initialValue: [.spectrum])
        }
        if let screen = ScreenshotMode.screen {
            _recordingModel = State(initialValue: .preview(state: .completed))
            _selectedTab = State(initialValue: screen == .history ? .trends : .practice)
            _showsScreenshotHistory = State(initialValue: screen == .history)
            switch screen {
            case .monitor: _practicePath = State(initialValue: [.pitch])
            case .insights: _practicePath = State(initialValue: [.analysis])
            case .articles: _practicePath = State(initialValue: [.screenshotArticles])
            case .home, .history: break
            }
        }
        if ScreenshotMode.dashboardScenario != nil {
            _selectedTab = State(initialValue: .trends)
            _showsScreenshotHistory = State(initialValue: false)
            _practicePath = State(initialValue: [])
        }
        #endif
    }

    var body: some View {
        tabNavigation
            .tint(selectedTab == .trends ? dashboardTint : themeColor)
            .environment(\.monitorAccessoryState, monitorAccessoryState)
            .fullScreenCover(isPresented: $monitorAccessoryState.isExpanded) {
                if let model = activeMonitorModel {
                    MonitorExpandedView(model: model, titleKey: monitorTitleKey) { height in
                        if practicePath.last == .spectrogram {
                            VStack(alignment: .leading, spacing: 18) {
                                PracticeSpectrumInstrument(model: model).frame(height: height)
                                MonitorSpectrogramLegend()
                                MonitorSpectrumReadout(model: model)
                                if model.hasAudio { MonitorTimelineControl(model: model) }
                            }
                        } else {
                            MonitorInstrument(model: model, height: height)
                        }
                    }
                    .monitorPlayerTransition(in: monitorTransition)
                }
            }
            .task { await VoiceTrainingLibraryLoader.shared.load() }
            .onChange(of: selectedTab) { _, tab in
                if tab != .practice {
                    monitorAccessoryState.leavePractice()
                    recordingModel.interruptCapture()
                }
            }
            .onChange(of: practicePath) { _, path in
                if path.last != .scoring { recordingModel.interruptCapture() }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { recordingModel.handleSceneActive() }
                else { recordingModel.handleSceneInactive(isBackground: phase == .background) }
            }
    }

    private var usesLegacyTabBar: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-legacy-tab-bar-preview") { return true }
        #endif
        if #available(iOS 26.0, *) { return false }
        return true
    }

    @ViewBuilder
    private var tabNavigation: some View {
        if usesLegacyTabBar {
            tabs.safeAreaInset(edge: .bottom, spacing: 0) {
                if !keyboardIsVisible {
                    VStack(spacing: 8) {
                        if insightsPickerVisible || scoringPageVisible || activeMonitorModel != nil {
                            accessory
                                .background { LegacyTabBarBackground() }
                        }
                        LegacyGlassTabBar(selection: $selectedTab)
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardIsVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardIsVisible = false
            }
        } else {
            tabs
                .modifier(InsightsTabBarMinimization(
                    isEnabled: insightsPickerVisible,
                    isMinimized: $isInsightsBarMinimized
                ))
                .modifier(TabBarAccessory(isVisible: scoringPageVisible || activeMonitorModel != nil) {
                    accessory
                })
                .modifier(InsightsRangeTabBarOverlay(
                    selection: $insightsRange,
                    ranges: dashboardRanges,
                    isVisible: insightsPickerVisible,
                    isMinimized: isInsightsBarMinimized
                ))
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if insightsPickerVisible {
            InsightsRangeTabBar(selection: $insightsRange, ranges: dashboardRanges)
        } else if let model = activeMonitorModel {
            MonitorAccessoryContent(model: model, titleKey: monitorTitleKey) {
                monitorAccessoryState.isExpanded = true
            }
            .monitorTransitionSource(in: monitorTransition)
        } else if scoringPageVisible {
            ScoringAccessoryHost(viewModel: recordingModel, action: scoringAction)
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                trendsRoot
                    .safeAreaPadding(.bottom, usesLegacyTabBar || dashboardRanges.isEmpty ? 0 : 56)
                    .onAppear { isDashboardVisible = true }
                    .onDisappear { isDashboardVisible = false }
            }
            .tabItem {
                Label(AppTab.trends.title, systemImage: AppTab.trends.systemImage)
            }
            .tag(AppTab.trends)
            .toolbar(usesLegacyTabBar ? .hidden : .automatic, for: .tabBar)

            NavigationStack(path: $practicePath) {
                PracticeHubView()
                    .navigationDestination(for: PracticeRoute.self) { route in
                        switch route {
                        case .scoring:
                            ScoringView(model: recordingModel, practicePath: $practicePath)
                        case .analysis:
                            RecordingAnalysisView(viewModel: recordingModel)
                        case .pitch:
                            PitchMonitorView()
                        case .spectrum:
                            SpectrumMonitorView()
                        case .spectrogram:
                            PracticeSpectrumView()
                        #if DEBUG
                        case .screenshotArticles:
                            VoiceTrainingLibraryContentView(initialCategory: "pitch")
                        #endif
                        }
                    }
            }
            .tabItem {
                Label(AppTab.practice.title, systemImage: AppTab.practice.systemImage)
            }
            .tag(AppTab.practice)
            .toolbar(usesLegacyTabBar ? .hidden : .automatic, for: .tabBar)

            NavigationStack {
                PianoKeysView()
            }
            .tabItem {
                Label(AppTab.pianoKeys.title, systemImage: AppTab.pianoKeys.systemImage)
            }
            .tag(AppTab.pianoKeys)
            .toolbar(usesLegacyTabBar ? .hidden : .automatic, for: .tabBar)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(AppTab.about.title, systemImage: AppTab.about.systemImage)
            }
            .tag(AppTab.about)
            .toolbar(usesLegacyTabBar ? .hidden : .automatic, for: .tabBar)
        }
    }

    private var scoringPageVisible: Bool {
        selectedTab == .practice && practicePath.last == .scoring
    }

    @ViewBuilder
    private var trendsRoot: some View {
        TrendsView(range: $insightsRange, showsRangePicker: false) { ranges in
            dashboardRanges = ranges
        }
            #if DEBUG
            .navigationDestination(isPresented: $showsScreenshotHistory) {
                RecordingHistoryView(range: .all, now: ScreenshotMode.now)
                .navigationTitle("insights.history.title")
            }
            #endif
    }

    private var insightsPickerVisible: Bool {
        selectedTab == .trends && isDashboardVisible && !dashboardRanges.isEmpty
    }

    private var activeMonitorModel: MonitorViewModel? {
        guard selectedTab == .practice else { return nil }
        guard practicePath.last == .pitch || practicePath.last == .spectrum
                || practicePath.last == .spectrogram else { return nil }
        return monitorAccessoryState.model
    }

    private var monitorTitleKey: String {
        practicePath.last == .spectrogram ? "practice.spectrum.title"
            : monitorAccessoryState.model?.kind.titleKey ?? "practice.hub.tab"
    }

    private func scoringAction() {
        recordingModel.primaryButtonTapped(modelContext: modelContext)
    }
}

private struct ScoringAccessoryHost: View {
    let viewModel: AnalysisViewModel
    let action: () -> Void

    var body: some View {
        RecordingAccessoryContent(viewModel: viewModel, action: action)
    }
}

private struct PianoKeysView: View {
    @AppStorage(AppStorageKey.themeSelection) private var savedTheme = AppThemeOption.twilt.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var soundEngine = PianoSoundEngine()
    @State private var activeNote: PianoNote?
    @State private var feedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ScrollView(showsIndicators: false) {
            noteGrid
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .environment(\.layoutDirection, .leftToRight)
        }
        .background {
            if savedTheme == AppThemeOption.pure.rawValue {
                AppThemeBackground()
            } else {
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.08),
                        Color.purple.opacity(0.05),
                        Color(uiColor: .systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .navigationTitle("piano.screen.title")
        .navigationBarTitleDisplayMode(.large)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            feedback.prepare()
            await soundEngine.prepare()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                soundEngine.stopAll()
                activeNote = nil
            }
        }
        .onDisappear {
            soundEngine.stopAll()
            activeNote = nil
        }
    }

    private var noteGrid: some View {
        // A piano keyboard is a physical object with a fixed orientation: the low
        // notes stay on the left even in right-to-left languages. Without this the
        // grid would fill from the trailing edge and the notes would read high to low.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: 12)],
            spacing: 12
        ) {
            ForEach(PianoNote.allNotes) { note in
                PianoNoteButton(
                    note: note,
                    isActive: activeNote == note,
                    onTap: {
                        playOnce(note)
                    },
                    onSustainChanged: { isSustaining in
                        setSustaining(isSustaining, for: note)
                    }
                )
            }
        }
    }

    private func playOnce(_ note: PianoNote) {
        soundEngine.play(note: note)
        feedback.impactOccurred()
        activeNote = note

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard activeNote == note else { return }
            activeNote = nil
        }
    }

    private func setSustaining(_ isSustaining: Bool, for note: PianoNote) {
        if isSustaining {
            if let activeNote, activeNote != note {
                soundEngine.stop(note: activeNote)
            }

            soundEngine.start(note: note)
            feedback.impactOccurred()
            activeNote = note
        } else {
            soundEngine.stop(note: note)
            if activeNote == note { activeNote = nil }
            feedback.prepare()
        }
    }
}

private struct PianoNoteButton: View {
    let note: PianoNote
    let isActive: Bool
    let onTap: () -> Void
    let onSustainChanged: (Bool) -> Void

    private var tint: Color {
        switch note.midi {
        case 42...49:
            return .blue
        case 54...61:
            return .pink
        default:
            return Color(uiColor: .systemGray)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(note.displayName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.8)

            Text(note.frequency.formatted(.number.precision(.fractionLength(1))) + " " + String(localized: "common.unit.hertz"))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .scaleEffect(isActive ? 0.97 : 1)
        .liquidGlass(
            tint: tint.opacity(isActive ? 0.30 : 0.14),
            cornerRadius: 20,
            interactive: true
        )
        .overlay {
            PianoKeyTouchSurface(onSustainChanged: onSustainChanged)
                .accessibilityHidden(true)
        }
        .animation(isActive ? nil : .easeOut(duration: 0.12), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("piano.note.name.a11y \(note.displayName)")
        .accessibilityHint("piano.note.playbackHint.a11y")
        .accessibilityAction { onTap() }
    }
}

private struct PianoKeyTouchSurface: UIViewRepresentable {
    let onSustainChanged: (Bool) -> Void

    func makeUIView(context: Context) -> TouchView { TouchView() }

    func updateUIView(_ view: TouchView, context: Context) {
        view.onSustainChanged = onSustainChanged
    }

    static func dismantleUIView(_ view: TouchView, coordinator: ()) {
        view.endSustain()
    }

    final class TouchView: UIView, UIGestureRecognizerDelegate {
        var onSustainChanged: (Bool) -> Void = { _ in }
        private var isSustaining = false
        private var holdOrigin = CGPoint.zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold))
            hold.minimumPressDuration = 0
            hold.allowableMovement = 12
            hold.cancelsTouchesInView = false
            hold.delegate = self
            addGestureRecognizer(hold)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // A sustained key must never prevent the enclosing scroll view from panning.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }

        @objc private func handleHold(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                holdOrigin = gesture.location(in: window)
                isSustaining = true
                onSustainChanged(true)
            case .changed:
                let position = gesture.location(in: window)
                if hypot(position.x - holdOrigin.x, position.y - holdOrigin.y) > 12 {
                    endSustain()
                }
            case .ended, .cancelled, .failed:
                endSustain()
            default:
                break
            }
        }

        func endSustain() {
            guard isSustaining else { return }
            isSustaining = false
            onSustainChanged(false)
        }
    }
}

#if DEBUG
#Preview("Debug - Onboarding") {
    ContentView()
        .defaultAppStorage(DebugPreviewDefaults.store)
}

#Preview("Debug - Trends Empty") {
    MainTabView(themeColor: .pitcheeAccent, dashboardTint: .pitcheeAccent)
        .modelContainer(for: RecordingAssessment.self, inMemory: true)
        .defaultAppStorage(DebugPreviewDefaults.store)
}

#Preview("Mock - Trends With History") {
    if let container = DebugPreviewStore.makeContainer(withHistory: true) {
        MainTabView(themeColor: .pitcheeAccent, dashboardTint: .pitcheeAccent)
            .modelContainer(container)
            .defaultAppStorage(DebugPreviewDefaults.store)
    } else {
        Text(verbatim: "Unable to create the preview store.")
    }
}

#Preview("Debug - Piano") {
    NavigationStack { PianoKeysView() }
}

#Preview("Debug - About") {
    NavigationStack { SettingsView() }
}
#endif
