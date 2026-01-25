#if os(iOS)
import ComposableArchitecture
import SwiftUI
import UIKit

@main
struct AuralystApp: App {
    private let isRunningTests: Bool
    private let configuration: AppBootstrap.Configuration

    init() {
        let runningTests = AppBootstrap.isRunningTests()
        let configuration = AppBootstrap.makeConfiguration(isRunningTests: runningTests)
        self.isRunningTests = runningTests
        self.configuration = configuration

        if configuration.shouldConfigureAppearance {
            configureAppearance()
        }

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

private extension AuralystApp {
    func configureAppearance() {
        UINavigationBar.appearance().tintColor = UIColor(Color.brandAccent)
    }
}
#endif
