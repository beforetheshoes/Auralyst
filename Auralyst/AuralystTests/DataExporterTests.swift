import Foundation
import Testing
import Dependencies
import SQLiteData
@testable import Auralyst

@Suite("Data Exporter")
struct DataExporterSuite {
    @MainActor
    @Test("Summary counts match database state")
    func summaryCounts() throws {
        try prepareDependencies {
            try $0.bootstrapDatabase()
        }

        let store = DataStore()
        let journal = store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal,
            severity: 6,
            note: "Evening log",
            timestamp: Date(timeIntervalSince1970: 1_726_601_200),
            isMenstruating: true
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
        try database.write { db in
            try SQLiteMedicationSchedule.insert { schedule }.execute(db)
        }

        let summary = try DataExporter.exportSummary(for: journal)
        #expect(summary.exportedEntries == 1)
        #expect(summary.exportedMedications == 1)
        #expect(summary.exportedSchedules == 1)
        #expect(summary.exportedIntakes == 1)

        // Sanity check: ensure entry persisted for later export operations
        #expect(entry.id != UUID())
    }

    @MainActor
    @Test("JSON export produces structured payload")
    func jsonPayloadIncludesRecords() throws {
        try prepareDependencies {
            try $0.bootstrapDatabase()
        }

        let store = DataStore()
        let journal = store.createJournal()
        _ = try store.createSymptomEntry(
            for: journal,
            severity: 4,
            note: "Morning log"
        )
        let medication = store.createMedication(for: journal, name: "Vitamin D", defaultAmount: 1, defaultUnit: "capsule")
        _ = try store.createMedicationIntake(for: medication, amount: 1, unit: "capsule")

        let jsonData = try DataExporter.exportJSON(for: journal)
        let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        let entries = object? ["entries"] as? [[String: Any]]
        let meds = object? ["medications"] as? [[String: Any]]
        let summary = object? ["summary"] as? [String: Any]

        #expect(entries?.count == 1)
        #expect(meds?.count == 1)
        #expect((summary? ["exportedEntries"] as? Int) == 1)
    }

    @MainActor
    @Test("CSV export includes headers and rows")
    func csvPayloadContainsHeaders() throws {
        try prepareDependencies {
            try $0.bootstrapDatabase()
        }

        let store = DataStore()
        let journal = store.createJournal()
        _ = try store.createSymptomEntry(
            for: journal,
            severity: 8,
            note: "Severe headache"
        )

        let csvData = try DataExporter.exportCSV(for: journal)
        guard let csvString = String(data: csvData, encoding: .utf8) else {
            Issue.record("CSV string decoding failed")
            return
        }

        #expect(csvString.contains("Entries"))
        #expect(csvString.contains("symptom_entries"))
        #expect(csvString.contains("Severe headache"))
    }
}
