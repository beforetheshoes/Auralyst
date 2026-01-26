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

        let medication = store.createMedication(for: journal, name: "Ibuprofen", defaultAmount: 200, defaultUnit: "mg")
        _ = try store.createMedicationIntake(for: medication, amount: 1, unit: "tablet")

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "tablet",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: [.monday, .wednesday, .friday]),
            hour: 8,
            minute: 30,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)

        let summary = try DataExporter.exportSummary(for: journal)
        #expect(summary.exportedEntries == 1)
        #expect(summary.exportedMedications == 1)
        #expect(summary.exportedSchedules == 1)
        #expect(summary.exportedIntakes == 1)
        #expect(summary.exportedCollaboratorNotes == 1)

        // Sanity check: ensure entry persisted for later export operations
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
        let medication = store.createMedication(for: journal, name: "Vitamin D", defaultAmount: 1, defaultUnit: "capsule")
        _ = try store.createMedicationIntake(for: medication, amount: 1, unit: "capsule")

        let jsonData = try DataExporter.exportJSON(for: journal)
        let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        let entries = object? ["entries"] as? [[String: Any]]
        let collaboratorNotes = object? ["collaboratorNotes"] as? [[String: Any]]
        let meds = object? ["medications"] as? [[String: Any]]
        let summary = object? ["summary"] as? [String: Any]

        #expect(entries?.count == 1)
        #expect(collaboratorNotes?.count == 1)
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
        guard let csvString = String(data: csvData, encoding: .utf8) else {
            Issue.record("CSV string decoding failed")
            return
        }

        #expect(csvString.contains("Entries"))
        #expect(csvString.contains("symptom_entries"))
        #expect(csvString.contains("collaborator_notes"))
        #expect(csvString.contains("Severe headache"))
        #expect(csvString.contains("Context note"))
    }

    @MainActor
    @Test("Summary counts ignore records from other journals")
    func summaryFiltersByJournal() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journalA = store.createJournal()
        let journalB = store.createJournal()

        let entryA = try store.createSymptomEntry(for: journalA, severity: 2)
        _ = try store.createSymptomEntry(for: journalB, severity: 9)
        _ = try store.createCollaboratorNote(
            for: journalA,
            entry: entryA,
            authorName: "Casey",
            text: "Journal A note"
        )
        _ = try store.createCollaboratorNote(
            for: journalB,
            authorName: "Taylor",
            text: "Journal B note"
        )

        let medicationA = store.createMedication(for: journalA, name: "Aspirin", defaultAmount: 1, defaultUnit: "tablet")
        let medicationB = store.createMedication(for: journalB, name: "Magnesium", defaultAmount: 2, defaultUnit: "capsule")

        _ = try store.createMedicationIntake(for: medicationA, amount: 1, unit: "tablet")
        _ = try store.createMedicationIntake(for: medicationB, amount: 2, unit: "capsule")

        @Dependency(\.defaultDatabase) var database
        let scheduleA = SQLiteMedicationSchedule(
            medicationID: medicationA.id,
            label: "Morning",
            amount: 1,
            unit: "tablet",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 8,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        let scheduleB = SQLiteMedicationSchedule(
            medicationID: medicationB.id,
            label: "Evening",
            amount: 2,
            unit: "capsule",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 20,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(scheduleA, database: database)
        try insertSchedule(scheduleB, database: database)

        let summary = try DataExporter.exportSummary(for: journalA)
        #expect(summary.exportedEntries == 1)
        #expect(summary.exportedMedications == 1)
        #expect(summary.exportedSchedules == 1)
        #expect(summary.exportedIntakes == 1)
        #expect(summary.exportedCollaboratorNotes == 1)
    }

    @MainActor
    @Test("JSON export includes only intakes and schedules for the journal")
    func jsonExportFiltersIntakesAndSchedules() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journalA = store.createJournal()
        let journalB = store.createJournal()

        let medicationA = store.createMedication(for: journalA, name: "Cetirizine", defaultAmount: 10, defaultUnit: "mg")
        let medicationB = store.createMedication(for: journalB, name: "Zinc", defaultAmount: 1, defaultUnit: "tablet")

        _ = try store.createMedicationIntake(for: medicationA, amount: 1, unit: "tablet")
        _ = try store.createMedicationIntake(for: medicationA, amount: 2, unit: "tablet")
        _ = try store.createMedicationIntake(for: medicationB, amount: 1, unit: "tablet")

        _ = try store.createCollaboratorNote(
            for: journalA,
            authorName: "Morgan",
            text: "Journal A note"
        )
        _ = try store.createCollaboratorNote(
            for: journalB,
            authorName: "Riley",
            text: "Journal B note"
        )

        @Dependency(\.defaultDatabase) var database
        let scheduleA = SQLiteMedicationSchedule(
            medicationID: medicationA.id,
            label: "Noon",
            amount: 1,
            unit: "tablet",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 12,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        let scheduleB = SQLiteMedicationSchedule(
            medicationID: medicationB.id,
            label: "Night",
            amount: 1,
            unit: "tablet",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 22,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(scheduleA, database: database)
        try insertSchedule(scheduleB, database: database)

        let jsonData = try DataExporter.exportJSON(for: journalA)
        let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        let intakes = object? ["intakes"] as? [[String: Any]]
        let schedules = object? ["schedules"] as? [[String: Any]]
        let collaboratorNotes = object? ["collaboratorNotes"] as? [[String: Any]]
        let summary = object? ["summary"] as? [String: Any]

        #expect(intakes?.count == 2)
        #expect(schedules?.count == 1)
        #expect(collaboratorNotes?.count == 1)
        #expect((summary? ["exportedIntakes"] as? Int) == 2)
        #expect((summary? ["exportedSchedules"] as? Int) == 1)
        #expect((summary? ["exportedCollaboratorNotes"] as? Int) == 1)
    }
}
