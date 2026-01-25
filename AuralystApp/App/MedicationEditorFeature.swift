import ComposableArchitecture
import Dependencies
import Foundation
import GRDB
import StructuredQueries
@preconcurrency import SQLiteData

@Reducer
struct MedicationEditorFeature {
    @ObservableState
    struct State: Equatable {
        var journalID: UUID
        var medicationID: UUID?
        var name: String = ""
        var defaultAmount: String = ""
        var defaultUnit: String = ""
        var isAsNeeded: Bool = false
        var useCase: String = ""
        var notes: String = ""
        var scheduleDrafts: [ScheduleDraft] = []
        var isLoading = false
        var isSaving = false
        var showDeleteConfirmation = false
        var errorMessage: String?
        var didFinish = false

        init(journalID: UUID, medicationID: UUID? = nil) {
            self.journalID = journalID
            self.medicationID = medicationID
        }
    }

    struct ScheduleDraft: Identifiable, Equatable {
        let id: UUID
        var existingID: UUID?
        var label: String
        var amount: String
        var unit: String
        var time: Date
        var sortOrder: Int16

        init(
            existingID: UUID? = nil,
            label: String = "",
            amount: String = "",
            unit: String = "",
            time: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date(),
            sortOrder: Int16 = 0
        ) {
            self.id = UUID()
            self.existingID = existingID
            self.label = label
            self.amount = amount
            self.unit = unit
            self.time = time
            self.sortOrder = sortOrder
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case loadResponse(TaskResult<LoadedMedication?>)
        case addDoseTapped
        case removeDose(UUID)
        case saveTapped
        case saveResponse(TaskResult<Void>)
        case deleteTapped
        case deleteConfirmed
        case deleteResponse(TaskResult<Void>)
        case clearError
        case clearDidFinish
    }

    struct LoadedMedication: Equatable {
        var name: String
        var defaultAmount: Double?
        var defaultUnit: String?
        var isAsNeeded: Bool
        var useCase: String?
        var notes: String?
        var drafts: [ScheduleDraft]
    }

    @Dependency(\.defaultDatabase) private var database

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .task:
                guard let medicationID = state.medicationID, !state.isLoading else { return .none }
                state.isLoading = true
                return .run { send in
                    await send(
                        .loadResponse(
                            TaskResult {
                                try database.read { db -> LoadedMedication? in
                                    guard let row = try Row.fetchOne(
                                        db,
                                        sql: """
                                            SELECT name, defaultAmount, defaultUnit, isAsNeeded, useCase, notes
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
                                            SELECT id, label, amount, unit, hour, minute, sortOrder
                                            FROM sqLiteMedicationSchedule
                                            WHERE medicationID = ?
                                            ORDER BY sortOrder ASC, hour ASC, minute ASC
                                        """,
                                        arguments: [medicationID]
                                    )

                                    let drafts: [ScheduleDraft] = scheduleRows.enumerated().map { index, row in
                                        let scheduleID: UUID = row["id"]
                                        let label: String = row["label"] ?? ""
                                        let amount: Double? = row["amount"]
                                        let unit: String = row["unit"] ?? ""
                                        let hour: Int = Int(row["hour"] as Int16? ?? 8)
                                        let minute: Int = Int(row["minute"] as Int16? ?? 0)
                                        var components = DateComponents()
                                        components.hour = hour
                                        components.minute = minute
                                        let time = Calendar.current.date(from: components) ?? Date()
                                        return ScheduleDraft(
                                            existingID: scheduleID,
                                            label: label,
                                            amount: amount.map { (floor($0) == $0) ? String(Int($0)) : String($0) } ?? "",
                                            unit: unit,
                                            time: time,
                                            sortOrder: Int16(index)
                                        )
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
                            }
                        )
                    )
                }

            case .loadResponse(.success(let loaded)):
                state.isLoading = false
                guard let loaded else { return .none }
                state.name = loaded.name
                if let amount = loaded.defaultAmount {
                    state.defaultAmount = (floor(amount) == amount) ? String(Int(amount)) : String(amount)
                } else {
                    state.defaultAmount = ""
                }
                state.defaultUnit = loaded.defaultUnit ?? ""
                state.isAsNeeded = loaded.isAsNeeded
                state.useCase = loaded.useCase ?? ""
                state.notes = loaded.notes ?? ""
                state.scheduleDrafts = loaded.drafts
                return .none

            case .loadResponse(.failure(let error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case .addDoseTapped:
                var draft = ScheduleDraft()
                draft.sortOrder = Int16(state.scheduleDrafts.count)
                if state.scheduleDrafts.isEmpty {
                    draft.label = "Morning"
                } else if state.scheduleDrafts.count == 1 {
                    draft.label = "Evening"
                    draft.time = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? draft.time
                }
                state.scheduleDrafts.append(draft)
                return .none

            case .removeDose(let id):
                state.scheduleDrafts.removeAll { $0.id == id }
                renumberSortOrders(state: &state)
                return .none

            case .saveTapped:
                guard !state.name.isEmpty, !state.isSaving else { return .none }
                state.isSaving = true
                let snapshot = state
                return .run { send in
                    await send(
                        .saveResponse(
                            TaskResult {
                                try database.write { db in
                                    let amountValue = Double(snapshot.defaultAmount)
                                    let unitValue = snapshot.defaultUnit.isEmpty ? nil : snapshot.defaultUnit
                                    let notesValue = snapshot.notes.isEmpty ? nil : snapshot.notes
                                    let useCaseValue = snapshot.useCase.isEmpty ? nil : snapshot.useCase
                                    let now = Date()

                                    let medicationID = try upsertMedication(
                                        in: db,
                                        journalID: snapshot.journalID,
                                        medicationID: snapshot.medicationID,
                                        name: snapshot.name,
                                        amount: amountValue,
                                        unit: unitValue,
                                        isAsNeeded: snapshot.isAsNeeded,
                                        useCase: useCaseValue,
                                        notes: notesValue,
                                        timestamp: now
                                    )

                                    var drafts = snapshot.scheduleDrafts
                                    try syncSchedules(in: db, medicationID: medicationID, drafts: &drafts)

                                    NotificationCenter.default.post(name: .medicationsDidChange, object: nil)
                                }
                            }
                        )
                    )
                }

            case .saveResponse(.success):
                state.isSaving = false
                state.didFinish = true
                return .none

            case .saveResponse(.failure(let error)):
                state.isSaving = false
                state.errorMessage = error.localizedDescription
                return .none

            case .deleteTapped:
                state.showDeleteConfirmation = true
                return .none

            case .deleteConfirmed:
                guard let medicationID = state.medicationID else { return .none }
                return .run { send in
                    await send(
                        .deleteResponse(
                            TaskResult {
                                try database.write { db in
                                    try db.execute(sql: "DELETE FROM sqLiteMedicationSchedule WHERE medicationID = ?", arguments: [medicationID])
                                    try db.execute(sql: "DELETE FROM sqLiteMedicationIntake WHERE medicationID = ?", arguments: [medicationID])
                                    try db.execute(sql: "DELETE FROM sqLiteMedication WHERE id = ?", arguments: [medicationID])
                                }
                                NotificationCenter.default.post(name: .medicationsDidChange, object: nil)
                            }
                        )
                    )
                }

            case .deleteResponse(.success):
                state.showDeleteConfirmation = false
                state.didFinish = true
                return .none

            case .deleteResponse(.failure(let error)):
                state.showDeleteConfirmation = false
                state.errorMessage = error.localizedDescription
                return .none

            case .clearError:
                state.errorMessage = nil
                return .none

            case .clearDidFinish:
                state.didFinish = false
                return .none
            }
        }
    }
}

private func renumberSortOrders(state: inout MedicationEditorFeature.State) {
    for index in state.scheduleDrafts.indices {
        state.scheduleDrafts[index].sortOrder = Int16(index)
    }
}

private func upsertMedication(
    in db: Database,
    journalID: UUID,
    medicationID: UUID?,
    name: String,
    amount: Double?,
    unit: String?,
    isAsNeeded: Bool,
    useCase: String?,
    notes: String?,
    timestamp: Date
) throws -> UUID {
    if let medID = medicationID {
        try db.execute(sql: """
            UPDATE sqLiteMedication
            SET name = ?,
                defaultAmount = ?,
                defaultUnit = ?,
                isAsNeeded = ?,
                useCase = ?,
                notes = ?,
                updatedAt = ?
            WHERE id = ?
        """, arguments: [name, amount, unit, isAsNeeded, useCase, notes, timestamp, medID])
        return medID
    } else {
        let medID = UUID()
        try db.execute(sql: """
            INSERT INTO sqLiteMedication
                (id, journalID, name, defaultAmount, defaultUnit, isAsNeeded, useCase, notes, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [medID, journalID, name, amount, unit, isAsNeeded, useCase, notes, timestamp, timestamp])
        return medID
    }
}

private func syncSchedules(in db: Database, medicationID: UUID, drafts: inout [MedicationEditorFeature.ScheduleDraft]) throws {
    let existingIDs = Set(try UUID.fetchAll(db, sql: "SELECT id FROM sqLiteMedicationSchedule WHERE medicationID = ?", arguments: [medicationID]))
    var retainedIDs = Set<UUID>()

    for index in drafts.indices {
        let draft = drafts[index]
        let scheduleID = draft.existingID ?? UUID()
        drafts[index].existingID = scheduleID
        retainedIDs.insert(scheduleID)

        let amount = Double(draft.amount)
        let unit = draft.unit.isEmpty ? nil : draft.unit
        let hour = Int16(Calendar.current.component(.hour, from: draft.time))
        let minute = Int16(Calendar.current.component(.minute, from: draft.time))

        try db.execute(sql: """
            INSERT INTO sqLiteMedicationSchedule
                (id, medicationID, label, amount, unit, hour, minute, sortOrder)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                label = excluded.label,
                amount = excluded.amount,
                unit = excluded.unit,
                hour = excluded.hour,
                minute = excluded.minute,
                sortOrder = excluded.sortOrder
        """, arguments: [scheduleID, medicationID, draft.label, amount, unit, hour, minute, Int16(index)])
    }

    let idsToDelete = existingIDs.subtracting(retainedIDs)
    if !idsToDelete.isEmpty {
        let placeholders = idsToDelete.map { _ in "?" }.joined(separator: ",")
        try db.execute(sql: "DELETE FROM sqLiteMedicationSchedule WHERE id IN (\(placeholders))", arguments: StatementArguments(Array(idsToDelete)))
    }
}
