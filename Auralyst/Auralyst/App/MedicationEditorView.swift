import Foundation
import SQLiteData
import StructuredQueries
import SwiftUI
import Dependencies

struct MedicationEditorView: View {
    let journalID: UUID
    let medicationID: UUID?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var defaultAmount: String = ""
    @State private var defaultUnit: String = ""
    @State private var isAsNeeded: Bool = false
    @State private var useCase: String = ""
    @State private var notes: String = ""

    // Schedule editing
    struct ScheduleDraft: Identifiable, Equatable {
        let id: UUID = UUID() // UI identity
        var existingID: UUID? // DB identity when editing
        var label: String = ""
        var amount: String = "" // keep as string for text field
        var unit: String = ""
        var time: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        var sortOrder: Int16 = 0
    }

    @State private var scheduleDrafts: [ScheduleDraft] = []

    init(journalID: UUID, medicationID: UUID? = nil) {
        self.journalID = journalID
        self.medicationID = medicationID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication Details") {
                    TextField("Name", text: $name)
                    Toggle("As Needed", isOn: $isAsNeeded)
                        .toggleStyle(.switch)
                    TextField("Default Amount", text: $defaultAmount)
                        .keyboardType(.decimalPad)
                    TextField("Unit (e.g., mg, ml)", text: $defaultUnit)
                    TextField("Use Case (e.g., pain, sleep)", text: $useCase)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if !isAsNeeded {
                    Section("Schedule") {
                        if scheduleDrafts.isEmpty {
                            Text("Add one or more daily doses with time and amount.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(scheduleDrafts.indices, id: \.self) { idx in
                            let binding = Binding(get: { scheduleDrafts[idx] }, set: { scheduleDrafts[idx] = $0 })
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Label (e.g., Morning)", text: binding.label)
                                        .textInputAutocapitalization(.words)

                                    Spacer()

                                    Button(role: .destructive) {
                                        scheduleDrafts.remove(at: idx)
                                        renumberSortOrders()
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }

                                HStack {
                                    TextField("Amount", text: binding.amount)
                                        .keyboardType(.decimalPad)
                                        .frame(maxWidth: 120)
                                    TextField("Unit", text: binding.unit)
                                        .frame(maxWidth: 80)
                                    Spacer()
                                    DatePicker("Time", selection: binding.time, displayedComponents: [.hourAndMinute])
                                        .labelsHidden()
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Button {
                            addDraftDose()
                        } label: {
                            Label("Add Dose", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle(medicationID == nil ? "Add Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear { loadIfNeeded() }
        }
    }

    private func addDraftDose() {
        var draft = ScheduleDraft()
        draft.sortOrder = Int16(scheduleDrafts.count)
        if scheduleDrafts.isEmpty {
            draft.label = "Morning"
        } else if scheduleDrafts.count == 1 {
            draft.label = "Evening"
            draft.time = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? draft.time
        }
        scheduleDrafts.append(draft)
    }

    private func renumberSortOrders() {
        for i in scheduleDrafts.indices { scheduleDrafts[i].sortOrder = Int16(i) }
    }

    private func loadIfNeeded() {
        @Dependency(\.defaultDatabase) var database

        // Load existing medication data if editing
        guard let medicationID else { return }
        do {
            if let med = try database.read({ db in try SQLiteMedication.find(medicationID).fetchOne(db) }) {
                name = med.name
                if let amt = med.defaultAmount {
                    defaultAmount = (floor(amt) == amt) ? String(Int(amt)) : String(amt)
                } else {
                    defaultAmount = ""
                }
                defaultUnit = med.defaultUnit ?? ""
                isAsNeeded = med.isAsNeeded ?? false
                useCase = med.useCase ?? ""
                notes = med.notes ?? ""
            }

            // Load schedules for this medication when not as-needed
            let schedules = try database.read { db in
                try SQLiteMedicationSchedule
                    .where { $0.medicationID == medicationID }
                    .fetchAll(db)
            }

            scheduleDrafts = schedules
                .sorted { (lhs, rhs) in
                    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                    let lh = Int(lhs.hour ?? 0), rh = Int(rhs.hour ?? 0)
                    if lh != rh { return lh < rh }
                    return Int(lhs.minute ?? 0) < Int(rhs.minute ?? 0)
                }
                .enumerated()
                .map { idx, s in
                    var comps = DateComponents()
                    comps.hour = Int(s.hour ?? 8)
                    comps.minute = Int(s.minute ?? 0)
                    let time = Calendar.current.date(from: comps) ?? Date()
                    return ScheduleDraft(
                        existingID: s.id,
                        label: s.label ?? "",
                        amount: s.amount.map { (floor($0) == $0) ? String(Int($0)) : String($0) } ?? "",
                        unit: s.unit ?? "",
                        time: time,
                        sortOrder: Int16(idx)
                    )
                }
        } catch {
            print("Failed to load medication/schedules: \(error)")
        }
    }

    private func save() {
        @Dependency(\.defaultDatabase) var database

        let amount = Double(defaultAmount)
        let unit = defaultUnit.isEmpty ? nil : defaultUnit
        let notesParam = notes.isEmpty ? nil : notes
        let useCaseParam = useCase.isEmpty ? nil : useCase

        do {
            if let medID = medicationID {
                guard let existing = try database.read({ db in
                    try SQLiteMedication.find(medID).fetchOne(db)
                }) else {
                    assertionFailure("Attempting to update missing medication")
                    return
                }

                let updatedMedication = SQLiteMedication(
                    id: existing.id,
                    journalID: existing.journalID,
                    name: name,
                    defaultAmount: amount,
                    defaultUnit: unit,
                    isAsNeeded: isAsNeeded,
                    useCase: useCaseParam,
                    notes: notesParam,
                    createdAt: existing.createdAt,
                    updatedAt: Date()
                )

                try database.write { db in
                    try SQLiteMedication.update(updatedMedication).execute(db)
                }

                // Persist schedules
                try persistSchedules(for: medID)
            } else {
                // Create new medication (typed insert so we own the id)
                let med = SQLiteMedication(
                    journalID: journalID,
                    name: name,
                    defaultAmount: amount,
                    defaultUnit: unit,
                    isAsNeeded: isAsNeeded,
                    useCase: useCaseParam,
                    notes: notesParam
                )

                try database.write { db in
                    try SQLiteMedication.insert { med }.execute(db)
                }

                // Persist schedules for new medication
                try persistSchedules(for: med.id)
            }
        } catch {
            print("Failed to save medication: \(error)")
        }

        NotificationCenter.default.post(name: .medicationsDidChange, object: nil)
        NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)

        dismiss()
    }

    private func persistSchedules(for medicationID: UUID) throws {
        @Dependency(\.defaultDatabase) var database

        try database.write { db in
            // If set as as-needed, remove all schedules
            if isAsNeeded {
                try SQLiteMedicationSchedule
                    .where { $0.medicationID == medicationID }
                    .delete()
                    .execute(db)
                return
            }

            // Fetch existing schedules
            let existing = try SQLiteMedicationSchedule
                .where { $0.medicationID == medicationID }
                .fetchAll(db)
            let existingByID: [UUID: SQLiteMedicationSchedule] = .init(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            // Update/Insert drafts
            var keptIDs: Set<UUID> = []
            let maskAllDays: Int16 = MedicationWeekday.mask(for: MedicationWeekday.allCases)
            let tzID = TimeZone.current.identifier

            for (index, draft) in scheduleDrafts.enumerated() {
                let amountValue: Double? = Double(draft.amount)
                let unitValue: String? = draft.unit.isEmpty ? nil : draft.unit
                let comps = Calendar.current.dateComponents([.hour, .minute], from: draft.time)
                let hour: Int16? = comps.hour.flatMap { Int16($0) }
                let minute: Int16? = comps.minute.flatMap { Int16($0) }
                let labelValue: String? = draft.label.isEmpty ? nil : draft.label
                let sortOrder: Int16 = Int16(index)

                if let existingID = draft.existingID, let existingSchedule = existingByID[existingID] {
                    keptIDs.insert(existingID)
                    let updatedSchedule = SQLiteMedicationSchedule(
                        id: existingID,
                        medicationID: medicationID,
                        label: labelValue,
                        amount: amountValue,
                        unit: unitValue,
                        cadence: "daily",
                        interval: 1,
                        daysOfWeekMask: maskAllDays,
                        hour: hour,
                        minute: minute,
                        timeZoneIdentifier: tzID,
                        startDate: existingSchedule.startDate,
                        isActive: true,
                        sortOrder: sortOrder
                    )
                    try SQLiteMedicationSchedule.update(updatedSchedule).execute(db)
                } else {
                    let schedule = SQLiteMedicationSchedule(
                        medicationID: medicationID,
                        label: labelValue,
                        amount: amountValue,
                        unit: unitValue,
                        cadence: "daily",
                        interval: 1,
                        daysOfWeekMask: maskAllDays,
                        hour: hour,
                        minute: minute,
                        timeZoneIdentifier: tzID,
                        isActive: true,
                        sortOrder: sortOrder
                    )
                    try SQLiteMedicationSchedule.insert { schedule }.execute(db)
                }
            }

            // Delete removed schedules
            let toDelete = existing.compactMap { keptIDs.contains($0.id) ? nil : $0.id }
            for id in toDelete {
                try SQLiteMedicationSchedule.find(id).delete().execute(db)
            }
        }
    }
}

#Preview {
    withPreviewDataStore { _ in
        MedicationEditorView(journalID: UUID())
    }
}
