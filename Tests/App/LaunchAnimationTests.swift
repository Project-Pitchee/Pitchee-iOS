import Foundation

@main
enum LaunchAnimationTests {
    @MainActor
    static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }

        for showsOnboarding in [true, false] {
            var phases: [LaunchPhase] = []
            await LaunchAnimation.run(showsOnboarding: showsOnboarding, reduceMotion: false) {
                phases.append($0)
            }
            check(phases == [.contracted, .revealed, .finished],
                  "Both launch routes contract, reveal, and finish exactly once")

            phases.removeAll()
            await LaunchAnimation.run(showsOnboarding: showsOnboarding, reduceMotion: true) {
                phases.append($0)
            }
            check(phases == [.finished], "Reduce Motion skips all moving phases")
        }

        for reduceMotion in [true, false] {
            var phases: [LaunchPhase] = []
            let cancelled = Task { @MainActor in
                await LaunchAnimation.run(showsOnboarding: true, reduceMotion: reduceMotion) {
                    phases.append($0)
                }
            }
            cancelled.cancel()
            await cancelled.value
            check(phases.isEmpty, "A task cancelled before entry never updates the view")
        }

        var initialPhases: [LaunchPhase] = []
        let initialTask = Task { @MainActor in
            await LaunchAnimation.run(showsOnboarding: true, reduceMotion: false) {
                initialPhases.append($0)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        initialTask.cancel()
        await initialTask.value
        check(initialPhases.isEmpty, "Cancelling the initial pause never contracts or reveals")

        for showsOnboarding in [true, false] {
            var phases: [LaunchPhase] = []
            var contractedTask: Task<Void, Never>?
            contractedTask = Task { @MainActor in
                await LaunchAnimation.run(showsOnboarding: showsOnboarding, reduceMotion: false) { phase in
                    phases.append(phase)
                    if phase == .contracted { contractedTask?.cancel() }
                }
            }
            await contractedTask?.value
            check(phases == [.contracted], "Cancelling after contraction prevents all later phases")
        }

        print("Launch animation: \(checks) checks passed")
    }
}
