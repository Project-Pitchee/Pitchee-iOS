//
//  PitcheeApp.swift
//  Pitchee
//
//  Created by Lvy Zhan on 2026/6/12.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct PitcheeApp: App {
    private let container: ModelContainer?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            try PrivateAppStorage.prepare(libraryDirectory: library)
            try PrivateAppStorage.removeAbandonedRecordings(in: FileManager.default.temporaryDirectory)
            AppStorageMigration.run()
            PitcheeAndroidFont.registerBundledFonts()
            AnalyzerSettings.migrateThreadDefaultIfNeeded()
            // Keep SwiftData's existing default URL so no history migration is needed.
            let configuration = ModelConfiguration(schema: Schema([RecordingAssessment.self]), cloudKitDatabase: .none)
            container = try ModelContainer(for: RecordingAssessment.self, configurations: configuration)
        } catch {
            container = nil
            Logger(subsystem: "com.lvyzhan.Pitchee", category: "Storage")
                .error("Private local storage could not be prepared.")
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                ContentView()
                    #if DEBUG
                    .modifier(MonitorReviewModifier())
                    #endif
                    .modelContainer(container)
                    .onAppear {
                        LocalDiagnosticsStore.shared.refresh()
                        LocalScoreStudyStore.shared.refresh()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            LocalDiagnosticsStore.shared.refresh()
                            LocalScoreStudyStore.shared.refresh()
                        }
                    }
            } else {
                ContentUnavailableView {
                    Label("settings.privateStorage.unavailable.title", systemImage: "lock.trianglebadge.exclamationmark")
                } description: {
                    Text("settings.privateStorage.unavailable.description")
                }
            }
        }
    }
}
