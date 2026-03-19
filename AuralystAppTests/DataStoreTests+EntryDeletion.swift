import Foundation
import Testing
import Dependencies
import GRDB
@preconcurrency import SQLiteData
@testable import AuralystApp

// MARK: - Entry Deletion & Insert Helpers Tests

extension DataStoreSuite {
    @MainActor
    @Test("Deleting a symptom entry detaches linked records")
    func deleteSymptomEntryDetachesLinkedRecords() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 6, note: "Headache"
        )
        let medication = store.createMedication(
            for: journal, name: "Ibuprofen",
            defaultAmount: 2, defaultUnit: "pill"
        )

        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            entryID: entry.id,
            amount: 2,
            unit: "pill",
            timestamp: .now
        )
        let note = SQLiteCollaboratorNote(
            journalID: journal.id,
            entryID: entry.id,
            authorName: "Alex",
            text: "Follow up"
        )

        try insertLinkedRecords(
            database: database,
            journal: journal,
            entry: entry,
            intake: intake,
            note: note
        )

        try store.deleteSymptomEntry(id: entry.id)
        #expect(
            store.fetchSymptomEntry(id: entry.id) == nil
        )

        let intakeLinked = try fetchLinkedCount(
            database: database,
            table: "sqLiteMedicationIntake",
            id: intake.id
        )
        #expect(intakeLinked == 0)

        let noteLinked = try fetchLinkedCount(
            database: database,
            table: "sqLiteCollaboratorNote",
            id: note.id
        )
        #expect(noteLinked == 0)
    }

    @MainActor
    @Test("Insert helpers persist linkage metadata")
    func insertHelpersPersistLinkageMetadata() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 2
        )
        let medication = store.createMedication(
            for: journal, name: "Vitamin D",
            defaultAmount: 1, defaultUnit: "capsule"
        )

        let schedule = makeDetailedSchedule(
            for: medication
        )
        try insertSchedule(schedule, database: database)

        let intake = makeDetailedIntake(
            medication: medication,
            entry: entry,
            schedule: schedule
        )
        try insertIntake(intake, database: database)

        let result = try fetchReloadedRows(
            database: database,
            scheduleID: schedule.id,
            intakeID: intake.id
        )

        assertScheduleFields(
            result.schedule, expected: schedule
        )
        assertIntakeFields(
            result.intake,
            expectedEntryID: entry.id,
            expectedScheduleID: schedule.id,
            expectedOrigin: intake.origin
        )
    }
}

// MARK: - Helpers

private func insertLinkedRecords(
    database: any DatabaseWriter,
    journal: SQLiteJournal,
    entry: SQLiteSymptomEntry,
    intake: SQLiteMedicationIntake,
    note: SQLiteCollaboratorNote
) throws {
    let ts = ISO8601DateFormatter().string(
        from: note.timestamp
    )
    try database.write { db in
        try insertIntake(intake, in: db)
        try db.execute(
            sql: """
                INSERT INTO sqLiteCollaboratorNote
                (id, journalID, entryID,
                 authorName, text, timestamp)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                note.id.uuidString,
                journal.id.uuidString,
                entry.id.uuidString,
                note.authorName,
                note.text,
                ts
            ]
        )
    }
}

private func fetchLinkedCount(
    database: any DatabaseReader,
    table: String,
    id: UUID
) throws -> Int {
    try database.read { db in
        try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM \(table)
                WHERE lower(id) = lower(?)
                AND entryID IS NOT NULL
                """,
            arguments: [id.uuidString]
        ) ?? 0
    }
}

private func makeDetailedSchedule(
    for medication: SQLiteMedication
) -> SQLiteMedicationSchedule {
    SQLiteMedicationSchedule(
        medicationID: medication.id,
        label: "Breakfast",
        amount: 1,
        unit: "capsule",
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: MedicationWeekday.mask(
            for: MedicationWeekday.allCases
        ),
        hour: 8,
        minute: 15,
        timeZoneIdentifier: "America/New_York",
        startDate: Date(
            timeIntervalSince1970: 1_726_500_000
        ),
        isActive: true,
        sortOrder: 2
    )
}

private func makeDetailedIntake(
    medication: SQLiteMedication,
    entry: SQLiteSymptomEntry,
    schedule: SQLiteMedicationSchedule
) -> SQLiteMedicationIntake {
    SQLiteMedicationIntake(
        id: UUID(),
        medicationID: medication.id,
        entryID: entry.id,
        scheduleID: schedule.id,
        amount: 1,
        unit: "capsule",
        timestamp: Date(
            timeIntervalSince1970: 1_726_500_600
        ),
        scheduledDate: Date(
            timeIntervalSince1970: 1_726_500_000
        ),
        origin: "scheduled",
        notes: "Morning dose"
    )
}

private struct ReloadedRows {
    let schedule: DeletionScheduleRow?
    let intake: DeletionIntakeRow?
}

private func fetchReloadedRows(
    database: any DatabaseReader,
    scheduleID: UUID,
    intakeID: UUID
) throws -> ReloadedRows {
    try database.read { db in
        let scheduleRows = try DeletionScheduleRow
            .fetchAll(db)
        let intakeRows = try DeletionIntakeRow
            .fetchAll(db)
        let scheduleRow = scheduleRows.first {
            $0.id.lowercased()
                == scheduleID.uuidString.lowercased()
        }
        let intakeRow = intakeRows.first {
            $0.id.lowercased()
                == intakeID.uuidString.lowercased()
        }
        return ReloadedRows(
            schedule: scheduleRow, intake: intakeRow
        )
    }
}

private func assertScheduleFields(
    _ row: DeletionScheduleRow?,
    expected: SQLiteMedicationSchedule
) {
    #expect(row?.label == expected.label)
    #expect(row?.hour == expected.hour)
    #expect(row?.minute == expected.minute)
    #expect(
        row?.timeZoneIdentifier
            == expected.timeZoneIdentifier
    )
    #expect(row?.startDate != nil)
}

private func assertIntakeFields(
    _ row: DeletionIntakeRow?,
    expectedEntryID: UUID,
    expectedScheduleID: UUID,
    expectedOrigin: String?
) {
    #expect(
        row?.entryID?.lowercased()
            == expectedEntryID.uuidString.lowercased()
    )
    #expect(
        row?.scheduleID?.lowercased()
            == expectedScheduleID.uuidString.lowercased()
    )
    #expect(row?.origin == expectedOrigin)
    #expect(row?.scheduledDate != nil)
}

// MARK: - Row Types

private struct DeletionScheduleRow:
    FetchableRecord, TableRecord {
    static let databaseTableName = "sqLiteMedicationSchedule"

    let id: String
    let label: String?
    let hour: Int16?
    let minute: Int16?
    let timeZoneIdentifier: String?
    let startDate: String?

    init(row: Row) throws {
        id = row["id"]
        label = row["label"]
        hour = row["hour"]
        minute = row["minute"]
        timeZoneIdentifier = row["timeZoneIdentifier"]
        startDate = row["startDate"]
    }
}

private struct DeletionIntakeRow:
    FetchableRecord, TableRecord {
    static let databaseTableName = "sqLiteMedicationIntake"

    let id: String
    let entryID: String?
    let scheduleID: String?
    let origin: String?
    let scheduledDate: String?

    init(row: Row) throws {
        id = row["id"]
        entryID = row["entryID"]
        scheduleID = row["scheduleID"]
        origin = row["origin"]
        scheduledDate = row["scheduledDate"]
    }
}
