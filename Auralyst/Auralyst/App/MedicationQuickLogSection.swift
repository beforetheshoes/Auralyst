import Foundation
import SQLiteData
import SwiftUI
import Dependencies

struct MedicationQuickLogSection: View {
    let journalID: UUID
    let manageAction: () -> Void
    let loggingError: String?

    @Environment(DataStore.self) private var dataStore

    @State private var snapshot: MedicationQuickLogSnapshot = .empty
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    @State private var navigatingMedication: NavigationMedication?
    private struct NavigationMedication: Identifiable, Hashable { let id: UUID }

    var body: some View {
        Section("Quick Medication Log") {
            // Date selector to backfill previous days
            DatePicker("Log Date", selection: $selectedDate, displayedComponents: [.date])
                .onChange(of: selectedDate) { _, _ in
                    refreshData()
                }

            // Scheduled medications
            if scheduledMedications.isEmpty {
                Text("No scheduled medications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scheduledMedications) { med in
                    if let doses = scheduledDoses(for: med, on: selectedDate), !doses.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(med.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            ForEach(doses, id: \.id) { sched in
                                ScheduledDoseRow(
                                    medication: med,
                                    schedule: sched,
                                    date: selectedDate,
                                    isTaken: snapshot.takenByScheduleID[sched.id] != nil,
                                    toggle: { isOn in
                                        if isOn { logScheduledDose(schedule: sched, medication: med) }
                                        else { unlogScheduledDose(schedule: sched) }
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // As-needed medications
            if !asNeededMedications.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("As Needed")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ForEach(asNeededMedications) { med in
                        HStack {
                            Text(med.name)
                            Spacer()
                            Button {
                                navigatingMedication = NavigationMedication(id: med.id)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }

            Button("Manage Medications", action: manageAction)
                .foregroundColor(.blue)

            if let error = loggingError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .medicationsDidChange)) { _ in
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .medicationIntakesDidChange)) { _ in
            refreshData()
        }
        .onAppear { refreshData() }
        .navigationDestination(item: $navigatingMedication) { payload in
            if let med = latestMedication(with: payload.id) {
                AsNeededIntakeView(
                    medication: med,
                    defaultDate: selectedDate,
                    onSaved: {
                        refreshData(force: true)
                    }
                )
            } else {
                Text("Medication unavailable")
            }
        }
    }

    private func refreshData(force: Bool = false) {
        do {
            snapshot = try MedicationQuickLogLoader(dataStore: dataStore)
                .load(journalID: journalID, on: selectedDate)
        } catch {
            snapshot = .empty
        }
    }

    private func latestMedication(with id: UUID) -> SQLiteMedication? {
        if let current = snapshot.medications.first(where: { $0.id == id }) {
            return current
        }
        @Dependency(\.defaultDatabase) var database
        return try? database.read { db in try SQLiteMedication.find(id).fetchOne(db) }
    }

    // MARK: - Derived Collections

    private var scheduledMedications: [SQLiteMedication] {
        snapshot.medications.filter { !($0.isAsNeeded ?? false) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var asNeededMedications: [SQLiteMedication] {
        snapshot.medications.filter { $0.isAsNeeded ?? false }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scheduledDoses(for medication: SQLiteMedication, on date: Date) -> [SQLiteMedicationSchedule]? {
        let all = snapshot.schedulesByMedication[medication.id] ?? []

        // If no explicit doses are defined, default to once-daily at 8:00 AM
        if all.isEmpty {
            let maskAllDays = MedicationWeekday.mask(for: MedicationWeekday.allCases)
            let synthetic = SQLiteMedicationSchedule(
                id: medication.id, // stable ID so toggling works per med
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
        let w = Calendar.current.component(.weekday, from: date)
        return MedicationWeekday(rawValue: w) ?? .monday
    }

    // MARK: - Actions

    private func logScheduledDose(schedule: SQLiteMedicationSchedule, medication: SQLiteMedication) {
        @Dependency(\.defaultDatabase) var database
        let times = scheduledDateTime(for: schedule, on: selectedDate)
        let amountValue = schedule.amount ?? medication.defaultAmount
        let unitValue = schedule.unit ?? medication.defaultUnit
        let newIntake = SQLiteMedicationIntake(
            id: UUID(),
            medicationID: schedule.medicationID,
            scheduleID: schedule.id,
            amount: amountValue,
            unit: unitValue,
            timestamp: times.timestamp,
            scheduledDate: times.scheduledDate,
            origin: "scheduled"
        )
        do {
            try database.write { db in
                try SQLiteMedicationIntake.insert { newIntake }.execute(db)
            }
            NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
            refreshData(force: true)
        } catch {
            // ignore for now
        }
    }

    private func unlogScheduledDose(schedule: SQLiteMedicationSchedule) {
        @Dependency(\.defaultDatabase) var database
        if let intake = snapshot.takenByScheduleID[schedule.id] {
            do {
                try database.write { db in
                    try SQLiteMedicationIntake.find(intake.id).delete().execute(db)
                }
                NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
                refreshData(force: true)
            } catch {
                // ignore for now
            }
            return
        }
        // Synthetic once-daily case: remove any intake for this medication on selected day
        if schedule.id == schedule.medicationID {
            let bounds = dayBounds(for: selectedDate)
            do {
                try database.write { db in
                    try SQLiteMedicationIntake
                        .where { intake in
                            intake.medicationID == schedule.medicationID &&
                            intake.timestamp >= bounds.start &&
                            intake.timestamp < bounds.end &&
                            intake.scheduleID == nil
                        }
                        .delete()
                        .execute(db)
                }
                NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
                refreshData(force: true)
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
        let ts = cal.date(from: comps) ?? start
        return (ts, start)
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
            Button(action: { toggle(!isTaken) }) {
                Image(systemName: isTaken ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isTaken ? .blue : .secondary)
            }
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
        let d = cal.date(from: comps) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
}

private struct AsNeededIntakeView: View {
    let medication: SQLiteMedication
    let defaultDate: Date
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var unit: String = ""
    @State private var notes: String = ""
    @State private var timestamp: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    Text(medication.name)
                }
                Section("When") {
                    DatePicker("Time", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Dose") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("Unit", text: $unit)
                }
                Section("Notes") {
                    TextField("Optional note", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Log Dose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: seed)
        }
    }

    private var canSave: Bool {
        Double(amount) != nil || medication.defaultAmount != nil
    }

    private func seed() {
        amount = medication.defaultAmount.map { $0.cleanAmount } ?? ""
        unit = medication.defaultUnit ?? ""
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: defaultDate)
        let now = Date()
        let comps = cal.dateComponents([.hour, .minute], from: now)
        var dtc = cal.dateComponents([.year, .month, .day], from: dayStart)
        dtc.hour = comps.hour
        dtc.minute = comps.minute
        timestamp = cal.date(from: dtc) ?? defaultDate
    }

    private func save() {
        @Dependency(\.defaultDatabase) var database
        let amt = Double(amount) ?? medication.defaultAmount
        let unitValue = unit.isEmpty ? medication.defaultUnit : unit
        let noteValue = notes.isEmpty ? nil : notes
        let intake = SQLiteMedicationIntake(
            id: UUID(),
            medicationID: medication.id,
            amount: amt,
            unit: unitValue,
            timestamp: timestamp,
            origin: "asNeeded",
            notes: noteValue
        )
        do {
            try database.write { db in
                try SQLiteMedicationIntake.insert { intake }.execute(db)
            }
            NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
            onSaved()
            dismiss()
        } catch {
            dismiss()
        }
    }
}

extension Notification.Name {
    static let medicationsDidChange = Notification.Name("com.auralyst.medicationsDidChange")
    static let medicationIntakesDidChange = Notification.Name("com.auralyst.medicationIntakesDidChange")
}

private extension Double {
    var cleanAmount: String {
        if floor(self) == self { return String(Int(self)) }
        return String(self)
    }
}

#Preview {
    withPreviewDataStore { dataStore in
        let journal = dataStore.createJournal()
        List {
            MedicationQuickLogSection(
                journalID: journal.id,
                manageAction: {},
                loggingError: nil
            )
        }
    }
}
