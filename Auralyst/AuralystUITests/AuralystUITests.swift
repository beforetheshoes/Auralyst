//
//  AuralystUITests.swift
//  AuralystUITests
//
//  Created by Ryan Williams on 9/17/25.
//

import XCTest

final class AuralystUITests: XCTestCase {

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
    func testQuickMedicationLogRefreshesAfterManaging() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORCE_FULL_APP"] = "1"
        app.launch()

        func manageButton() -> XCUIElement {
            let button = app.buttons["Manage Medications"]
            if button.exists { return button }
            let tableButton = app.tables.buttons["Manage Medications"]
            if tableButton.exists { return tableButton }
            let cell = app.cells.containing(.staticText, identifier: "Manage Medications").firstMatch
            return cell.exists ? cell : button
        }

        let manageMedicationsButton: XCUIElement
        let createJournalButton = app.buttons["Create Journal"]
        if createJournalButton.waitForExistence(timeout: 3) {
            createJournalButton.tap()
            manageMedicationsButton = manageButton()
        } else {
            manageMedicationsButton = manageButton()
        }

        XCTAssertTrue(manageMedicationsButton.waitForExistence(timeout: 5))
        manageMedicationsButton.tap()

        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Ibuprofen")

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        var doneButton = app.navigationBars["Medications"].buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        let mainTable = app.tables.firstMatch
        if mainTable.exists {
            mainTable.swipeDown()
            mainTable.swipeUp()
        }

        let quickLogMedication = app.staticTexts["Ibuprofen"]
        XCTAssertTrue(quickLogMedication.waitForExistence(timeout: 8))

    }
}
