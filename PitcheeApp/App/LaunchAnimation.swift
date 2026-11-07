import SwiftUI

enum LaunchPhase: Equatable {
    case initial, contracted, revealed, finished
}

enum LaunchAnimation {
    @MainActor
    static func run(
        showsOnboarding: Bool,
        reduceMotion: Bool,
        update: (LaunchPhase) -> Void
    ) async {
        do {
            try Task.checkCancellation()
            if reduceMotion {
                withAnimation(nil) { update(.finished) }
                return
            }

            try await Task.sleep(for: .seconds(0.45))
            withAnimation(showsOnboarding
                ? .bouncy(duration: 0.5, extraBounce: 0.05)
                : .smooth(duration: 0.3)) {
                update(.contracted)
            }

            try await Task.sleep(for: .seconds(showsOnboarding ? 0.15 : 0.1))
            withAnimation(showsOnboarding
                ? .bouncy(duration: 0.4)
                : .interpolatingSpring(duration: 0.6, bounce: 0, initialVelocity: 0)) {
                update(.revealed)
            }

            try await Task.sleep(for: .seconds(showsOnboarding ? 0.5 : 0.6))
            withAnimation(nil) { update(.finished) }
        } catch {
            // The owning view cancels the sequence when it leaves the hierarchy.
            return
        }
    }
}
