//
//  DashboardView.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: DashboardSnapshot
    @Binding var range: InsightsRange
    let preference: VoicePreference
    var showsRangePicker = true
    var availableRanges: [InsightsRange] = InsightsRange.allCases

    @AppStorage(AppStorageKey.themeSelection) private var savedTheme = AppThemeOption.twilt.rawValue
    @AppStorage(AppStorageKey.dashboardComponentOrder) private var savedOrder = DashboardConfiguration.defaultOrder
    @AppStorage(AppStorageKey.dashboardComponentSizes) private var savedSizes = "{}"
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 174
    @ScaledMetric(relativeTo: .body) private var singleRecordHeight: CGFloat = 124
    @ScaledMetric(relativeTo: .body) private var fewRecordsHeight: CGFloat = 156
    @State private var isEditing = false
    @State private var isAdding = false
    @State private var pendingAddition: DashboardComponent?
    @State private var selectedComponent: DashboardComponent?
    @State private var cardFrames: [DashboardComponent: CGRect] = [:]
    @State private var draft: DashboardConfiguration?
    @State private var resizing: DashboardComponent?
    @State private var drag = DashboardDragFeedbackState<DashboardComponent>()
    @State private var lastLegacyTarget: DashboardComponent?

    private var theme: AppThemeOption { AppThemeOption(rawValue: savedTheme) ?? .twilt }
    private var appearance: GradientAppearance { colorScheme == .dark ? .dark : .light }
    private var palette: AppThemePalette {
        theme.dashboardPalette(for: appearance, contrast: colorSchemeContrast)
    }
    private var persisted: DashboardConfiguration { DashboardConfiguration(order: savedOrder, sizes: savedSizes) }
    private var configuration: DashboardConfiguration { draft ?? persisted }
    private var animation: Animation? { reduceMotion ? nil : .snappy(duration: 0.28) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if showsRangePicker && !availableRanges.isEmpty {
                        InsightsRangePicker(selection: $range, ranges: availableRanges)
                    }
                    grid
                    if configuration.components.isEmpty || isEditing {
                        addButton
                    }
                    if snapshot.assessmentCount == 0 && !configuration.components.isEmpty {
                        Text("insights.history.empty.description")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .liquidGlass(tint: .clear, cornerRadius: 18)
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollDisabled(resizing != nil || selectedComponent != nil)
            .sheet(isPresented: $isAdding, onDismiss: { completeAddition(using: proxy) }) {
                DashboardAddComponentsView(
                    components: DashboardComponent.allCases.filter { !configuration.components.contains($0) },
                    theme: theme,
                    onSelect: { pendingAddition = $0 }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .background {
            AppThemeBackground()
        }
        .navigationTitle(Text(verbatim: "Pitchee"))
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.action.done", action: finishEditing)
                        .tint(palette.primaryText)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ReadinessView()
                    } label: {
                        Label {
                            Text("readiness.title", tableName: "Readiness")
                        } icon: {
                            Image(systemName: "heart.text.square")
                        }
                    }
                    .tint(palette.primaryText)
                }
            }
        }
        .fullScreenCover(item: $selectedComponent) { component in
            DashboardFlipDetail(
                component: component, size: configuration.size(for: component),
                sourceFrame: cardFrames[component], snapshot: snapshot,
                preference: preference, palette: palette, range: range
            )
            .presentationBackground(.clear)
        }
        .onAppear {
            DashboardHapticFeedback.shared.prepare()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-dashboard-edit-preview") { isEditing = true }
            #endif
        }
        .onDisappear(perform: finishInteractions)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { finishInteractions() }
        }
        .onChange(of: savedOrder) { _, _ in cancelDraft() }
        .onChange(of: savedSizes) { _, _ in cancelDraft() }
    }

    @ViewBuilder
    private var grid: some View {
        if #available(iOS 27.0, *), !usesLegacyReordering {
            DashboardWidgetLayout(
                minimumHeight: minimumHeight,
                sizes: configuration.components.map { configuration.size(for: $0) },
                summaryHeights: summaryHeights
            ) {
                ForEach(configuration.components) { component in
                    cell(component)
                        .modifier(DashboardFlipSource(
                            isHidden: selectedComponent == component,
                            onFrameChange: { cardFrames[component] = $0 }
                        ))
                }
                .reorderable()
            }
            .reorderContainer(for: DashboardComponent.self, isEnabled: resizing == nil, move: applyReorder)
            .onDragSessionUpdated(updateDragSession)
            .onDropSessionUpdated(updateDropSession)
            .dragConfiguration(DragConfiguration(
                operationsWithinApp: .init(allowMove: true),
                operationsOutsideApp: .init(allowCopy: false)
            ))
            .animation(animation, value: configuration)
        } else {
            DashboardWidgetLayout(
                minimumHeight: minimumHeight,
                sizes: configuration.components.map { configuration.size(for: $0) },
                summaryHeights: summaryHeights
            ) {
                ForEach(configuration.components) { component in
                    DashboardLegacyDragSource(
                        identifier: component.rawValue,
                        isEditing: isEditing,
                        content: cell(component)
                            .environment(\.colorScheme, colorScheme)
                            .environment(\.dynamicTypeSize, dynamicTypeSize),
                        onBegin: { beginDrag(component, previewsOrder: true) },
                        onEnd: endDrag
                    )
                    .onDrop(of: [UTType.text], delegate: DashboardLegacyDropDelegate(
                        isActive: drag.item != nil,
                        onEnter: { moveLegacy(to: component) },
                        onDrop: commitLegacyDrop
                    ))
                    .id(component)
                    .modifier(DashboardFlipSource(
                        isHidden: selectedComponent == component,
                        onFrameChange: { cardFrames[component] = $0 }
                    ))
                }
            }
            .animation(animation, value: configuration)
        }
    }

    /// A temporary reading layout never overwrites a user's saved widget size.
    private var summaryHeights: [CGFloat?] {
        configuration.components.map { component in
            guard !isEditing, !dynamicTypeSize.isAccessibilitySize,
                  configuration.size(for: component) == .medium,
                  configuration.sizes[component.rawValue] == nil else { return nil }
            switch DashboardCard.summaryDayCount(for: component, snapshot: snapshot) {
            case 1: return singleRecordHeight
            case 2...3: return fewRecordsHeight
            default: return nil
            }
        }
    }

    private var usesLegacyReordering: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-dashboard-legacy-preview")
        #else
        false
        #endif
    }

    private func cell(_ component: DashboardComponent) -> some View {
        Button { open(component) } label: {
            DashboardCard(
                component: component, size: configuration.size(for: component), snapshot: snapshot,
                preference: preference, palette: palette, isEditing: isEditing
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.card.\(component.rawValue)")
        .overlay(alignment: .topLeading) {
            if isEditing {
                Button { remove(component) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.red, .white)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(drag.item != nil || resizing != nil)
                .accessibilityLabel(Text("insights.dashboard.remove.action") + Text(verbatim: " ") + Text(LocalizedStringKey(component.titleKey)))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isEditing && component.supportsResizing {
                DashboardResizeHandle(
                    size: configuration.size(for: component), tint: palette.accent,
                    onResize: { resize(component, to: $0) },
                    onDraggingChanged: { resizeDragging($0, component: component) }
                )
                .disabled(drag.item != nil)
            }
        }
        .accessibilityAction(named: Text("insights.dashboard.edit.action"), beginEditing)
        .accessibilityActions {
            if isEditing {
                if component != configuration.components.first {
                    Button("insights.dashboard.moveEarlier.action") { moveAccessible(component, offset: -1) }
                }
                if component != configuration.components.last {
                    Button("insights.dashboard.moveLater.action") { moveAccessible(component, offset: 1) }
                }
            }
        }
        .id(component)
        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }

    private var addButton: some View {
        Button { isAdding = true } label: {
            Label("insights.dashboard.add.action", systemImage: "plus.circle.fill")
                .font(.headline)
                .foregroundStyle(palette.primaryText)
                .frame(maxWidth: .infinity, minHeight: configuration.components.isEmpty ? 112 : 72)
        }
        .buttonStyle(.plain)
        .disabled(drag.item != nil || resizing != nil)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .liquidGlass(tint: .clear, cornerRadius: 20, interactive: true)
    }

    private func open(_ component: DashboardComponent) {
        guard !isEditing, drag.item == nil, resizing == nil, selectedComponent == nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedComponent = component
        }
    }

    private func beginEditing() {
        withAnimation(animation) { isEditing = true }
    }

    private func finishEditing() {
        finishInteractions()
        withAnimation(animation) { isEditing = false }
    }

    private func save(_ value: DashboardConfiguration) {
        if savedOrder != value.encodedOrder { savedOrder = value.encodedOrder }
        if savedSizes != value.encodedSizes { savedSizes = value.encodedSizes }
    }

    private func completeAddition(using proxy: ScrollViewProxy) {
        guard let component = pendingAddition else { return }
        pendingAddition = nil
        var updated = persisted
        guard updated.add(component) else { return }
        withAnimation(animation) { save(updated) }
        DashboardHapticFeedback.shared.componentChanged()
        // Wait for the appended identity to enter the scroll hierarchy.
        Task { @MainActor in
            await Task.yield()
            withAnimation(animation) { proxy.scrollTo(component, anchor: .bottom) }
        }
    }

    private func remove(_ component: DashboardComponent) {
        guard drag.item == nil, resizing == nil else { return }
        var updated = persisted
        guard updated.remove(component) else { return }
        withAnimation(animation) { save(updated) }
        DashboardHapticFeedback.shared.componentChanged()
    }

    private func resize(_ component: DashboardComponent, to size: DashboardComponentSize) {
        guard drag.item == nil else { return }
        var updated = configuration
        guard updated.resize(component, to: size) else { return }
        withAnimation(animation) {
            if resizing != nil { draft = updated } else { save(updated) }
        }
        DashboardHapticFeedback.shared.componentChanged()
    }

    private func resizeDragging(_ active: Bool, component: DashboardComponent) {
        if active {
            guard drag.item == nil, resizing == nil else { return }
            draft = persisted
            resizing = component
        } else if resizing == component {
            if let draft { save(draft) }
            draft = nil
            resizing = nil
        }
    }

    private func beginDrag(_ component: DashboardComponent, previewsOrder: Bool = false) {
        guard resizing == nil, let index = configuration.components.firstIndex(of: component),
              drag.begin(component, at: index) else { return }
        if previewsOrder { draft = persisted }
        lastLegacyTarget = nil
        beginEditing()
        DashboardHapticFeedback.shared.dragActivated()
    }

    private func endDrag() {
        guard drag.end() else { return }
        withAnimation(animation) { draft = nil }
        lastLegacyTarget = nil
        DashboardHapticFeedback.shared.dragReleased()
    }

    private func cancelDraft() {
        // A reset or another scene can change AppStorage during an interaction.
        // Its newer persisted values take precedence over the local preview.
        draft = nil
        resizing = nil
        endDrag()
    }

    private func finishInteractions() {
        if resizing != nil, let draft { save(draft) }
        resizing = nil
        endDrag()
        draft = nil
    }

    private func moveLegacy(to target: DashboardComponent) {
        guard let item = drag.item, item != target, lastLegacyTarget != target,
              var updated = draft else { return }
        lastLegacyTarget = target
        guard updated.move(item, to: target) else { return }
        withAnimation(animation) { draft = updated }
        if let index = updated.components.firstIndex(of: item), drag.move(to: index) {
            DashboardHapticFeedback.shared.positionChanged()
        }
    }

    private func commitLegacyDrop() -> Bool {
        guard drag.item != nil, let draft else { return false }
        save(draft)
        endDrag()
        return true
    }

    private func moveAccessible(_ component: DashboardComponent, offset: Int) {
        guard drag.item == nil, resizing == nil else { return }
        var updated = persisted
        guard let index = updated.components.firstIndex(of: component),
              updated.components.indices.contains(index + offset),
              updated.move(component, to: updated.components[index + offset]) else { return }
        withAnimation(animation) { save(updated) }
        DashboardHapticFeedback.shared.positionChanged()
    }

    @available(iOS 27.0, *)
    private func applyReorder(_ difference: ReorderDifference<DashboardComponent, ReorderableSingleCollectionIdentifier>) {
        var updated = persisted
        let target: DashboardComponent?
        switch difference.destination.position {
        case .before(let component): target = component
        case .end: target = nil
        @unknown default: return
        }
        guard updated.move(difference.sources, before: target) else { return }
        withAnimation(animation) { save(updated) }
    }

    @available(iOS 27.0, *)
    private func updateDragSession(_ session: DragSession) {
        switch session.phase {
        case .initial: DashboardHapticFeedback.shared.prepare()
        case .active:
            if let component = session.draggedItemIDs(for: DashboardComponent.self).first { beginDrag(component) }
        case .ending, .ended: endDrag()
        default: break
        }
    }

    @available(iOS 27.0, *)
    private func updateDropSession(_ session: DropSession) {
        guard session.phase == .active,
              let item = drag.item,
              session.localSession?.draggedItemIDs(for: DashboardComponent.self).contains(item) == true,
              let destination = session.reorderDestination(for: DashboardComponent.self) else { return }
        var preview = persisted
        switch destination.position {
        case .before(let target): preview.move([item], before: target)
        case .end: preview.move([item], before: nil)
        @unknown default: return
        }
        if let index = preview.components.firstIndex(of: item), drag.move(to: index) {
            DashboardHapticFeedback.shared.positionChanged()
        }
    }
}

private struct DashboardLegacyDropDelegate: DropDelegate {
    let isActive: Bool
    let onEnter: () -> Void
    let onDrop: () -> Bool

    func validateDrop(info: DropInfo) -> Bool { isActive }
    func dropEntered(info: DropInfo) { if isActive { onEnter() } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: isActive ? .move : .forbidden) }
    func performDrop(info: DropInfo) -> Bool { isActive && onDrop() }
}
