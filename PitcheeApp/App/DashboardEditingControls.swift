//
//  DashboardEditingControls.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import SwiftUI
import UIKit

@MainActor
final class DashboardHapticFeedback {
    static let shared = DashboardHapticFeedback()

    private let activation = UIImpactFeedbackGenerator(style: .medium)
    private let selection = UISelectionFeedbackGenerator()
    private let placement = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        activation.prepare()
        selection.prepare()
        placement.prepare()
    }

    func dragActivated() {
        activation.impactOccurred()
        selection.prepare()
        placement.prepare()
    }

    func positionChanged() {
        selection.selectionChanged()
        selection.prepare()
    }

    func dragReleased() {
        placement.impactOccurred()
        activation.prepare()
    }

    func componentChanged() {
        selection.selectionChanged()
        selection.prepare()
    }
}

struct DashboardResizeHandle: View {
    let size: DashboardComponentSize
    let tint: Color
    let onResize: (DashboardComponentSize) -> Void
    let onDraggingChanged: (Bool) -> Void

    @State private var initialSize: DashboardComponentSize?
    @GestureState private var isDragging = false

    private var sizeTitle: LocalizedStringKey {
        switch size {
        case .small: "insights.dashboard.size.small"
        case .medium: "insights.dashboard.size.medium"
        case .large: "insights.dashboard.size.large"
        }
    }

    var body: some View {
        grip
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($isDragging) { _, isDragging, _ in isDragging = true }
                    .onChanged(updateResize)
                    .onEnded(endResize)
            )
            .onChange(of: isDragging) { _, active in
                if !active { finishResize() }
            }
            .onDisappear(perform: finishResize)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("insights.dashboard.resize.action")
            .accessibilityValue(Text(sizeTitle))
            .accessibilityHint("insights.dashboard.resize.hint")
            .accessibilityAction { cycleSize() }
            .accessibilityAdjustableAction(adjustSize)
    }

    @ViewBuilder
    private var grip: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(tint.opacity(0.35)).interactive(), in: DashboardResizeGrip())
                .overlay { DashboardResizeGrip().fill(tint.opacity(0.75)) }
        } else {
            DashboardResizeGrip()
                .fill(.thinMaterial)
                .overlay { DashboardResizeGrip().fill(tint.opacity(0.75)) }
        }
    }

    private func endResize(_ value: DragGesture.Value) {
        // One gesture owns both tap and drag; a nested Button would compete
        // with the card's reorder recognizer and swallow handle touches.
        if max(abs(value.translation.width), abs(value.translation.height)) < 8,
           let initialSize {
            onResize(initialSize.next)
        }
        finishResize()
    }

    private func cycleSize() {
        guard initialSize == nil else { return }
        resize(to: size.next)
    }

    private func updateResize(_ value: DragGesture.Value) {
        if initialSize == nil {
            initialSize = size
            onDraggingChanged(true)
        }
        guard let initialSize else { return }
        resize(to: initialSize.resized(by: value.translation))
    }

    private func finishResize() {
        guard initialSize != nil else { return }
        initialSize = nil
        onDraggingChanged(false)
    }

    private func adjustSize(_ direction: AccessibilityAdjustmentDirection) {
        let translation: CGSize
        switch direction {
        case .increment:
            translation = CGSize(width: 0, height: 50)
        case .decrement:
            translation = CGSize(width: 0, height: -50)
        @unknown default:
            return
        }
        resize(to: size.resized(by: translation))
    }

    private func resize(to newSize: DashboardComponentSize) {
        guard newSize != size else { return }
        onResize(newSize)
    }
}

private struct DashboardResizeGrip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 12, y: rect.maxY - 11))
        path.addLine(to: CGPoint(x: rect.maxX - 23, y: rect.maxY - 11))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 11, y: rect.maxY - 23),
            control: CGPoint(x: rect.maxX - 11, y: rect.maxY - 11)
        )
        path.addLine(to: CGPoint(x: rect.maxX - 11, y: rect.minY + 12))
        return path.strokedPath(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
    }
}

/// Older SwiftUI drag modifiers don't expose the end of a cancelled session.
/// UIKit supplies both lifecycle callbacks, including drops outside the grid.
struct DashboardLegacyDragSource<Content: View>: UIViewControllerRepresentable {
    let identifier: String
    let isEditing: Bool
    let content: Content
    let onBegin: () -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        let interaction = UIDragInteraction(delegate: context.coordinator)
        interaction.isEnabled = true
        controller.view.addInteraction(interaction)
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        context.coordinator.parent = self
        controller.rootView = content
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: UIHostingController<Content>,
        context: Context
    ) -> CGSize? {
        // The grid gives each widget an exact size. Keep the hosting
        // controller's intrinsic content size from overriding that proposal.
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: max(0, width), height: max(0, height))
    }

    static func dismantleUIViewController(_ controller: UIHostingController<Content>, coordinator: Coordinator) {
        coordinator.finishSession()
        for interaction in controller.view.interactions where interaction is UIDragInteraction {
            controller.view.removeInteraction(interaction)
        }
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var parent: DashboardLegacyDragSource
        private var activeSession: ObjectIdentifier?

        init(parent: DashboardLegacyDragSource) { self.parent = parent }

        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            // Editing controls own their touches; a resize or removal must
            // never activate the card's reorder interaction.
            if parent.isEditing, let view = interaction.view {
                let location = session.location(in: view)
                let removeControl = CGRect(x: view.bounds.minX, y: view.bounds.minY, width: 44, height: 44)
                let resizeControl = CGRect(x: view.bounds.maxX - 44, y: view.bounds.maxY - 44, width: 44, height: 44)
                if removeControl.contains(location) || resizeControl.contains(location) {
                    return []
                }
            }
            return [UIDragItem(itemProvider: NSItemProvider(object: parent.identifier as NSString))]
        }

        func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
            guard activeSession == nil else { return }
            activeSession = ObjectIdentifier(session)
            parent.onBegin()
        }

        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, willEndWith operation: UIDropOperation) {
            finishSession(session)
        }

        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
            finishSession(session)
        }

        func finishSession(_ session: UIDragSession? = nil) {
            guard let activeSession else { return }
            if let session, activeSession != ObjectIdentifier(session) { return }
            // UIKit delivers both willEnd and didEnd. Clear first so release
            // feedback and parent cleanup happen once, including on teardown.
            self.activeSession = nil
            parent.onEnd()
        }
    }
}
