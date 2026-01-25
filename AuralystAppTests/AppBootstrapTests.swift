import XCTest
@testable import AuralystApp

final class AppBootstrapTests: XCTestCase {
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
