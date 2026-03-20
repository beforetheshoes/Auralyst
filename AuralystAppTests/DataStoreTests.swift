import Foundation
import Testing
import Observation
import Dependencies
import GRDB
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("DataStore SQLiteData integration", .serialized)
struct DataStoreSuite {
    @MainActor
    @Test("DataStore adopts Observation")
    func dataStoreIsObservable() {
        let store = DataStore()
        let mirror = Mirror(reflecting: store)
        #expect(
            mirror.descendant("_observationRegistrar") != nil
        )
    }

    @MainActor
    @Test("Creating and fetching journals persists")
    func createAndFetchJournal() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let created = try store.createJournal()
        let fetched = store.fetchJournal(id: created.id)
        #expect(fetched?.id == created.id)
    }

}

// Isolated in its own suite to avoid SyncEngine teardown crash (rdar://FB000).
// The SyncEngine's complex triggers corrupt the Swift runtime's generic metadata
// caches when deallocated, so this test must not share a serialized suite with
// tests that run after SyncEngine cleanup.
@Suite("CloudKit metadata bug repro")
struct CloudKitMetadataBugSuite {
    // BUG: ensureJournalCloudMetadata does a no-op UPDATE
    // hoping the SQLiteData trigger recreates metadata, but
    // it doesn't. When fixed, flip assertion to #expect(has).
    // See: https://github.com/beforetheshoes/Auralyst/issues/43
    @MainActor
    @Test("Deleted journal metadata is not yet restored")
    func deletedMetadataIsNotRestoredYet() throws {
        try prepareTestDependencies(
            configureSyncEngine: true
        )

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()

        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM sqlitedata_icloud_metadata
                    WHERE recordPrimaryKey = ?
                    AND recordType = ?
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            )
        }

        _ = try store.createSymptomEntry(
            for: journal, severity: 1
        )

        let hasMetadata = try database.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1
                        FROM sqlitedata_icloud_metadata
                        WHERE recordPrimaryKey = ?
                        AND recordType = ?
                    )
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            ) ?? false
        }

        // This asserts current (broken) behavior.
        // When #43 is fixed, this will fail — change to:
        // #expect(hasMetadata)
        #expect(!hasMetadata)
    }
}

// MARK: - Intake & Medication Tests

extension DataStoreSuite {
    @MainActor
    @Test("Updating scheduled intake preserves linkage")
    func updateMedicationIntakePreservesSchedule() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 4, note: "Pre-edit log"
        )
        let medication = store.createMedication(
            for: journal, name: "Levothyroxine",
            defaultAmount: 1, defaultUnit: "tablet"
        )

        let schedule = makeWeekdaySchedule(
            for: medication, hour: 7, minute: 30
        )
        try insertSchedule(schedule, database: database)

        let originalIntake = makeLinkedIntake(
            medication: medication,
            entry: entry,
            schedule: schedule
        )
        try insertIntake(originalIntake, database: database)

        let editedIntake = SQLiteMedicationIntake(
            id: originalIntake.id,
            medicationID: originalIntake.medicationID,
            amount: 2,
            unit: "tablet",
            timestamp: originalIntake.timestamp
                .addingTimeInterval(1800),
            notes: "Adjusted amount"
        )

        try store.updateMedicationIntake(editedIntake)

        let reloaded = store.fetchMedicationIntake(
            id: originalIntake.id
        )
        assertIntakeLinkagePreserved(
            reloaded: reloaded,
            original: originalIntake,
            edited: editedIntake
        )
    }

    @MainActor
    @Test("Deleting a medication cascades schedules/intakes")
    func deleteMedicationRemovesRelatedRecords() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()
        let medication = store.createMedication(
            for: journal, name: "Melatonin",
            defaultAmount: 5, defaultUnit: "mg"
        )

        let schedule = makeAllDaysSchedule(
            for: medication, label: "Bedtime",
            hour: 22, minute: 30
        )

        try database.write { db in
            try insertSchedule(schedule, in: db)
            try insertIntake(
                SQLiteMedicationIntake(
                    medicationID: medication.id,
                    scheduleID: schedule.id,
                    amount: 1,
                    unit: "tablet",
                    timestamp: .now
                ),
                in: db
            )
        }

        try store.deleteMedication(medication.id)

        let remaining = store.fetchMedications(for: journal)
        #expect(remaining.isEmpty)

        try assertCascadeDeleted(
            medicationID: medication.id, database: database
        )
    }
}

// MARK: - Journal Cascade Tests

extension DataStoreSuite {
    @MainActor
    @Test("Deleting a journal cascades to all child records")
    func deleteJournalCascadesToChildren() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 3, note: "Test"
        )
        let medication = store.createMedication(
            for: journal, name: "Aspirin",
            defaultAmount: 1, defaultUnit: "tablet"
        )
        try insertJournalCascadeChildren(
            journal: journal, entry: entry,
            medication: medication, database: database
        )

        // Delete the journal directly via SQL to test
        // ON DELETE CASCADE at the database level.
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM sqLiteJournal WHERE id = ?",
                arguments: [journal.id.uuidString.lowercased()]
            )
        }

        try assertAllChildrenDeleted(database: database)
    }
}

private func insertJournalCascadeChildren(
    journal: SQLiteJournal,
    entry: SQLiteSymptomEntry,
    medication: SQLiteMedication,
    database: any DatabaseWriter
) throws {
    let schedule = makeAllDaysSchedule(
        for: medication, label: "Morning", hour: 8, minute: 0
    )
    try database.write { db in
        try insertSchedule(schedule, in: db)
        try insertIntake(
            SQLiteMedicationIntake(
                medicationID: medication.id,
                entryID: entry.id,
                amount: 1, unit: "tablet", timestamp: .now
            ),
            in: db
        )
        try db.execute(
            sql: """
                INSERT INTO sqLiteCollaboratorNote
                (id, journalID, entryID, authorName, text, timestamp)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                UUID().uuidString.lowercased(),
                journal.id.uuidString.lowercased(),
                entry.id.uuidString.lowercased(),
                "Test Author", "Test note",
                ISO8601DateFormatter().string(from: .now)
            ]
        )
    }
}

private func assertAllChildrenDeleted(
    database: any DatabaseReader
) throws {
    let tables = [
        "sqLiteSymptomEntry", "sqLiteMedication",
        "sqLiteMedicationIntake", "sqLiteMedicationSchedule",
        "sqLiteCollaboratorNote"
    ]
    for table in tables {
        let count = try database.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM \(table)"
            ) ?? 0
        }
        #expect(
            count == 0,
            "Expected \(table) empty after journal delete, got \(count) rows"
        )
    }
}

// MARK: - Helper Functions

private func makeWeekdaySchedule(
    for medication: SQLiteMedication,
    hour: Int16,
    minute: Int16
) -> SQLiteMedicationSchedule {
    SQLiteMedicationSchedule(
        medicationID: medication.id,
        label: "Morning",
        amount: 1,
        unit: "tablet",
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: MedicationWeekday.mask(
            for: [
                .monday, .tuesday, .wednesday,
                .thursday, .friday
            ]
        ),
        hour: hour,
        minute: minute,
        isActive: true,
        sortOrder: 0
    )
}

private func makeAllDaysSchedule(
    for medication: SQLiteMedication,
    label: String,
    hour: Int16,
    minute: Int16
) -> SQLiteMedicationSchedule {
    SQLiteMedicationSchedule(
        medicationID: medication.id,
        label: label,
        amount: 1,
        unit: "tablet",
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: MedicationWeekday.mask(
            for: MedicationWeekday.allCases
        ),
        hour: hour,
        minute: minute,
        isActive: true,
        sortOrder: 0
    )
}

private func makeLinkedIntake(
    medication: SQLiteMedication,
    entry: SQLiteSymptomEntry,
    schedule: SQLiteMedicationSchedule
) -> SQLiteMedicationIntake {
    SQLiteMedicationIntake(
        id: UUID(),
        medicationID: medication.id,
        entryID: entry.id,
        scheduleID: schedule.id,
        amount: 1, unit: "tablet",
        timestamp: Date(timeIntervalSince1970: 1_726_000_000),
        scheduledDate: Date(timeIntervalSince1970: 1_725_936_000),
        origin: "scheduled",
        notes: "Logged from quick checkmark"
    )
}

private func assertCascadeDeleted(
    medicationID: UUID, database: DatabaseWriter
) throws {
    let args: StatementArguments = [medicationID.uuidString]
    let scheduleCount = try database.read { db in
        try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM sqLiteMedicationSchedule
            WHERE medicationID = ?
            """, arguments: args) ?? 0
    }
    #expect(scheduleCount == 0)
    let intakeCount = try database.read { db in
        try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM sqLiteMedicationIntake
            WHERE medicationID = ?
            """, arguments: args) ?? 0
    }
    #expect(intakeCount == 0)
}

private func assertIntakeLinkagePreserved(
    reloaded: SQLiteMedicationIntake?,
    original: SQLiteMedicationIntake,
    edited: SQLiteMedicationIntake
) {
    #expect(reloaded?.id == original.id)
    #expect(reloaded?.scheduleID == original.scheduleID)
    #expect(reloaded?.entryID == original.entryID)
    #expect(
        reloaded?.scheduledDate == original.scheduledDate
    )
    #expect(reloaded?.origin == original.origin)
    #expect(reloaded?.amount == edited.amount)
    #expect(reloaded?.timestamp == edited.timestamp)
    #expect(reloaded?.notes == edited.notes)
}
