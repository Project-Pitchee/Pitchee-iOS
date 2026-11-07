//
//  RecordingTabAccessory.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/18.
//

import SwiftUI
import Combine

/// Recording and practice share one system-owned accessory above the tab bar.
struct TabBarAccessory<Accessory: View>: ViewModifier {
    let isVisible: Bool
    @ViewBuilder var accessory: () -> Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isVisible) {
                accessory()
            }
        } else if #available(iOS 26.0, *) {
            content.tabViewBottomAccessory {
                if isVisible {
                    accessory()
                }
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if isVisible {
                    accessory()
                        .background(.regularMaterial)
                }
            }
        }
    }
}

struct RecordingAccessoryContent: View {
    let viewModel: AnalysisViewModel
    let action: () -> Void
    var iconSize: CGFloat = 26
    @State private var state: AnalysisViewModel.State

    init(viewModel: AnalysisViewModel, action: @escaping () -> Void, iconSize: CGFloat = 26) {
        self.viewModel = viewModel
        self.action = action
        self.iconSize = iconSize
        _state = State(initialValue: viewModel.state)
    }

    private var isRecording: Bool { state == .recording }
    private var isRequestingPermission: Bool { state == .requestingPermission }
    private var needsAnalysisScreen: Bool { state == .analyzing || state == .awaitingFeedback }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            RecordingAccessoryButton(
                symbol: actionSymbol,
                color: needsAnalysisScreen ? .primary : .red,
                iconSize: iconSize,
                isPreparing: isRequestingPermission,
                action: action
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("recording.primaryAction")
            .accessibilityInputLabels([accessibilityLabel])
            .accessibilityHint(isRecording
                ? String(localized: "recording.controls.stopAndAnalyze.hint")
                : "")
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: isRecording)
        .onReceive(viewModel.$state.removeDuplicates()) { state = $0 }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var actionSymbol: String {
        if isRecording { return "stop.circle" }
        if needsAnalysisScreen { return "arrow.up.right.circle" }
        return "record.circle"
    }

    private var accessibilityLabel: String {
        if isRecording { return String(localized: "recording.controls.stopAndAnalyze") }
        if needsAnalysisScreen { return String(localized: "recording.controls.viewAnalysisProgress") }
        return String(localized: "recording.controls.startRecording")
    }

    private var title: String {
        if isRecording { return String(localized: "recording.controls.recordingInProgress") }
        if isRequestingPermission { return String(localized: "recording.controls.preparingMicrophone") }
        if needsAnalysisScreen { return String(localized: "recording.controls.analyzingAudio") }
        return String(localized: "recording.controls.startRecording")
    }

    private var subtitle: LocalizedStringKey {
        if isRecording { return "recording.controls.stopAndAnalyze.subtitle" }
        if isRequestingPermission { return "recording.controls.preparingMicrophone.subtitle" }
        if needsAnalysisScreen { return "recording.controls.viewAnalysisProgress.subtitle" }
        return "recording.controls.startRecording.subtitle"
    }
}

/// Both audio tools use the same size, symbol treatment, and press feedback.
struct RecordingAccessoryButton: View {
    let symbol: String
    var color: Color = .red
    var iconSize: CGFloat = 32
    let isPreparing: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Group {
                if isPreparing {
                    ProgressView()
                        .tint(color)
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: iconSize, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                }
            }
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(RecordingAccessoryPressStyle())
        .disabled(isPreparing)
    }
}

struct RecordingAccessoryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("Mock - Control States", traits: .sizeThatFitsLayout) {
    VStack(spacing: 24) {
        RecordingAccessoryContent(viewModel: .preview(state: .idle), action: {})
        RecordingAccessoryContent(viewModel: .preview(state: .requestingPermission), action: {})
        RecordingAccessoryContent(viewModel: .preview(state: .recording), action: {})
        RecordingAccessoryContent(viewModel: .preview(state: .analyzing), action: {})
    }
    .padding(.vertical)
}
#endif
