//
//  DashboardConfiguration.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import Foundation

enum DashboardComponent: String, CaseIterable, Identifiable, Hashable, Sendable {
    case analysisCount
    case openedDays
    case compositeScore
    case naturalness
    case meanPitch

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .analysisCount: "insights.summary.analysisCount.title"
        case .openedDays: "insights.summary.openedDays.title"
        case .compositeScore: "common.metric.compositeScore.title"
        case .naturalness: "common.metric.naturalness.title"
        case .meanPitch: "common.metric.meanPitch.title"
        }
    }

    var symbol: String {
        switch self {
        case .analysisCount: "waveform"
        case .openedDays: "calendar"
        case .compositeScore: "chart.xyaxis.line"
        case .naturalness: "waveform.path.ecg"
        case .meanPitch: "tuningfork"
        }
    }

    var defaultSize: DashboardComponentSize {
        self == .compositeScore ? .medium : .small
    }

    var supportsResizing: Bool {
        switch self {
        case .compositeScore, .naturalness, .meanPitch: true
        case .analysisCount, .openedDays: false
        }
    }
}

/// The persisted dashboard arrangement, independent of rendering and drag state.
/// An empty order is intentional: hiding every component must survive relaunch.
struct DashboardConfiguration: Equatable {
    var components: [DashboardComponent]
    var sizes: [String: DashboardComponentSize]

    static let defaultOrder = DashboardComponent.allCases.map(\.rawValue).joined(separator: ",")

    init(order: String = Self.defaultOrder, sizes: String = "{}") {
        var seen = Set<DashboardComponent>()
        components = order.split(separator: ",")
            .compactMap { DashboardComponent(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        self.sizes = DashboardComponentSizes.decode(sizes)
        for component in DashboardComponent.allCases where !component.supportsResizing {
            self.sizes.removeValue(forKey: component.rawValue)
        }
    }

    var encodedOrder: String { components.map(\.rawValue).joined(separator: ",") }
    var encodedSizes: String { DashboardComponentSizes.encode(sizes) }

    func size(for component: DashboardComponent) -> DashboardComponentSize {
        guard component.supportsResizing else { return .small }
        return sizes[component.rawValue] ?? component.defaultSize
    }

    @discardableResult
    mutating func add(_ component: DashboardComponent) -> Bool {
        guard !components.contains(component) else { return false }
        components.append(component)
        return true
    }

    @discardableResult
    mutating func remove(_ component: DashboardComponent) -> Bool {
        guard let index = components.firstIndex(of: component) else { return false }
        components.remove(at: index)
        return true
    }

    @discardableResult
    mutating func resize(_ component: DashboardComponent, to size: DashboardComponentSize) -> Bool {
        guard component.supportsResizing, components.contains(component),
              self.size(for: component) != size else { return false }
        sizes[component.rawValue] = size
        return true
    }

    /// Native drop destinations describe the gap before a component, or the end.
    /// Resolve the gap after removing the sources so forward moves do not drift.
    /// Multiple sources retain their order in the dashboard, regardless of the
    /// order in which the drag session supplies their identifiers.
    @discardableResult
    mutating func move(_ sources: [DashboardComponent], before target: DashboardComponent?) -> Bool {
        let sourceSet = Set(sources)
        guard !sources.isEmpty, sourceSet.count == sources.count,
              sources.allSatisfy(components.contains) else { return false }
        if let target {
            guard components.contains(target), !sourceSet.contains(target) else { return false }
        }

        let moving = components.filter { sourceSet.contains($0) }
        var reordered = components.filter { !sourceSet.contains($0) }
        let destination = target.flatMap { reordered.firstIndex(of: $0) } ?? reordered.endIndex
        reordered.insert(contentsOf: moving, at: destination)
        guard reordered != components else { return false }
        components = reordered
        return true
    }

    /// Legacy hover targets identify an occupied cell, not an insertion gap.
    /// Moving to its original index permits adjacent forward moves and the last
    /// position. The drag session is responsible for deduplicating hover events.
    @discardableResult
    mutating func move(_ source: DashboardComponent, to target: DashboardComponent) -> Bool {
        guard source != target,
              let sourceIndex = components.firstIndex(of: source),
              let targetIndex = components.firstIndex(of: target) else { return false }
        components.remove(at: sourceIndex)
        components.insert(source, at: targetIndex)
        return true
    }
}
