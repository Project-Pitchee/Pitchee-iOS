//
//  DashboardSizing.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import Foundation
import CoreGraphics

enum DashboardComponentSize: String, CaseIterable, Sendable {
    case small, medium, large

    var next: Self {
        switch self {
        case .small: .medium
        case .medium: .large
        case .large: .small
        }
    }

    /// The handle sits in the lower-right corner: right/down expands it and
    /// left/up contracts it. Resolve from the size at touch-down, so a single
    /// drag never cycles repeatedly through the same sizes.
    func resized(by translation: CGSize) -> Self {
        let distance = abs(translation.width) > abs(translation.height)
            ? translation.width : translation.height
        let steps = abs(distance) < 36 ? 0 : (abs(distance) < 100 ? 1 : 2)
        let index = Self.allCases.firstIndex(of: self) ?? 0
        let offset = distance >= 0 ? steps : -steps
        return Self.allCases[min(max(index + offset, 0), Self.allCases.count - 1)]
    }
}

enum DashboardComponentSizes {
    static func decode(_ value: String) -> [String: DashboardComponentSize] {
        guard let data = value.data(using: .utf8),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values.compactMapValues(DashboardComponentSize.init(rawValue:))
    }

    static func encode(_ sizes: [String: DashboardComponentSize]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(sizes.mapValues(\.rawValue)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// All four compact metrics occupy exactly the same grid cell. A wide widget
/// occupies two columns; a large widget occupies two rows as well.
struct DashboardWidgetMetrics {
    let frames: [CGRect]
    let height: CGFloat

    init(width: CGFloat, spacing: CGFloat, minimumHeight: CGFloat, sizes: [DashboardComponentSize]) {
        let width = max(0, width)
        let columnWidth = max(0, (width - spacing) / 2)
        let unitHeight = max(columnWidth, minimumHeight)
        var frames: [CGRect] = []
        var y: CGFloat = 0
        var pendingSmall = false

        for size in sizes {
            if size == .small {
                frames.append(CGRect(
                    x: pendingSmall ? columnWidth + spacing : 0,
                    y: y,
                    width: columnWidth,
                    height: unitHeight
                ))
                if pendingSmall { y += unitHeight + spacing }
                pendingSmall.toggle()
            } else {
                if pendingSmall {
                    y += unitHeight + spacing
                    pendingSmall = false
                }
                let height = size == .large ? unitHeight * 2 + spacing : unitHeight
                frames.append(CGRect(x: 0, y: y, width: width, height: height))
                y += height + spacing
            }
        }
        if pendingSmall { y += unitHeight + spacing }
        self.frames = frames
        self.height = frames.isEmpty ? 0 : y - spacing
    }
}

/// A drag session can report the same phase or destination many times. Only
/// actual lift, slot change, and release transitions should produce feedback.
struct DashboardDragFeedbackState<Item: Hashable> {
    private(set) var item: Item?
    private(set) var insertionIndex: Int?

    mutating func begin(_ item: Item, at index: Int) -> Bool {
        guard self.item == nil else { return false }
        self.item = item
        insertionIndex = index
        return true
    }

    mutating func move(to index: Int) -> Bool {
        guard item != nil, insertionIndex != index else { return false }
        insertionIndex = index
        return true
    }

    mutating func end() -> Bool {
        guard item != nil else { return false }
        item = nil
        insertionIndex = nil
        return true
    }
}
