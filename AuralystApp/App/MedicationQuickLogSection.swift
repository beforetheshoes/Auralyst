import Foundation
@preconcurrency import SQLiteData
import SwiftUI
import Dependencies
import ComposableArchitecture
import GRDB

struct MedicationQuickLogSection: View {
    let store: StoreOf<MedicationQuickLogFeature>
    let manageAction: () -> Void
    let loggingError: String?
    let presentAsNeeded: (SQLiteMedication, Date) -> Void

    var body: some View {
        Section("Quick Medication Log") {
            DatePicker(
                "Log Date",
                selection: Binding(
                    get: { store.selectedDate },
                    set: { store.send(.selectedDateChanged($0)) }
                ),
                displayedComponents: [.date]
            )

            if scheduledMedications(snapshot: store.snapshot).isEmpty {
                Text("No scheduled medications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scheduledMedications(snapshot: store.snapshot)) { med in
                    if let doses = scheduledDoses(for: med, on: store.selectedDate, snapshot: store.snapshot), !doses.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(med.name)
                                .font(.subheadline.weight(.semibold))
                            ForEach(doses, id: \.id) { sched in
                                ScheduledDoseRow(
                                    medication: med,
                                    schedule: sched,
                                    date: store.selectedDate,
                                    isTaken: store.snapshot.takenByScheduleID[sched.id] != nil,
                                    toggle: { isOn in
                                        if isOn {
                                            logScheduledDose(
                                                schedule: sched,
                                                medication: med,
                                                selectedDate: store.selectedDate,
                                                onRefresh: { store.send(.refreshRequested) }
                                            )
                                        } else {
                                            unlogScheduledDose(
                                                schedule: sched,
                                                selectedDate: store.selectedDate,
                                                snapshot: store.snapshot,
                                                onRefresh: { store.send(.refreshRequested) }
                                            )
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(quickLogIdentifier(for: med, context: "scheduled"))
                    }
                }
            }

            if !asNeededMedications(snapshot: store.snapshot).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("As Needed")
                        .font(.subheadline.weight(.semibold))
                    ForEach(asNeededMedications(snapshot: store.snapshot)) { med in
                        Button {
                            presentAsNeeded(med, store.selectedDate)
                        } label: {
                            HStack {
                                Text(med.name)
                                Spacer()
                                Image(systemName: "plus.circle")
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(quickLogIdentifier(for: med, context: "asneeded"))
                    }
                }
                .padding(.top, 4)
            }

            Button("Manage Medications", action: manageAction)
                .foregroundStyle(.blue)

            if let error = loggingError ?? store.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private func scheduledMedications(snapshot: MedicationQuickLogSnapshot) -> [SQLiteMedication] {
        snapshot.medications.filter { !($0.isAsNeeded ?? false) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func asNeededMedications(snapshot: MedicationQuickLogSnapshot) -> [SQLiteMedication] {
        snapshot.medications.filter { $0.isAsNeeded ?? false }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scheduledDoses(
        for medication: SQLiteMedication,
        on date: Date,
        snapshot: MedicationQuickLogSnapshot
    ) -> [SQLiteMedicationSchedule]? {
        let all = snapshot.schedulesByMedication[medication.id] ?? []

        if all.isEmpty {
            let maskAllDays = MedicationWeekday.mask(for: MedicationWeekday.allCases)
            let synthetic = SQLiteMedicationSchedule(
                id: medication.id,
                medicationID: medication.id,
                label: "Daily",
                amount: medication.defaultAmount,
                unit: medication.defaultUnit,
                cadence: "daily",
                interval: 1,
                daysOfWeekMask: maskAllDays,
                hour: Int16(8),
                minute: Int16(0),
                timeZoneIdentifier: TimeZone.current.identifier,
                startDate: nil,
                isActive: true,
                sortOrder: 0
            )
            return [synthetic]
        }

        let mask = MedicationWeekday.mask(for: [weekday(for: date)])
        return all.filter { sched in
            (sched.isActive ?? true) && (sched.daysOfWeekMask & mask) == mask
        }
        .sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            let lh = Int(lhs.hour ?? 0), rh = Int(rhs.hour ?? 0)
            if lh != rh { return lh < rh }
            return Int(lhs.minute ?? 0) < Int(rhs.minute ?? 0)
        }
    }

    private func weekday(for date: Date) -> MedicationWeekday {
        let weekdayValue = Calendar.current.component(.weekday, from: date)
        return MedicationWeekday(rawValue: weekdayValue) ?? .monday
    }

    private func quickLogIdentifier(for medication: SQLiteMedication, context: String) -> String {
        let sanitized = medication.name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "quicklog-\(context)-\(sanitized)"
    }

    private func logScheduledDose(
        schedule: SQLiteMedicationSchedule,
        medication: SQLiteMedication,
        selectedDate: Date,
        onRefresh: @escaping () -> Void
    ) {
        @Dependency(\.defaultDatabase) var database
        let times = scheduledDateTime(for: schedule, on: selectedDate)
        let amountValue = schedule.amount ?? medication.defaultAmount
        let unitValue = schedule.unit ?? medication.defaultUnit
        do {
            try database.write { db in
                let persistedScheduleID = try Self.scheduleIDToPersist(scheduleID: schedule.id, db: db)
                let newIntake = SQLiteMedicationIntake(
                    id: UUID(),
                    medicationID: schedule.medicationID,
                    scheduleID: persistedScheduleID,
                    amount: amountValue,
                    unit: unitValue,
                    timestamp: times.timestamp,
                    scheduledDate: times.scheduledDate,
                    origin: "scheduled"
                )
                try SQLiteMedicationIntake.insert { newIntake }.execute(db)
            }
            NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
            onRefresh()
        } catch {
            // ignore for now
        }
    }

    static func scheduleIDToPersist(scheduleID: UUID, db: Database) throws -> UUID? {
        // Only persist a scheduleID that actually exists in the schedules table.
        let count = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM sqLiteMedicationSchedule WHERE lower(id) = lower(?) OR id = ?",
            arguments: [scheduleID.uuidString, scheduleID]
        ) ?? 0
        return count > 0 ? scheduleID : nil
    }

    private func unlogScheduledDose(
        schedule: SQLiteMedicationSchedule,
        selectedDate: Date,
        snapshot: MedicationQuickLogSnapshot,
        onRefresh: @escaping () -> Void
    ) {
        @Dependency(\.defaultDatabase) var database
        if let intake = snapshot.takenByScheduleID[schedule.id] {
            do {
                try database.write { db in
                    try SQLiteMedicationIntake.find(intake.id).delete().execute(db)
                }
                NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
                onRefresh()
            } catch {
                // ignore for now
            }
            return
        }
        if schedule.id == schedule.medicationID {
            let bounds = dayBounds(for: selectedDate)
            do {
                try database.write { db in
                    let medicationID = schedule.medicationID
                    let start = bounds.start
                    let end = bounds.end
                    try SQLiteMedicationIntake
                        .where { intake in
                            intake.medicationID.eq(medicationID) &&
                            intake.timestamp >= start &&
                            intake.timestamp < end &&
                            intake.scheduleID.is(nil)
                        }
                        .delete()
                        .execute(db)
                }
                NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
                onRefresh()
            } catch {
                // ignore
            }
        }
    }

    private func scheduledDateTime(for schedule: SQLiteMedicationSchedule, on date: Date) -> (timestamp: Date, scheduledDate: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        var comps = cal.dateComponents([.year, .month, .day], from: start)
        comps.hour = Int(schedule.hour ?? 8)
        comps.minute = Int(schedule.minute ?? 0)
        let scheduled = cal.date(from: comps) ?? start
        return (scheduled, start)
    }

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }
}

// MARK: - Row Views

private struct ScheduledDoseRow: View {
    let medication: SQLiteMedication
    let schedule: SQLiteMedicationSchedule
    let date: Date
    let isTaken: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(
                action: { toggle(!isTaken) },
                label: {
                    Image(systemName: isTaken ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isTaken ? .blue : .secondary)
                }
            )
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(schedule.label ?? "Dose")
                        .font(.subheadline)
                    Text(timeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let amount = schedule.amount ?? medication.defaultAmount,
                   let unit = schedule.unit ?? medication.defaultUnit {
                    Text("\(amount.cleanAmount) \(unit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var timeString: String {
        var comps = DateComponents()
        comps.hour = Int(schedule.hour ?? 8)
        comps.minute = Int(schedule.minute ?? 0)
        let cal = Calendar.current
        let doseTime = cal.date(from: comps) ?? Date()
        return doseTime.formatted(date: .omitted, time: .shortened)
    }
}

struct AsNeededIntakeView: View {
    @Bindable var store: StoreOf<AsNeededIntakeFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    Text(store.medication.name)
                }
                Section("When") {
                    DatePicker(
                        "Time",
                        selection: $store.timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                Section("Dose") {
                    TextField("Amount", text: $store.amount)
                        .decimalPadKeyboard()
                    TextField("Unit", text: $store.unit)
                }
                Section("Notes") {
                    TextField("Optional note", text: $store.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Log Dose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.send(.saveTapped) }
                        .disabled(!canSave() || store.isSaving)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .alert(
                "Unable to Save",
                isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { _ in store.send(.clearError) }
                )
            ) {
                Button("OK") { store.send(.clearError) }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .onChange(of: store.didSave) { _, didSave in
                guard didSave else { return }
                store.send(.clearDidSave)
                dismiss()
            }
            .task { store.send(.task) }
        }
    }

    private func canSave() -> Bool {
        Double(store.amount) != nil || store.medication.defaultAmount != nil
    }
}

extension Notification.Name {
    static let medicationsDidChange = Notification.Name("com.auralyst.medicationsDidChange")
    static let medicationIntakesDidChange = Notification.Name("com.auralyst.medicationIntakesDidChange")
}

extension Double {
    var cleanAmount: String {
        if floor(self) == self { return String(Int(self)) }
        return String(self)
    }
}

#Preview {
    withPreviewDataStore {
        let journal = DependencyValues._current.databaseClient.createJournal()
        List {
            MedicationQuickLogSection(
                store: Store(initialState: MedicationQuickLogFeature.State(journalID: journal.id)) {
                    MedicationQuickLogFeature()
                },
                manageAction: {},
                loggingError: nil,
                presentAsNeeded: { _, _ in }
            )
        }
    }
}
