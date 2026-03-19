import Foundation
import Testing
import Dependencies
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Data Exporter", .serialized)
struct DataExporterSuite {
    @MainActor
    @Test("Summary counts match database state")
    func summaryCounts() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal,
            severity: 6,
            note: "Evening log",
            timestamp: Date(timeIntervalSince1970: 1_726_601_200),
            isMenstruating: true
        )
        _ = try store.createCollaboratorNote(
            for: journal,
            entry: entry,
            authorName: "Alex",
            text: "Shared context"
        )

        let medication = store.createMedication(
            for: journal, name: "Ibuprofen",
            defaultAmount: 200, defaultUnit: "mg"
        )
        _ = try store.createMedicationIntake(
            for: medication, amount: 1, unit: "tablet"
        )

        @Dependency(\.defaultDatabase) var database
        try insertExporterSchedule(
            for: medication, database: database,
            label: "Morning",
            daysOfWeekMask: MedicationWeekday.mask(
                for: [.monday, .wednesday, .friday]
            ),
            hour: 8, minute: 30
        )

        let summary = try DataExporter.exportSummary(
            for: journal
        )
        #expect(summary.exportedEntries == 1)
        #expect(summary.exportedMedications == 1)
        #expect(summary.exportedSchedules == 1)
        #expect(summary.exportedIntakes == 1)
        #expect(summary.exportedCollaboratorNotes == 1)

        #expect(entry.id != UUID())
    }

    @MainActor
    @Test("JSON export produces structured payload")
    func jsonPayloadIncludesRecords() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        _ = try store.createSymptomEntry(
            for: journal,
            severity: 4,
            note: "Morning log"
        )
        _ = try store.createCollaboratorNote(
            for: journal,
            authorName: "Jamie",
            text: "Follow-up"
        )
        let medication = store.createMedication(
            for: journal, name: "Vitamin D",
            defaultAmount: 1, defaultUnit: "capsule"
        )
        _ = try store.createMedicationIntake(
            for: medication, amount: 1, unit: "capsule"
        )

        let jsonData = try DataExporter.exportJSON(for: journal)
        let object = try JSONSerialization.jsonObject(
            with: jsonData
        ) as? [String: Any]
        let entries = object? ["entries"] as? [[String: Any]]
        let notes = object? ["collaboratorNotes"]
            as? [[String: Any]]
        let meds = object? ["medications"] as? [[String: Any]]
        let summary = object? ["summary"] as? [String: Any]

        #expect(entries?.count == 1)
        #expect(notes?.count == 1)
        #expect(meds?.count == 1)
        #expect((summary? ["exportedEntries"] as? Int) == 1)
    }

    @MainActor
    @Test("CSV export includes headers and rows")
    func csvPayloadContainsHeaders() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        _ = try store.createSymptomEntry(
            for: journal,
            severity: 8,
            note: "Severe headache"
        )
        _ = try store.createCollaboratorNote(
            for: journal,
            authorName: "Pat",
            text: "Context note"
        )

        let csvData = try DataExporter.exportCSV(for: journal)
        guard let csvString = String(
            data: csvData, encoding: .utf8
        ) else {
            Issue.record("CSV string decoding failed")
            return
        }

        #expect(csvString.contains("Entries"))
        #expect(csvString.contains("symptom_entries"))
        #expect(csvString.contains("collaborator_notes"))
        #expect(csvString.contains("Severe headache"))
        #expect(csvString.contains("Context note"))
    }
}

// MARK: - Schedule Helper

func insertExporterSchedule(
    for medication: SQLiteMedication,
    database: any DatabaseWriter,
    label: String = "Morning",
    daysOfWeekMask: Int16? = nil,
    hour: Int16 = 8,
    minute: Int16 = 0
) throws {
    let mask = daysOfWeekMask ?? MedicationWeekday.mask(
        for: MedicationWeekday.allCases
    )
    let schedule = SQLiteMedicationSchedule(
        medicationID: medication.id,
        label: label,
        amount: 1,
        unit: "tablet",
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: mask,
        hour: hour,
        minute: minute,
        isActive: true,
        sortOrder: 0
    )
    try insertSchedule(schedule, database: database)
}

private func isNull(_ value: Any?) -> Bool {
    value == nil || value is NSNull
}
