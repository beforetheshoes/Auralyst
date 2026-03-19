import XCTest
@testable import AuralystApp

final class AppBootstrapTests: XCTestCase {
    func testUIAutomationEnvironmentCountsAsUIAutomation() {
        XCTAssertTrue(
            AppBootstrap.isRunningUIAutomation(
                environment: [
                    "AURALYST_UI_RESET": "1"
                ]
            )
        )
    }

    func testForceFullAppOverridesUIAutomationEnvironment() {
        XCTAssertFalse(
            AppBootstrap.isRunningUIAutomation(
                environment: [
                    "AURALYST_UI_RESET": "1",
                    "FORCE_FULL_APP": "1"
                ]
            )
        )
    }

    func testUIAutomationEnvironmentDoesNotCountAsUnitTests() {
        XCTAssertFalse(
            AppBootstrap.isRunningTests(
                environment: [
                    "AURALYST_UI_RESET": "1"
                ]
            )
        )
    }

    func testConfigurationDisablesSyncWhileRunningTests() {
        let config = AppBootstrap.makeConfiguration(isRunningTests: true)
        XCTAssertFalse(config.shouldStartSync)
        XCTAssertFalse(config.shouldConfigureAppearance)
    }

    func testConfigurationEnablesSyncDuringNormalRuns() {
        let config = AppBootstrap.makeConfiguration(isRunningTests: false)
        XCTAssertTrue(config.shouldStartSync)
        XCTAssertTrue(config.shouldConfigureAppearance)
    }
}
