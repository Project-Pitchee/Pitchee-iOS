import Foundation

// Keep audio hardware out of this presentation-state regression test.
@MainActor
final class MonitorViewModel {
    var samples: [Float] = [0.25, -0.25]
    private(set) var stopCount = 0

    func stopForLeaving() {
        stopCount += 1
        samples.removeAll()
    }
}

@main
enum MonitorAccessoryStateTests {
    @MainActor
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }

        let state = MonitorAccessoryState()
        let first = MonitorViewModel()
        let second = MonitorViewModel()
        let samples = first.samples
        check(state.model == nil && !state.isExpanded, "The accessory starts empty and collapsed")

        state.show(first)
        check(state.model === first && !state.isExpanded, "Entering a monitor shows its compact accessory")
        state.isExpanded = true
        state.show(first)
        check(state.model === first && state.isExpanded, "Reappearing during expansion preserves the same session")
        check(first.stopCount == 0 && first.samples == samples, "Expanding never clears retained audio")
        state.isExpanded = false
        state.show(first)
        check(first.stopCount == 0 && first.samples == samples, "Collapsing never clears retained audio")

        state.isExpanded = true
        state.show(second)
        check(state.model === second && !state.isExpanded, "A different monitor starts collapsed")
        check(first.stopCount == 1 && first.samples.isEmpty, "Replacing the monitor stops the old session once")
        check(second.stopCount == 0 && second.samples == samples, "Replacing a monitor preserves the new session")

        state.isExpanded = true
        state.hide(first)
        check(state.model === second && state.isExpanded, "A late disappearance cannot hide the current monitor")
        check(second.stopCount == 0 && second.samples == samples, "A stale disappearance cannot clear current audio")
        state.hide(second)
        check(state.model == nil && !state.isExpanded, "Hiding the current monitor also clears expansion")
        check(second.stopCount == 0 && second.samples == samples, "Hiding leaves audio teardown to the owning destination")

        state.show(second)
        state.isExpanded = true
        state.leavePractice()
        check(state.model == nil && !state.isExpanded, "Leaving practice removes both the accessory and expanded view")
        check(second.stopCount == 1 && second.samples.isEmpty, "Leaving practice clears its retained audio once")
        state.leavePractice()
        check(second.stopCount == 1, "Repeated departure does not stop an already detached session")

        print("Monitor accessory state: \(checks) checks passed")
    }
}
