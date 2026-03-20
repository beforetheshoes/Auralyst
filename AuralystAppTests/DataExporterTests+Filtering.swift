import Foundation
import Testing
import Dependencies
@preconcurrency import SQLiteData
@testable import AuralystApp

// MARK: - Journal Filtering Tests

extension DataExporterSuite {
    @MainActor
    @Test("Summary counts ignore records from other journals")
    func summaryFiltersByJournal() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journalA = try store.createJournal()
        let journalB = try store.createJournal()

        let entryA = try store.createSymptomEntry(
            for: journalA, severity: 2
        )
        _ = try store.createSymptomEntry(
            for: journalB, severity: 9
        )
        _ = try store.createCollaboratorNote(
            for: journalA, entry: entryA,
            authorName: "Casey", text: "Journal A note"
        )
        _ = try store.createCollaboratorNote(
            for: journalB,
            authorName: "Taylor", text: "Journal B note"
        )

        let medicationA = store.createMedication(
            for: journalA, name: "Aspirin",
            defaultAmount: 1, defaultUnit: "tablet"
        )
        let medicationB = store.createMedication(
            for: journalB, name: "Magnesium",
            defaultAmount: 2, defaultUnit: "capsule"
        )

        _ = try store.createMedicationIntake(
            for: medicationA, amount: 1, unit: "tablet"
        )
        _ = try store.createMedicationIntake(
            for: medicationB, amount: 2, unit: "capsule"
        )

        @Dependency(\.defaultDatabase) var database
        try insertExporterSchedule(
            for: medicationA, database: database
        )
        try insertFilterSchedule(
            for: medicationB, database: database,
            label: "Evening", hour: 20,
            unit: "capsule", amount: 2
        )

        let summary = try DataExporter.exportSummary(
            for: journalA
        )
        #expect(summary.exportedEntries == 1)
        #expect(summary.exportedMedications == 1)
        #expect(summary.exportedSchedules == 1)
        #expect(summary.exportedIntakes == 1)
        #expect(summary.exportedCollaboratorNotes == 1)
    }

    @MainActor
    @Test("JSON export includes only intakes and schedules")
    func jsonExportFiltersIntakesAndSchedules() throws {
        try prepareTestDependencies()

        let journalA = try createFilterFixture()

        let jsonData = try DataExporter.exportJSON(
            for: journalA
        )
        let object = try JSONSerialization.jsonObject(
            with: jsonData
        ) as? [String: Any]
        let intakes = object? ["intakes"]
            as? [[String: Any]]
        let schedules = object? ["schedules"]
            as? [[String: Any]]
        let notes = object? ["collaboratorNotes"]
            as? [[String: Any]]
        let summary = object? ["summary"]
            as? [String: Any]

        #expect(intakes?.count == 2)
        #expect(schedules?.count == 1)
        #expect(notes?.count == 1)
        assertFilterSummaryCounts(summary)
    }
}

// MARK: - Helpers

private func insertFilterSchedule(
    for medication: SQLiteMedication,
    database: any DatabaseWriter,
    label: String,
    hour: Int16,
    unit: String = "tablet",
    amount: Double = 1
) throws {
    let schedule = SQLiteMedicationSchedule(
        medicationID: medication.id,
        label: label,
        amount: amount,
        unit: unit,
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: MedicationWeekday.mask(
            for: MedicationWeekday.allCases
        ),
        hour: hour,
        minute: 0,
        isActive: true,
        sortOrder: 0
    )
    try insertSchedule(schedule, database: database)
}

@MainActor
private func createFilterFixture() throws -> SQLiteJournal {
    let store = DataStore()
    let journalA = try store.createJournal()
    let journalB = try store.createJournal()

    let medicationA = store.createMedication(
        for: journalA, name: "Cetirizine",
        defaultAmount: 10, defaultUnit: "mg"
    )
    let medicationB = store.createMedication(
        for: journalB, name: "Zinc",
        defaultAmount: 1, defaultUnit: "tablet"
    )

    _ = try store.createMedicationIntake(
        for: medicationA, amount: 1, unit: "tablet"
    )
    _ = try store.createMedicationIntake(
        for: medicationA, amount: 2, unit: "tablet"
    )
    _ = try store.createMedicationIntake(
        for: medicationB, amount: 1, unit: "tablet"
    )

    _ = try store.createCollaboratorNote(
        for: journalA,
        authorName: "Morgan", text: "Journal A note"
    )
    _ = try store.createCollaboratorNote(
        for: journalB,
        authorName: "Riley", text: "Journal B note"
    )

    @Dependency(\.defaultDatabase) var database
    try insertFilterSchedule(
        for: medicationA, database: database,
        label: "Noon", hour: 12
    )
    try insertFilterSchedule(
        for: medicationB, database: database,
        label: "Night", hour: 22
    )

    return journalA
}

private func assertFilterSummaryCounts(
    _ summary: [String: Any]?
) {
    let intakes = summary? ["exportedIntakes"] as? Int
    let schedules = summary? ["exportedSchedules"] as? Int
    let notes =
        summary? ["exportedCollaboratorNotes"] as? Int
    #expect(intakes == 2)
    #expect(schedules == 1)
    #expect(notes == 1)
}
