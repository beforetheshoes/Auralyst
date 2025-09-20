import CoreData
import SwiftUI

struct MedicationEditorView: View {
    let mode: MedicationsView.EditorMode
    let journalID: NSManagedObjectID

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var form = MedicationFormState()
    @State private var didLoad = false

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name", text: $form.name)
                    Toggle("As Needed", isOn: $form.isAsNeeded)
                        .toggleStyle(.switch)
                        .animation(.easeInOut, value: form.isAsNeeded)
                    TextField("Default Amount", text: $form.defaultAmount)
                        .keyboardType(.decimalPad)
                    TextField("Unit", text: $form.defaultUnit)
                    TextField("Use Case (e.g. Anxiety)", text: $form.useCase)
                    TextField("Notes", text: $form.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if form.isAsNeeded == false {
                    Section("Schedule") {
                        if form.scheduleForms.isEmpty {
                            Text("Add at least one time of day.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($form.scheduleForms) { $schedule in
                                ScheduleFormView(schedule: $schedule)
                            }
                            .onDelete(perform: removeSchedules)
                        }

                        Button {
                            addSchedule()
                        } label: {
                            Label("Add Time", systemImage: "plus.circle")
                        }
                    }
                }

                if case .edit = mode {
                    Section {
                        Button("Delete Medication", role: .destructive, action: deleteMedication)
                    }
                }
            }
            .navigationTitle(modeTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
#if os(macOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    Button("Save", action: save)
                        .disabled(isSaveDisabled)
                        .keyboardShortcut(.defaultAction)
                }
#else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isSaveDisabled)
                        .keyboardShortcut(.defaultAction)
                }
#endif
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create: return "New Medication"
        case .edit: return "Edit Medication"
        }
    }

    private var isSaveDisabled: Bool {
        let trimmedName = form.name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return true }
        if form.isAsNeeded == false {
            if form.scheduleForms.isEmpty { return true }
            for schedule in form.scheduleForms where schedule.cadence == .weekly && schedule.weekdays.isEmpty {
                return true
            }
        }
        return false
    }

    private func loadIfNeeded() {
        guard didLoad == false else { return }
        defer { didLoad = true }

        switch mode {
        case .create:
            form = MedicationFormState()
        case .edit(let objectID):
            if let medication = try? context.existingObject(with: objectID) as? Medication {
                form = MedicationFormState(medication: medication, formatter: numberFormatter)
            }
        }
    }

    private func addSchedule() {
        let order = form.scheduleForms.count
        form.scheduleForms.append(MedicationScheduleFormState.makeDefault(order: order))
    }

    private func removeSchedules(at offsets: IndexSet) {
        form.scheduleForms.remove(atOffsets: offsets)
    }

    private func save() {
        guard let journal = try? context.existingObject(with: journalID) as? Journal else {
            assertionFailure("Journal missing for medication save")
            return
        }

        let medication: Medication
        switch mode {
        case .create:
            medication = Medication(context: context)
            medication.id = UUID()
            medication.createdAt = Date()
            medication.journal = journal
        case .edit(let objectID):
            guard let existing = try? context.existingObject(with: objectID) as? Medication else {
                assertionFailure("Unable to find medication to edit")
                return
            }
            medication = existing
        }

        apply(form: form, to: medication)

        do {
            try context.save()
            dismiss()
        } catch {
            assertionFailure("Failed to save medication: \(error)")
        }
    }

    private func apply(form: MedicationFormState, to medication: Medication) {
        let trimmedName = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.name = trimmedName
        let trimmedNotes = form.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        medication.isAsNeeded = form.isAsNeeded

        if let amount = decimal(from: form.defaultAmount) {
            medication.defaultAmount = amount.nsDecimalNumber
        } else {
            medication.defaultAmount = nil
        }

        let unit = form.defaultUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.defaultUnit = unit.isEmpty ? nil : unit
        let useCaseValue = form.useCase.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.useCase = useCaseValue.isEmpty ? nil : useCaseValue
        medication.updatedAt = Date()

        let existingSchedules = (medication.scheduleItems as? Set<MedicationSchedule>) ?? []
        if form.isAsNeeded {
            existingSchedules.forEach { context.delete($0) }
            return
        }

        var handledIDs: Set<NSManagedObjectID> = []
        for (index, state) in form.scheduleForms.enumerated() {
            let schedule: MedicationSchedule
            if let objectID = state.objectID,
               let existing = existingSchedules.first(where: { $0.objectID == objectID }) {
                schedule = existing
                handledIDs.insert(objectID)
            } else {
                schedule = MedicationSchedule(context: context)
                schedule.id = UUID()
                schedule.startDate = state.startDate
                schedule.medication = medication
            }

            let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: state.time)
            schedule.hour = Int16(timeComponents.hour ?? 0)
            schedule.minute = Int16(timeComponents.minute ?? 0)
            schedule.sortOrder = Int16(index)
            schedule.label = state.label.trimmingCharacters(in: .whitespacesAndNewlines)
            schedule.cadence = state.cadence.rawValue
            schedule.interval = Int16(max(state.interval, 1))
            schedule.isActive = state.isActive
            schedule.startDate = state.startDate
            schedule.timeZoneIdentifier = state.timeZoneIdentifier ?? TimeZone.current.identifier
            schedule.daysOfWeekMask = MedicationWeekday.mask(for: Array(state.weekdays))

            if let amount = decimal(from: state.amount) {
                schedule.amount = amount.nsDecimalNumber
            } else {
                schedule.amount = nil
            }

            let unit = state.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            schedule.unit = unit.isEmpty ? nil : unit
        }

        let toDelete = existingSchedules.filter { schedule in
            handledIDs.contains(schedule.objectID) == false
        }
        toDelete.forEach { context.delete($0) }
    }

    private func decimal(from string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return numberFormatter.number(from: trimmed)?.decimalValue
    }

    private func deleteMedication() {
        guard case .edit(let objectID) = mode,
              let medication = try? context.existingObject(with: objectID) as? Medication else {
            dismiss()
            return
        }
        context.delete(medication)
        try? context.save()
        dismiss()
    }
}

private struct MedicationFormState {
    var name: String = ""
    var notes: String = ""
    var isAsNeeded: Bool = false
    var defaultAmount: String = ""
    var defaultUnit: String = ""
    var useCase: String = ""
    var scheduleForms: [MedicationScheduleFormState] = [MedicationScheduleFormState.makeDefault(order: 0)]

    init() {}

    init(medication: Medication, formatter: NumberFormatter) {
        name = medication.name ?? ""
        notes = medication.notes ?? ""
        isAsNeeded = medication.isAsNeeded
        if let amount = medication.defaultAmountValue {
            defaultAmount = formatter.string(from: amount.nsDecimalNumber) ?? ""
        }
        defaultUnit = medication.defaultUnit ?? ""
        useCase = medication.useCase ?? ""

        if medication.isAsNeeded {
            scheduleForms = []
        } else {
            let schedules = medication.scheduleList
            scheduleForms = schedules.enumerated().map { index, schedule in
                MedicationScheduleFormState(schedule: schedule, order: index, formatter: formatter)
            }
        }
    }
}

private struct MedicationScheduleFormState: Identifiable {
    let id: UUID
    var objectID: NSManagedObjectID?
    var label: String
    var time: Date
    var amount: String
    var unit: String
    var cadence: MedicationSchedule.Cadence
    var interval: Int
    var weekdays: Set<MedicationWeekday>
    var isActive: Bool
    var sortOrder: Int
    var startDate: Date
    var timeZoneIdentifier: String?

    init(id: UUID = UUID(),
         objectID: NSManagedObjectID? = nil,
         label: String = "",
         time: Date,
         amount: String = "",
         unit: String = "",
         cadence: MedicationSchedule.Cadence = .daily,
         interval: Int = 1,
         weekdays: Set<MedicationWeekday> = [],
         isActive: Bool = true,
         sortOrder: Int,
         startDate: Date = Date(),
         timeZoneIdentifier: String? = nil) {
        self.id = id
        self.objectID = objectID
        self.label = label
        self.time = time
        self.amount = amount
        self.unit = unit
        self.cadence = cadence
        self.interval = max(interval, 1)
        self.weekdays = weekdays
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.startDate = startDate
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(schedule: MedicationSchedule, order: Int, formatter: NumberFormatter) {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = Int(schedule.hour)
        components.minute = Int(schedule.minute)
        let time = calendar.date(from: components) ?? Date()

        let amountString: String
        if let amount = schedule.amountValue {
            amountString = formatter.string(from: amount.nsDecimalNumber) ?? ""
        } else {
            amountString = ""
        }

        self.init(
            objectID: schedule.objectID,
            label: schedule.label ?? "",
            time: time,
            amount: amountString,
            unit: schedule.unit ?? "",
            cadence: schedule.cadenceValue,
            interval: Int(schedule.interval == 0 ? 1 : schedule.interval),
            weekdays: Set(schedule.weekdays),
            isActive: schedule.isActive,
            sortOrder: order,
            startDate: schedule.startDate ?? Date(),
            timeZoneIdentifier: schedule.timeZoneIdentifier
        )
    }

    static func makeDefault(order: Int) -> MedicationScheduleFormState {
        var components = DateComponents()
        components.hour = 8
        components.minute = 0
        let calendar = Calendar.current
        let time = calendar.date(from: components) ?? Date()
        return MedicationScheduleFormState(time: time, sortOrder: order)
    }
}

private struct ScheduleFormView: View {
    @Binding var schedule: MedicationScheduleFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Label", text: $schedule.label)
            DatePicker("Time", selection: $schedule.time, displayedComponents: .hourAndMinute)
            TextField("Amount", text: $schedule.amount)
                .keyboardType(.decimalPad)
            TextField("Unit", text: $schedule.unit)

            Picker("Cadence", selection: $schedule.cadence) {
                ForEach(MedicationSchedule.Cadence.allCases) { cadence in
                    Text(cadence.label).tag(cadence)
                }
            }
            .pickerStyle(.segmented)

            switch schedule.cadence {
            case .weekly, .custom:
                WeekdaySelector(selectedDays: $schedule.weekdays)
            case .interval:
                Stepper(value: $schedule.interval, in: 1...30) {
                    Text("Every \(schedule.interval) day\(schedule.interval == 1 ? "" : "s")")
                }
                DatePicker("Starts", selection: $schedule.startDate, displayedComponents: .date)
            case .daily:
                EmptyView()
            }

            Toggle("Active", isOn: $schedule.isActive)
        }
        .padding(.vertical, 4)
    }
}

private struct WeekdaySelector: View {
    @Binding var selectedDays: Set<MedicationWeekday>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekdays")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(MedicationWeekday.allCases, id: \.self) { day in
                    let isSelected = selectedDays.contains(day)
                    Button {
                        toggle(day)
                    } label: {
                        Text(day.shortName)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.brandPrimary.opacity(0.2) : Color.surfaceLight, in: Capsule())
                            .foregroundStyle(isSelected ? Color.brandPrimary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggle(_ day: MedicationWeekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}
