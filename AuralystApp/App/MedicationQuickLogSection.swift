import Foundation
@preconcurrency import SQLiteData
import SwiftUI
import Dependencies
import ComposableArchitecture

struct MedicationQuickLogSection: View {
    let store: StoreOf<MedicationQuickLogFeature>
    let manageAction: () -> Void
    let loggingError: String?
    let presentAsNeeded: (SQLiteMedication, Date) -> Void

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Section("Quick Medication Log") {
                DatePicker(
                    "Log Date",
                    selection: Binding(
                        get: { viewStore.selectedDate },
                        set: { viewStore.send(.selectedDateChanged($0)) }
                    ),
                    displayedComponents: [.date]
                )

                if scheduledMedications(snapshot: viewStore.snapshot).isEmpty {
                    Text("No scheduled medications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scheduledMedications(snapshot: viewStore.snapshot)) { med in
                        if let doses = scheduledDoses(for: med, on: viewStore.selectedDate, snapshot: viewStore.snapshot), !doses.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(med.name)
                                    .font(.subheadline.weight(.semibold))
                                ForEach(doses, id: \.id) { sched in
                                    ScheduledDoseRow(
                                        medication: med,
                                        schedule: sched,
                                        date: viewStore.selectedDate,
                                        isTaken: viewStore.snapshot.takenByScheduleID[sched.id] != nil,
                                        toggle: { isOn in
                                            if isOn {
                                                logScheduledDose(
                                                    schedule: sched,
                                                    medication: med,
                                                    selectedDate: viewStore.selectedDate,
                                                    onRefresh: { viewStore.send(.refreshRequested) }
                                                )
                                            } else {
                                                unlogScheduledDose(
                                                    schedule: sched,
                                                    selectedDate: viewStore.selectedDate,
                                                    snapshot: viewStore.snapshot,
                                                    onRefresh: { viewStore.send(.refreshRequested) }
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

                if !asNeededMedications(snapshot: viewStore.snapshot).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("As Needed")
                            .font(.subheadline.weight(.semibold))
                        ForEach(asNeededMedications(snapshot: viewStore.snapshot)) { med in
                            Button {
                                presentAsNeeded(med, viewStore.selectedDate)
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

                if let error = loggingError ?? viewStore.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .task { viewStore.send(.task) }
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
        let w = Calendar.current.component(.weekday, from: date)
        return MedicationWeekday(rawValue: w) ?? .monday
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
            onRefresh()
        } catch {
            // ignore for now
        }
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

struct AsNeededIntakeView: View {
    let store: StoreOf<AsNeededIntakeFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                Form {
                    Section("Medication") {
                        Text(viewStore.medication.name)
                    }
                    Section("When") {
                        DatePicker(
                            "Time",
                            selection: viewStore.binding(
                                get: \.timestamp,
                                send: { .binding(.set(\.timestamp, $0)) }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    Section("Dose") {
                        TextField(
                            "Amount",
                            text: viewStore.binding(
                                get: \.amount,
                                send: { .binding(.set(\.amount, $0)) }
                            )
                        )
                        .decimalPadKeyboard()
                        TextField(
                            "Unit",
                            text: viewStore.binding(
                                get: \.unit,
                                send: { .binding(.set(\.unit, $0)) }
                            )
                        )
                    }
                    Section("Notes") {
                        TextField(
                            "Optional note",
                            text: viewStore.binding(
                                get: \.notes,
                                send: { .binding(.set(\.notes, $0)) }
                            ),
                            axis: .vertical
                        )
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
                        Button("Save") { viewStore.send(.saveTapped) }
                            .disabled(!canSave(viewStore) || viewStore.isSaving)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .alert(
                    "Unable to Save",
                    isPresented: viewStore.binding(
                        get: { $0.errorMessage != nil },
                        send: { _ in .clearError }
                    )
                ) {
                    Button("OK") { viewStore.send(.clearError) }
                } message: {
                    Text(viewStore.errorMessage ?? "")
                }
                .onChange(of: viewStore.didSave) { _, didSave in
                    guard didSave else { return }
                    viewStore.send(.clearDidSave)
                    dismiss()
                }
                .task { viewStore.send(.task) }
            }
        }
    }

    private func canSave(_ viewStore: ViewStoreOf<AsNeededIntakeFeature>) -> Bool {
        Double(viewStore.amount) != nil || viewStore.medication.defaultAmount != nil
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
