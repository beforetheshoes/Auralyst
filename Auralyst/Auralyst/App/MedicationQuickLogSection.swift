import CoreData
import SwiftUI

struct MedicationQuickLogSection: View {
    let journalID: NSManagedObjectID
    let manageAction: () -> Void
    let onLogAsNeeded: (MedicationTodayModel.AsNeededItem) -> Void
    let loggingError: String?
    let refreshToken: Int

    @Environment(\.managedObjectContext) private var context

    @State private var model: MedicationTodayModel
    @State private var selectedDay: Date

    init(
        journalID: NSManagedObjectID,
        manageAction: @escaping () -> Void,
        onLogAsNeeded: @escaping (MedicationTodayModel.AsNeededItem) -> Void = { _ in },
        loggingError: String? = nil,
        refreshToken: Int = 0
    ) {
        self.journalID = journalID
        self.manageAction = manageAction
        self.onLogAsNeeded = onLogAsNeeded
        self.loggingError = loggingError
        self.refreshToken = refreshToken
        let initialDay = Calendar.current.startOfDay(for: Date())
        _model = State(initialValue: MedicationTodayModel(journalID: journalID, day: initialDay))
        _selectedDay = State(initialValue: initialDay)
    }

    var body: some View {
        let dayBinding = Binding<Date>(
            get: { selectedDay },
            set: { updateSelectedDay($0) }
        )

        Section {
            if model.hasMedications == false {
                VStack(spacing: 8) {
                    Text("Set up medications to check off doses or log as they happen.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Set Up Medications", action: manageAction)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            } else {
                if model.scheduled.isEmpty == false {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.scheduled) { occurrence in
                            ScheduledDoseRow(occurrence: occurrence) {
                                toggleScheduled(occurrence)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("No scheduled doses today.")
                        .foregroundStyle(.secondary)
                }

                if model.asNeeded.isEmpty == false {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("As Needed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ForEach(model.asNeeded) { item in
                            Button {
                                onLogAsNeeded(item)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.medicationName)
                                            .font(.headline)
                                            .foregroundStyle(Color.ink)
                                        if let useCase = item.medicationUseCase {
                                            Text(useCase)
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(Color.brandAccent)
                                        }
                                        if let amount = item.displayAmount {
                                            Text(amount)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let last = item.lastLoggedAt {
                                            Text("Last logged \(last, format: .relative(presentation: .named))")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Label("Log", systemImage: "plus.circle")
                                        .labelStyle(.iconOnly)
                                        .font(.title3)
                                        .foregroundStyle(Color.brandPrimary)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Log \(item.medicationName)")
                        }

                        if let loggingError {
                            Text(loggingError)
                                .font(.footnote)
                                .foregroundStyle(Color.red)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 12)
                }

                Button("Manage Medications", action: manageAction)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
            }
        } header: {
            MedicationQuickLogHeader(
                day: model.day,
                canAdvance: canAdvanceDay,
                dateBinding: dayBinding,
                onPrevious: { shiftSelectedDay(by: -1) },
                onNext: { shiftSelectedDay(by: 1) }
            )
        }
        .task { refresh() }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
            refresh()
        }
        .onChange(of: refreshToken, initial: false) { _, _ in
            refresh()
        }
    }

    private func refresh() {
        model.refresh(in: context)
    }

    private func toggleScheduled(_ occurrence: MedicationTodayModel.ScheduledOccurrence) {
        guard let schedule = try? context.existingObject(with: occurrence.scheduleID) as? MedicationSchedule else {
            return
        }
        let store = MedicationStore(context: context)
        let markingTaken = occurrence.taken == false
        let overrideTimestamp = markingTaken ? loggedTimestamp(for: occurrence) : nil
        _ = store.setScheduledIntake(
            schedule,
            on: model.day,
            taken: !occurrence.taken,
            loggedAt: overrideTimestamp
        )
        try? context.save()
        refresh()
    }

    private var canAdvanceDay: Bool {
        selectedDay < Calendar.current.startOfDay(for: Date())
    }

    private func shiftSelectedDay(by offset: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: offset, to: selectedDay) else { return }
        if offset > 0 && canAdvanceDay == false { return }
        updateSelectedDay(next)
    }

    private func updateSelectedDay(_ newValue: Date) {
        let normalized = Calendar.current.startOfDay(for: newValue)
        let today = Calendar.current.startOfDay(for: Date())
        guard normalized <= today else { return }
        guard normalized != selectedDay else { return }
        selectedDay = normalized
        model.day = normalized
        refresh()
    }

    private func loggedTimestamp(for occurrence: MedicationTodayModel.ScheduledOccurrence) -> Date {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        if calendar.isDate(selectedDay, inSameDayAs: todayStart) {
            return Date()
        }
        return occurrence.scheduledAt
    }

}

private struct MedicationQuickLogHeader: View {
    let day: Date
    let canAdvance: Bool
    let dateBinding: Binding<Date>
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var dateRange: ClosedRange<Date> {
        Date.distantPast...today
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Medications")
                .font(.headline)
                .foregroundStyle(Color.ink)

            HStack(spacing: 8) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous day")

                DatePicker(
                    "",
                    selection: dateBinding,
                    in: dateRange,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(canAdvance == false)
                .accessibilityLabel("Next day")
            }

            Text(day, format: .dateTime.weekday(.wide).month().day().year())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScheduledDoseRow: View {
    let occurrence: MedicationTodayModel.ScheduledOccurrence
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: occurrence.taken ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(occurrence.taken ? Color.brandPrimary : .secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(occurrence.medicationName)
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                    if let useCase = occurrence.medicationUseCase {
                        Text(useCase)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.brandAccent)
                    }
                    HStack(spacing: 6) {
                        if occurrence.scheduleLabel.isEmpty == false {
                            Text(occurrence.scheduleLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let amount = occurrence.displayAmount {
                            Text(amount)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(occurrence.scheduledAt, format: .dateTime.hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let logged = occurrence.intakeTimestamp {
                        Text("Logged \(logged, format: .relative(presentation: .named))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
    }
}

extension MedicationQuickLogSection {
    struct AsNeededLogSheet: View {
        let item: MedicationTodayModel.AsNeededItem
        let onCommit: (Decimal?, String?, Date) -> Void

        @Environment(\.dismiss) private var dismiss

        @State private var amountValue: Double?
        @State private var unit: String
        @State private var timestamp: Date = Date()

        private let numberFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        init(item: MedicationTodayModel.AsNeededItem, onCommit: @escaping (Decimal?, String?, Date) -> Void) {
            self.item = item
            self.onCommit = onCommit
            _amountValue = State(initialValue: item.defaultAmount.map { NSDecimalNumber(decimal: $0).doubleValue })
            _unit = State(initialValue: item.unit ?? "")
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section(item.medicationName) {
                        TextField("Amount", value: $amountValue, formatter: numberFormatter)
                            .keyboardType(.decimalPad)
                        TextField("Unit", text: $unit)
                        DatePicker("When", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                .navigationTitle("Log Dose")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: { dismiss() })
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Log") {
                            let amount = amountValue.map { NSDecimalNumber(value: $0).decimalValue }
                            let unitValue = unit.trimmingCharacters(in: .whitespaces)
                            onCommit(amount, unitValue.isEmpty ? nil : unitValue, timestamp)
                            dismiss()
                        }
                        .disabled(amountValue == nil)
                    }
                }
            }
        }
    }
}
