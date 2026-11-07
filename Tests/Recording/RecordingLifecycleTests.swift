import Foundation
import SwiftData

@main
enum RecordingLifecycleTests {
    @MainActor
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            precondition(condition, message)
        }
        let fixture = CaptureFixture.shared
        let container = try ModelContainer(for: RecordingAssessment.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        // Permission prompts make the scene inactive without leaving the app.
        fixture.reset()
        let permissionModel = AnalysisViewModel()
        permissionModel.primaryButtonTapped(modelContext: context)
        await waitFor { AVAudioApplication.permission != nil }
        permissionModel.handleSceneInactive(isBackground: false)
        check(permissionModel.isRequestingPermission, "The permission prompt must not cancel startup")
        AVAudioApplication.respond(true)
        await settle()
        check(fixture.count("start") == 0, "Granted permission cannot open the microphone in an inactive scene")
        permissionModel.handleSceneActive()
        await waitFor { permissionModel.isRecording }
        check(fixture.count("start") == 1, "Permission dismissal starts one capture")
        permissionModel.interruptCapture()
        await waitFor { permissionModel.hasResult }
        check(fixture.count("finish") == 1 && fixture.count("cancel") == 0,
              "Leaving a started take finalizes its audio instead of discarding it")
        check(permissionModel.captureNotice != nil && fixture.count("analyze") == 1,
              "Partial audio receives an interruption notice and one analysis")
        check(try context.fetchCount(FetchDescriptor<RecordingAssessment>()) == 1,
              "The interrupted result is saved using the existing history schema")
        permissionModel.interruptCapture()
        check(fixture.count("finish") == 1, "Repeated leave events cannot stop or analyze twice")

        fixture.reset()
        let cancelledPermission = AnalysisViewModel()
        cancelledPermission.primaryButtonTapped(modelContext: context)
        await waitFor { AVAudioApplication.permission != nil }
        cancelledPermission.handleSceneInactive(isBackground: true)
        AVAudioApplication.respond(true)
        cancelledPermission.handleSceneActive()
        await settle()
        check(cancelledPermission.state == .idle && fixture.count("start") == 0,
              "A permission completion after going to background cannot resurrect capture")

        fixture.reset()
        let deniedPermission = AnalysisViewModel()
        deniedPermission.primaryButtonTapped(modelContext: context)
        await waitFor { AVAudioApplication.permission != nil }
        AVAudioApplication.respond(false)
        await waitFor { deniedPermission.state == .idle }
        check(deniedPermission.recordingError != nil && fixture.count("start") == 0,
              "Denied permission shows an error without opening capture")

        fixture.reset()
        let activationGate = LifecycleAsyncGate()
        AudioSessionController.gate = activationGate
        let obsoleteStartup = AnalysisViewModel()
        obsoleteStartup.primaryButtonTapped(modelContext: context)
        await waitFor { AVAudioApplication.permission != nil }
        AVAudioApplication.respond(true)
        await waitFor { fixture.count("activationWaiting") == 1 }
        obsoleteStartup.interruptCapture()
        check(obsoleteStartup.state == .idle && fixture.count("start") == 0,
              "Leaving before engine creation cancels startup and releases its activation attempt")
        AudioSessionController.gate = nil
        let successor = try await start(context: context)
        activationGate.open()
        await settle()
        check(successor.isRecording && obsoleteStartup.state == .idle && fixture.count("start") == 1,
              "Obsolete activation completion cannot resurrect capture or alter a successor's state")
        check(fixture.count("deactivate") == 1, "Obsolete activation cannot release a successor's lease")
        successor.interruptCapture()
        await waitFor { successor.hasResult }

        fixture.reset()
        let backgroundModel = try await start(context: context)
        backgroundModel.handleSceneInactive(isBackground: true)
        await waitFor { fixture.count("closed") == 1 && fixture.count("deactivate") == 1 }
        check(backgroundModel.isAnalyzing && fixture.count("analyze") == 0,
              "Background stops hardware and drains WAV without starting protected-file analysis")
        check(fixture.lastURL.map { FileManager.default.fileExists(atPath: $0.path) } == true,
              "The drained WAV survives until foreground analysis")
        backgroundModel.handleSceneActive()
        await waitFor { backgroundModel.hasResult }
        check(fixture.count("analyze") == 1 && fixture.count("cancel") == 0,
              "Foreground resumes only analysis, never microphone capture")
        check(fixture.count("start") == 1, "Returning to the app does not silently resume the utterance")

        for notification in [
            Notification(name: AVAudioSession.interruptionNotification,
                         userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]),
            Notification(name: AVAudioSession.routeChangeNotification,
                         userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]),
            Notification(name: AVAudioSession.routeChangeNotification,
                         userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue]),
            Notification(name: AVAudioSession.routeChangeNotification,
                         userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue]),
            Notification(name: AVAudioSession.mediaServicesWereResetNotification)
        ] {
            fixture.reset()
            let model = try await start(context: context)
            NotificationCenter.default.post(notification)
            await waitFor { model.hasResult }
            check(fixture.count("finish") == 1 && fixture.count("analyze") == 1,
                  "System interruption, device changes and media reset finalize the take exactly once")
        }
        fixture.reset()
        let unchangedRoute = try await start(context: context)
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue])
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        await settle()
        check(unchangedRoute.isRecording && fixture.count("finish") == 0,
              "Our category changes and interruption-ended notifications cannot stop a take")
        unchangedRoute.primaryButtonTapped(modelContext: context)
        await waitFor { unchangedRoute.hasResult }
        check(unchangedRoute.captureNotice == nil, "Normal completion does not show an interruption notice")

        // Reusing one scoring page must remain a normal sequence of independent
        // recordings after removing the abandoned A/B practice session state.
        fixture.reset()
        let ordinaryModel = AnalysisViewModel()
        let historyBeforeRetakes = try context.fetchCount(FetchDescriptor<RecordingAssessment>())
        var ordinaryURLs: [URL] = []
        var ordinaryAssessmentIDs: Set<UUID> = []
        for _ in 0..<3 {
            ordinaryModel.primaryButtonTapped(modelContext: context)
            check(ordinaryModel.isRequestingPermission && ordinaryModel.result == nil &&
                  ordinaryModel.assessment == nil && ordinaryModel.volumeStatistics == nil &&
                  ordinaryModel.livePitchSamples.isEmpty && ordinaryModel.elapsedTime == 0,
                  "Ordinary re-recording clears the prior result and realtime presentation")
            await waitFor { AVAudioApplication.permission != nil }
            AVAudioApplication.respond(true)
            await waitFor { ordinaryModel.isRecording }
            guard let url = fixture.lastURL else { preconditionFailure("Capture must create a WAV") }
            check(!ordinaryURLs.contains(url), "Each ordinary recording gets its own temporary WAV")
            ordinaryURLs.append(url)
            fixture.emitPitch([.init(elapsedTime: 0, pitchHz: 180), .init(elapsedTime: 45, pitchHz: 210)])
            await waitFor { ordinaryModel.livePitchSamples.last?.elapsedTime == 45 }
            check(ordinaryModel.livePitchSamples.count == 1 && ordinaryModel.livePitchSamples[0].pitchHz == 210,
                  "The live chart still retains only its recent 30-second window")
            ordinaryModel.primaryButtonTapped(modelContext: context)
            await waitFor { ordinaryModel.hasResult }
            guard let assessment = ordinaryModel.assessment else { preconditionFailure("History must be saved") }
            check(ordinaryAssessmentIDs.insert(assessment.id).inserted && assessment.practice == nil &&
                  assessment.comparedToID == nil && assessment.quality != nil,
                  "Ordinary recordings save distinct history and quality without an A/B relationship")
            await waitFor { !FileManager.default.fileExists(atPath: url.path) }
            check(ordinaryURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
                  "Successful analysis releases every completed temporary WAV")
        }
        check(fixture.count("start") == 3 && fixture.count("finish") == 3 && fixture.count("analyze") == 3 &&
              fixture.count("cancel") == 0,
              "Repeated ordinary takes each capture, finish and analyze once")
        check(try context.fetchCount(FetchDescriptor<RecordingAssessment>()) == historyBeforeRetakes + 3,
              "Re-recording preserves earlier history when its temporary audio is removed")

        // An interruption can arrive while detached engine startup is returning.
        let startGate = DispatchSemaphore(value: 0)
        let finishGate = LifecycleAsyncGate()
        fixture.reset(start: startGate, finish: finishGate)
        let startupModel = AnalysisViewModel()
        startupModel.primaryButtonTapped(modelContext: context)
        await waitFor { AVAudioApplication.permission != nil }
        AVAudioApplication.respond(true)
        await waitFor { fixture.count("start") == 1 }
        startupModel.interruptCapture()
        await waitFor { fixture.count("finish") == 1 }
        check(startupModel.isAnalyzing, "Interruption during startup immediately leaves the recording controls")
        let newHolder = NSObject()
        do {
            try await AudioSessionController.activate(owner: UUID(), use: .piano, holder: newHolder)
            preconditionFailure("Startup teardown must protect its draining WAV session")
        } catch AudioSessionCoordinator.Failure.recordingInProgress {}
        check(fixture.count("deactivate") == 0, "The recording lease survives until the WAV closes")
        startGate.signal()
        await settle()
        check(fixture.count("cancel") == 0 && fixture.lastURL.map { FileManager.default.fileExists(atPath: $0.path) } == true,
              "Late startup completion cannot discard an interrupted take")
        finishGate.open()
        await waitFor { startupModel.hasResult }
        check(fixture.count("deactivate") == 1 && fixture.count("analyze") == 1,
              "Startup interruption releases and analyzes only after finishing")

        let releasedFinishGate = LifecycleAsyncGate()
        fixture.reset(finish: releasedFinishGate)
        var releasedModel: AnalysisViewModel? = try await start(context: context)
        weak let weakModel = releasedModel
        releasedModel?.interruptCapture()
        await waitFor { fixture.count("finish") == 1 }
        releasedModel = nil
        check(weakModel == nil, "A draining capture must not retain its released screen")
        do {
            try await AudioSessionController.activate(owner: UUID(), use: .piano, holder: newHolder)
            preconditionFailure("Screen deinitialization must not reclaim a draining recording")
        } catch AudioSessionCoordinator.Failure.recordingInProgress {}
        check(fixture.count("deactivate") == 0, "Screen cleanup leaves the lease with the draining capture")
        releasedFinishGate.open()
        await waitFor { fixture.count("deactivate") == 1 }
        await settle()
        check(fixture.count("analyze") == 0 && fixture.lastURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true,
              "A released model cleans up its file and session after draining")

        fixture.reset(failFinish: true)
        let failedWrite = try await start(context: context)
        failedWrite.interruptCapture()
        await waitFor { failedWrite.state == .idle }
        check(failedWrite.analysisError != nil && fixture.count("analyze") == 0,
              "Drain write failures show an explicit error without analyzing a damaged file")
        check(fixture.lastURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true,
              "A failed WAV is removed only after teardown")

        fixture.reset(failAnalysis: true)
        let historyBeforeFailure = try context.fetchCount(FetchDescriptor<RecordingAssessment>())
        let failedAnalysis = try await start(context: context)
        failedAnalysis.primaryButtonTapped(modelContext: context)
        await waitFor { failedAnalysis.state == .idle && failedAnalysis.analysisError != nil }
        check(fixture.count("finish") == 1 && fixture.count("analyze") == 1 &&
              fixture.lastURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true,
              "Analysis failure releases the ordinary recording's temporary WAV after closing capture")
        check(try context.fetchCount(FetchDescriptor<RecordingAssessment>()) == historyBeforeFailure,
              "A failed analysis never replaces or appends saved history")

        fixture.reset()
        let liveFailure = try await start(context: context)
        fixture.failWrite()
        await waitFor { liveFailure.state == .idle && fixture.count("deactivate") == 1 }
        check(fixture.count("cancel") == 1 && fixture.count("analyze") == 0 && liveFailure.recordingError != nil,
              "Capture write failure cancels explicitly and recovers the session")

        fixture.reset()
        AudioSessionController.shouldFail = true
        let failedActivation = AnalysisViewModel()
        failedActivation.primaryButtonTapped(modelContext: context)
        await waitFor { AVAudioApplication.permission != nil }
        AVAudioApplication.respond(true)
        await waitFor { failedActivation.state == .idle }
        check(fixture.count("start") == 0 && fixture.count("deactivate") == 1,
              "Failed session activation releases the lease without opening capture")
        AudioSessionController.shouldFail = false
        let recovered = try await start(context: context)
        recovered.interruptCapture()
        await waitFor { recovered.hasResult }
        check(fixture.count("start") == 1, "A take can start after an activation failure")

        print("Recording lifecycle: \(checks) checks passed")
    }

    @MainActor
    private static func start(context: ModelContext) async throws -> AnalysisViewModel {
        let model = AnalysisViewModel()
        model.primaryButtonTapped(modelContext: context)
        await waitFor { AVAudioApplication.permission != nil }
        AVAudioApplication.respond(true)
        await waitFor { model.isRecording }
        return model
    }

    @MainActor
    private static func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<2_500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        preconditionFailure("Timed out waiting for a recording lifecycle transition")
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(40))
    }
}
