import SwiftUI
import UIKit

// Adapted from Kavsoft's PhotosTB.zip: PhotosTB/PhotosTB/Helpers/TabBarMinimizeHelper.swift.
struct InsightsTabBarObserver: UIViewRepresentable {
    @Binding var isMinimized: Bool

    func makeCoordinator() -> Coordinator { Coordinator(selection: $isMinimized) }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.onUpdate = { [weak coordinator = context.coordinator] view in
            coordinator?.refresh(from: view)
        }
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.selection = $isMinimized
        context.coordinator.refresh(from: view)
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) {
        view.onUpdate = nil
        coordinator.uninstall()
    }

    final class ProbeView: UIView {
        var onUpdate: ((UIView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onUpdate?(self)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            onUpdate?(self)
        }
    }

    @MainActor final class Coordinator {
        var selection: Binding<Bool>
        private weak var window: UIWindow?
        private weak var minimizedView: UIView?
        private weak var expandedView: UIView?
        private var observations: [NSKeyValueObservation] = []
        private var revision = 0
        private var retries = 3
        private var retryScheduled = false
        private var writeScheduled = false
        private var pendingValue = false
        private var isDismantled = false

        init(selection: Binding<Bool>) { self.selection = selection }

        func refresh(from view: UIView) {
            guard !isDismantled else { return }
            guard let sourceWindow = view.window else {
                window = nil
                removeObservers()
                publish(false)
                return
            }
            if window !== sourceWindow {
                window = sourceWindow
                retries = 3
            }
            let tabBar = sourceWindow.rootViewController.flatMap(Self.tabBarController)?.tabBar
            // Match Kavsoft's two tab containers, including an initially zero-sized minimized view.
            let candidates = (tabBar?.subviews ?? [])
                .filter { !String(describing: type(of: $0)).contains("UITabBarAuxiliary") }
                .prefix(2)
            if candidates.count == 2,
               let minimized = candidates.first(where: { $0.frame.width == $0.frame.height }),
               let expanded = candidates.first(where: { $0.frame.width != $0.frame.height }) {
                guard minimizedView !== minimized || expandedView !== expanded else { return }
                removeObservers()
                minimizedView = minimized
                expandedView = expanded
                publish(false)
                observe(minimized, minimized: true)
                observe(expanded, minimized: false)
                return
            }
            removeObservers()
            publish(false)
            guard retries > 0, !retryScheduled else { return }
            retries -= 1
            retryScheduled = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.retryScheduled = false
                if let view { self.refresh(from: view) }
            }
        }

        func uninstall() {
            isDismantled = true
            removeObservers()
        }

        private func observe(_ view: UIView, minimized: Bool) {
            let observedRevision = revision
            observations.append(view.observe(\.isHidden, options: [.initial, .new]) { [weak self] _, change in
                guard change.newValue == false else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.revision == observedRevision else { return }
                    self.publish(minimized)
                }
            })
        }

        private func removeObservers() {
            revision += 1
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            minimizedView = nil
            expandedView = nil
        }

        private func publish(_ value: Bool) {
            guard !isDismantled else { return }
            pendingValue = value
            guard !writeScheduled else { return }
            writeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.writeScheduled = false
                guard !self.isDismantled, self.selection.wrappedValue != self.pendingValue else { return }
                self.selection.wrappedValue = self.pendingValue
            }
        }

        private static func tabBarController(in controller: UIViewController) -> UITabBarController? {
            if let tabBar = controller as? UITabBarController { return tabBar }
            return controller.children.lazy.compactMap { tabBarController(in: $0) }.first
        }
    }
}
