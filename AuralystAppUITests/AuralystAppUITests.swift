//
//  AuralystAppUITests.swift
//  AuralystAppUITests
//
//  Created by Ryan Williams on 11/30/25.
//

import XCTest

final class AuralystAppUITests: XCTestCase {
    @MainActor
    private func makeApp(fixture: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AURALYST_UI_RESET"] = "1"
        if let fixture {
            app.launchEnvironment["AURALYST_UI_FIXTURE"] = fixture
        }
        return app
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = makeApp()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testQuickLogShowsOnInitialLaunch() throws {
        let app = makeApp(fixture: "quicklog_initial")
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Fixture Daily"].waitForExistence(timeout: 5),
            "Expected scheduled medication to appear on initial launch."
        )
        XCTAssertTrue(
            app.buttons["Fixture Relief"].waitForExistence(timeout: 5),
            "Expected as-needed medication to appear on initial launch."
        )
    }

    @MainActor
    func testAddEntrySavesAndDismisses() throws {
        let app = makeApp(fixture: "journal_only")
        app.launch()

        let addEntryButton = app.buttons["Add Entry"]
        XCTAssertTrue(addEntryButton.waitForExistence(timeout: 5))
        addEntryButton.tap()

        let newEntryNav = app.navigationBars["New Entry"]
        XCTAssertTrue(newEntryNav.waitForExistence(timeout: 5))

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertFalse(
            newEntryNav.waitForExistence(timeout: 2),
            "Expected Add Entry sheet to dismiss after saving."
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else {
            throw XCTSkip("Performance launch test runs only on simulator.")
        }
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApp().launch()
        }
    }
}
