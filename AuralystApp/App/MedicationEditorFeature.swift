import ComposableArchitecture
import Dependencies
import Foundation
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
                guard let medicationID = state.medicationID,
                      !state.isLoading else { return .none }
                state.isLoading = true
                return .run { send in
                    await send(
                        .loadResponse(
                            TaskResult {
                                try database.read { db in
                                    try loadMedication(
                                        medicationID, from: db
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
                    draft.time = Calendar.current.date(
                        bySettingHour: 20, minute: 0, second: 0, of: Date()
                    ) ?? draft.time
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
                                        params: MedicationUpsertParams(
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
                                    try SQLiteMedicationSchedule
                                        .where { $0.medicationID.eq(medicationID) }
                                        .delete()
                                        .execute(db)
                                    try SQLiteMedicationIntake
                                        .where { $0.medicationID.eq(medicationID) }
                                        .delete()
                                        .execute(db)
                                    try SQLiteMedication.find(medicationID).delete().execute(db)
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
