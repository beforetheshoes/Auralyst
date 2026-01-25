#if os(macOS)
import ComposableArchitecture
import SwiftUI

@main
struct AuralystMacApp: App {
    private let isRunningTests: Bool
    private let configuration: AppBootstrap.Configuration

    init() {
        let runningTests = AppBootstrap.isRunningTests()
        let configuration = AppBootstrap.makeConfiguration(isRunningTests: runningTests)
        self.isRunningTests = runningTests
        self.configuration = configuration

        AppBootstrap.initializeEnvironment(isRunningTests: runningTests)
    }

    var body: some Scene {
        AppRootScene(
            store: Store(
                initialState: AppFeature.State(
                    isRunningTests: isRunningTests,
                    shouldStartSync: configuration.shouldStartSync,
                    overridePhaseRaw: ProcessInfo.processInfo.environment["AURALYST_SYNC_STATUS"],
                    bypassInitialOverlay: ProcessInfo.processInfo.environment["AURALYST_SKIP_INITIAL_OVERLAY"] == "1"
                )
            ) {
                AppFeature()
            }
        )
    }
}
#endif
