import Foundation

@main
enum AudioSessionCoordinatorTests {
    @MainActor
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            precondition(condition, message)
        }

        for use in [AudioSessionCoordinator.Use.recording, .piano, .playback] {
            var events: [String] = []
            let coordinator = AudioSessionCoordinator(
                activate: { _ in events.append("activate") },
                deactivate: { events.append("deactivate") }
            )
            let oldID = UUID(), newID = UUID()
            var oldHolder: NSObject? = NSObject()
            weak let weakHolder = oldHolder
            try await coordinator.activate(owner: oldID, use: use, holder: oldHolder!) {}
            oldHolder = nil
            check(weakHolder == nil, "Leases must not keep a released screen alive")
            let newHolder = NSObject()
            try await coordinator.activate(owner: newID, use: .recording, holder: newHolder) {}
            check(events == ["activate", "deactivate", "activate"],
                  "Orphaned recording, piano and playback leases recover before activating")
            coordinator.release(owner: oldID)
            check(events.count == 3, "Late orphan cleanup cannot deactivate its successor")
            coordinator.release(owner: newID)
            check(events.count == 4, "The successor releases exactly once")
            coordinator.release(owner: newID)
            check(events.count == 4, "Repeated cleanup is harmless")
        }

        var activations = 0, deactivations = 0, stopCalls = 0
        let coordinator = AudioSessionCoordinator(
            activate: { _ in activations += 1 },
            deactivate: { deactivations += 1 }
        )
        let recordingID = UUID()
        var recordingHolder: NSObject? = NSObject()
        try await coordinator.activate(owner: recordingID, use: .recording, holder: recordingHolder!) {
            stopCalls += 1
        }
        let otherHolder = NSObject()
        for use in [AudioSessionCoordinator.Use.recording, .piano, .playback] {
            do {
                try await coordinator.activate(owner: UUID(), use: use, holder: otherHolder) {}
                preconditionFailure("A live recording must never be forcibly reclaimed")
            } catch AudioSessionCoordinator.Failure.recordingInProgress {}
            check(activations == 1 && deactivations == 0 && stopCalls == 0,
                  "A live recording protects the engine and accepted writes")
        }
        let drainingCapture = NSObject()
        coordinator.retainUntilStopped(owner: recordingID, holder: drainingCapture)
        recordingHolder = nil
        do {
            try await coordinator.activate(owner: UUID(), use: .piano, holder: otherHolder) {}
            preconditionFailure("A capture still draining must keep the recording lease")
        } catch AudioSessionCoordinator.Failure.recordingInProgress {}
        check(deactivations == 0, "A released screen cannot expose its draining capture to preemption")
        coordinator.retainUntilStopped(owner: UUID(), holder: otherHolder)
        coordinator.release(owner: recordingID)
        check(deactivations == 1, "Drain completion releases its original session")

        let playbackID = UUID(), nextID = UUID()
        try await coordinator.activate(owner: playbackID, use: .playback, holder: otherHolder) {
            stopCalls += 1
            coordinator.release(owner: playbackID)
        }
        try await coordinator.activate(owner: nextID, use: .piano, holder: otherHolder) {}
        check(stopCalls == 1 && deactivations == 2, "Live playback hands off synchronously")
        coordinator.release(owner: nextID)

        try await coordinator.activate(owner: playbackID, use: .playback, holder: otherHolder) {}
        do {
            try await coordinator.activate(owner: nextID, use: .piano, holder: otherHolder) {}
            preconditionFailure("A live holder that failed to stop must not be overwritten")
        } catch AudioSessionCoordinator.Failure.sessionBusy {}
        check(deactivations == 3, "A live unresponsive owner remains protected")
        coordinator.release(owner: playbackID)

        let gate = ActivationGate()
        var pendingDeactivations = 0
        let pendingCoordinator = AudioSessionCoordinator(
            activate: { use in if use == .playback { await gate.wait() } },
            deactivate: { pendingDeactivations += 1 }
        )
        let pendingID = UUID(), successorID = UUID()
        let pending = Task {
            try await pendingCoordinator.activate(owner: pendingID, use: .playback, holder: otherHolder) {
                pendingCoordinator.release(owner: pendingID)
            }
        }
        while !gate.isWaiting { await Task.yield() }
        try await pendingCoordinator.activate(owner: successorID, use: .recording, holder: otherHolder) {}
        gate.open()
        do {
            try await pending.value
            preconditionFailure("An obsolete activation must reject late completion")
        } catch is CancellationError {}
        check(pendingDeactivations == 1, "Late activation cannot release the new recording")
        pendingCoordinator.release(owner: successorID)
        check(pendingDeactivations == 2, "The new recording retains independent ownership")

        var failedDeactivations = 0
        let failing = AudioSessionCoordinator(
            activate: { _ in throw CocoaError(.fileReadUnknown) },
            deactivate: { failedDeactivations += 1 }
        )
        for _ in 0..<2 {
            do {
                try await failing.activate(owner: UUID(), use: .recording, holder: otherHolder) {}
                preconditionFailure("Injected activation failure must propagate")
            } catch is CocoaError {}
        }
        check(failedDeactivations == 2, "Failed activation releases its lease for the next attempt")
        print("Audio session coordinator: \(checks) checks passed")
    }
}

@MainActor
private final class ActivationGate {
    var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation {
            isWaiting = true
            continuation = $0
        }
    }
    func open() { continuation?.resume(); continuation = nil }
}
