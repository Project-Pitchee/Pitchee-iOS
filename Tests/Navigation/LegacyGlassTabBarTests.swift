import SwiftUI

@main
enum LegacyGlassTabBarTests {
    @MainActor
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        func selection(at x: CGFloat, width: CGFloat = 400,
                       direction: LayoutDirection = .leftToRight) -> AppTab {
            let position = LegacyGlassTabBar.position(at: x, width: width, direction: direction)
            check(position.isFinite && (0...3).contains(position),
                  "Every gesture must produce a valid tab position")
            return AppTab.allCases[Int(position.rounded())]
        }

        let centers: [(CGFloat, AppTab)] = [
            (50, .trends), (150, .practice), (250, .pianoKeys), (350, .about)
        ]
        for (x, expected) in centers {
            check(selection(at: x) == expected, "Releasing over a tab center selects that tab")
        }

        for (x, expected) in [(99.9, AppTab.trends), (100, .practice),
                              (199.9, .practice), (200, .pianoKeys),
                              (299.9, .pianoKeys), (300, .about)] {
            check(selection(at: x) == expected, "Selection changes at the neighboring tab boundary")
        }

        check(selection(at: -500) == .trends, "Dragging beyond the leading edge selects the first tab")
        check(selection(at: 900) == .about, "Dragging beyond the trailing edge selects the last tab")
        check([50, 350, 150].map { selection(at: CGFloat($0)) } == [.trends, .about, .practice],
              "A drag can cross multiple tabs and then return directly to an earlier tab")

        check(selection(at: 120, width: 320) == .practice, "A narrow window selects the visible second tab")
        check(selection(at: 375, width: 600) == .pianoKeys, "A wider window selects the visible third tab")
        check(selection(at: 150, width: 800) == .trends, "Resizing recalculates selection from current geometry")

        let mirroredCenters: [(CGFloat, AppTab)] = [
            (50, .about), (150, .pianoKeys), (250, .practice), (350, .trends)
        ]
        for (x, expected) in mirroredCenters {
            check(selection(at: x, direction: .rightToLeft) == expected,
                  "Right-to-left selection follows the mirrored visual order")
        }
        check(selection(at: -500, direction: .rightToLeft) == .about,
              "The right-to-left left edge clamps to the last logical tab")
        check(selection(at: 900, direction: .rightToLeft) == .trends,
              "The right-to-left right edge clamps to the first logical tab")
        check(selection(at: 300.1, direction: .rightToLeft) == .trends
              && selection(at: 300, direction: .rightToLeft) == .practice,
              "Right-to-left boundaries use the same selection rule")

        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            check(selection(at: 100, width: 0, direction: direction) == .trends,
                  "An unmeasured width safely falls back to the first tab")
        }

        print("Legacy glass tab bar: \(checks) checks passed")
    }
}
