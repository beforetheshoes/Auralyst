import Foundation
import GRDB
@preconcurrency import SQLiteData

typealias ScheduleDraft = MedicationEditorFeature.ScheduleDraft
typealias LoadedMedication = MedicationEditorFeature.LoadedMedication

func loadMedication(
    _ medicationID: UUID,
    from db: Database
) throws -> LoadedMedication? {
    guard let row = try Row.fetchOne(
        db,
        sql: """
            SELECT name, defaultAmount, defaultUnit, \
            isAsNeeded, useCase, notes
            FROM sqLiteMedication
            WHERE id = ?
        """,
        arguments: [medicationID]
    ) else {
        return nil
    }

    let name: String = row["name"]
    let defaultAmount: Double? = row["defaultAmount"]
    let defaultUnit: String? = row["defaultUnit"]
    let isAsNeeded: Bool = (row["isAsNeeded"] as Bool?) ?? false
    let useCase: String? = row["useCase"]
    let notes: String? = row["notes"]

    let scheduleRows = try Row.fetchAll(
        db,
        sql: """
            SELECT id, label, amount, unit, \
            hour, minute, sortOrder
            FROM sqLiteMedicationSchedule
            WHERE medicationID = ?
            ORDER BY sortOrder ASC, hour ASC, minute ASC
        """,
        arguments: [medicationID]
    )

    let drafts = scheduleRows.enumerated().map { index, row in
        buildScheduleDraft(from: row, index: index)
    }

    return LoadedMedication(
        name: name,
        defaultAmount: defaultAmount,
        defaultUnit: defaultUnit,
        isAsNeeded: isAsNeeded,
        useCase: useCase,
        notes: notes,
        drafts: drafts
    )
}

private func buildScheduleDraft(
    from row: Row, index: Int
) -> ScheduleDraft {
    let scheduleID: UUID = row["id"]
    let label: String = row["label"] ?? ""
    let amount: Double? = row["amount"]
    let unit: String = row["unit"] ?? ""
    let hour = Int(row["hour"] as Int16? ?? 8)
    let minute = Int(row["minute"] as Int16? ?? 0)
    var components = DateComponents()
    components.hour = hour
    components.minute = minute
    let time = Calendar.current.date(
        from: components
    ) ?? Date()
    return ScheduleDraft(
        existingID: scheduleID,
        label: label,
        amount: amount.map {
            (floor($0) == $0)
                ? String(Int($0)) : String($0)
        } ?? "",
        unit: unit,
        time: time,
        sortOrder: Int16(index)
    )
}

func renumberSortOrders(
    state: inout MedicationEditorFeature.State
) {
    for index in state.scheduleDrafts.indices {
        state.scheduleDrafts[index].sortOrder = Int16(index)
    }
}

struct MedicationUpsertParams {
    let journalID: UUID
    let medicationID: UUID?
    let name: String
    let amount: Double?
    let unit: String?
    let isAsNeeded: Bool
    let useCase: String?
    let notes: String?
    let timestamp: Date
}

func upsertMedication(
    in db: Database,
    params: MedicationUpsertParams
) throws -> UUID {
    if let medID = params.medicationID {
        return try upsertExistingMedication(
            in: db, medID: medID, params: params
        )
    } else {
        return try insertNewMedication(in: db, params: params)
    }
}

private func upsertExistingMedication(
    in db: Database,
    medID: UUID,
    params: MedicationUpsertParams
) throws -> UUID {
    if let existing = try SQLiteMedication.find(medID).fetchOne(db) {
        let updated = buildMedication(
            id: medID, journalID: existing.journalID,
            params: params,
            createdAt: existing.createdAt
        )
        try SQLiteMedication.update(updated).execute(db)
    } else {
        let newMed = buildMedication(
            id: medID, journalID: params.journalID,
            params: params,
            createdAt: params.timestamp
        )
        try SQLiteMedication.insert { newMed }.execute(db)
    }
    return medID
}

private func insertNewMedication(
    in db: Database,
    params: MedicationUpsertParams
) throws -> UUID {
    let medID = UUID()
    let medication = buildMedication(
        id: medID, journalID: params.journalID,
        params: params,
        createdAt: params.timestamp
    )
    try SQLiteMedication.insert { medication }.execute(db)
    return medID
}

private func buildMedication(
    id: UUID,
    journalID: UUID,
    params: MedicationUpsertParams,
    createdAt: Date
) -> SQLiteMedication {
    SQLiteMedication(
        id: id,
        journalID: journalID,
        name: params.name,
        defaultAmount: params.amount,
        defaultUnit: params.unit,
        isAsNeeded: params.isAsNeeded,
        useCase: params.useCase,
        notes: params.notes,
        createdAt: createdAt,
        updatedAt: params.timestamp
    )
}

func syncSchedules(
    in db: Database,
    medicationID: UUID,
    drafts: inout [MedicationEditorFeature.ScheduleDraft]
) throws {
    let existingSchedules = try SQLiteMedicationSchedule
        .where { $0.medicationID.eq(medicationID) }
        .fetchAll(db)
    let existingIDs = Set(existingSchedules.map(\.id))
    let existingByID = Dictionary(
        uniqueKeysWithValues: existingSchedules.map { ($0.id, $0) }
    )
    var retainedIDs = Set<UUID>()

    for index in drafts.indices {
        let scheduleID = drafts[index].existingID ?? UUID()
        drafts[index].existingID = scheduleID
        retainedIDs.insert(scheduleID)

        let context = ScheduleUpsertContext(
            scheduleID: scheduleID,
            medicationID: medicationID,
            sortOrder: Int16(index),
            existing: existingByID[scheduleID]
        )
        try upsertScheduleDraft(
            drafts[index],
            context: context,
            in: db
        )
    }

    for id in existingIDs.subtracting(retainedIDs) {
        try SQLiteMedicationSchedule
            .find(id).delete().execute(db)
    }
}

struct ScheduleUpsertContext {
    let scheduleID: UUID
    let medicationID: UUID
    let sortOrder: Int16
    let existing: SQLiteMedicationSchedule?
}

private func upsertScheduleDraft(
    _ draft: MedicationEditorFeature.ScheduleDraft,
    context: ScheduleUpsertContext,
    in db: Database
) throws {
    let amount = Double(draft.amount)
    let unit = draft.unit.isEmpty ? nil : draft.unit
    let cal = Calendar.current
    let hour = Int16(cal.component(.hour, from: draft.time))
    let minute = Int16(cal.component(.minute, from: draft.time))
    let scheduleID = context.scheduleID
    let medicationID = context.medicationID
    let sortOrder = context.sortOrder
    let existing = context.existing

    if let existing {
        let updated = SQLiteMedicationSchedule(
            id: scheduleID,
            medicationID: medicationID,
            label: draft.label,
            amount: amount,
            unit: unit,
            cadence: existing.cadence,
            interval: existing.interval,
            daysOfWeekMask: existing.daysOfWeekMask,
            hour: hour,
            minute: minute,
            timeZoneIdentifier: existing.timeZoneIdentifier,
            startDate: existing.startDate,
            isActive: existing.isActive,
            sortOrder: sortOrder
        )
        try SQLiteMedicationSchedule.update(updated).execute(db)
    } else {
        let schedule = SQLiteMedicationSchedule(
            id: scheduleID,
            medicationID: medicationID,
            label: draft.label,
            amount: amount,
            unit: unit,
            hour: hour,
            minute: minute,
            sortOrder: sortOrder
        )
        try SQLiteMedicationSchedule
            .insert { schedule }.execute(db)
    }
}
