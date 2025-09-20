import CoreData
import SwiftUI

struct JournalEntriesView: View {
    let journalID: NSManagedObjectID
    let journalIdentifier: UUID
    let onAddEntry: () -> Void

    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var entries: FetchedResults<SymptomEntry>
    @FetchRequest private var medicationIntakes: FetchedResults<MedicationIntake>
    @State private var showingMedicationManager = false
    @State private var selectedAsNeededItem: MedicationTodayModel.AsNeededItem?
    @State private var asNeededLoggingError: String?
    @State private var asNeededRefreshToken = 0
    @State private var editingIntake: MedicationIntake?
    @State private var pendingDeleteIntake: MedicationIntake?
    @State private var showingDeleteConfirmation = false
    @State private var deletionError: String?
    @State private var expandedDays: Set<Date> = []

    init(journalID: NSManagedObjectID, journalIdentifier: UUID, onAddEntry: @escaping () -> Void) {
        self.journalID = journalID
        self.journalIdentifier = journalIdentifier
        self.onAddEntry = onAddEntry
        _entries = FetchRequest(
            entity: SymptomEntry.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \SymptomEntry.timestamp, ascending: false)],
            predicate: NSPredicate(
                format: "(journal == %@) OR (journal.id == %@)",
                journalID,
                journalIdentifier as CVarArg
            ),
            animation: .default
        )
        _medicationIntakes = FetchRequest(
            entity: MedicationIntake.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \MedicationIntake.timestamp, ascending: false)],
            predicate: NSPredicate(
                format: "(medication.journal == %@) OR (entry.journal == %@) OR (medication.journal.id == %@) OR (entry.journal.id == %@)",
                journalID,
                journalID,
                journalIdentifier as CVarArg,
                journalIdentifier as CVarArg
            ),
            animation: .default
        )
    }

    var body: some View {
        List {
            MedicationQuickLogSection(
                journalID: journalID,
                manageAction: { showingMedicationManager = true },
                onLogAsNeeded: { item in
                    guard selectedAsNeededItem == nil else { return }
                    asNeededLoggingError = nil
                    let selection = item
                    DispatchQueue.main.async {
                        selectedAsNeededItem = selection
                    }
                },
                loggingError: asNeededLoggingError,
                refreshToken: asNeededRefreshToken
            )

            if timelineSections.isEmpty {
                Section {
                    TimelineEmptyState(addAction: onAddEntry)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(timelineSections) { section in
                    Section(section.date.formatted(date: .abbreviated, time: .omitted)) {
                        let isExpanded = expandedDays.contains(section.date)

                        if section.intakes.isEmpty == false {
                            MedicationDaySummaryRow(
                                intakes: section.intakes,
                                isExpanded: isExpanded
                            ) {
                                toggleDayExpansion(section.date)
                            }
                        }

                        ForEach(section.entries, id: \.objectID) { entry in
                            NavigationLink {
                                EntryDetailView(entryID: entry.objectID)
                            } label: {
                                SymptomEntryRow(entry: entry)
                            }
                        }

                        if isExpanded {
                            ForEach(section.intakes, id: \.objectID) { intake in
                                MedicationIntakeSummaryRow(intake: intake)
                                    .modifier(IntakeActionsModifier(
                                        onEdit: { editingIntake = intake },
                                        onDelete: { promptDelete(intake) }
                                    ))
                            }
                        }
                    }
                    .listRowBackground(Color.surfaceLight)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.surfaceLight)
        .sheet(isPresented: $showingMedicationManager) {
            MedicationsView(journalID: journalID)
        }
        .sheet(item: $selectedAsNeededItem, onDismiss: { selectedAsNeededItem = nil }) { item in
            MedicationQuickLogSection.AsNeededLogSheet(item: item) { amount, unit, timestamp in
                logAsNeeded(item: item, amount: amount, unit: unit, timestamp: timestamp)
            }
        }
        .sheet(item: $editingIntake, onDismiss: { editingIntake = nil }) { intake in
            MedicationIntakeEditorView(intakeID: intake.objectID)
        }
        .confirmationDialog(
            "Delete Dose?",
            isPresented: $showingDeleteConfirmation,
            presenting: pendingDeleteIntake
        ) { intake in
            Button("Delete", role: .destructive) {
                delete(intake)
            }
        } message: { _ in
            Text("This removes the logged medication from the journal.")
        }
        .alert("Unable to Delete", isPresented: Binding(get: { deletionError != nil }, set: { if $0 == false { deletionError = nil } })) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
    }

    private var timelineSections: [DaySection] {
        let calendar = Calendar.current

        let entryGroups = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.timestampValue)
        }
        let intakeGroups = Dictionary(grouping: medicationIntakes) { intake in
            calendar.startOfDay(for: intake.groupingDate)
        }

        let allDates = Set(entryGroups.keys).union(Set(intakeGroups.keys))
        guard allDates.isEmpty == false else { return [] }

        let sortedDates = allDates.sorted(by: >)
        return sortedDates.map { date in
            let dayEntries = (entryGroups[date] ?? [])
                .sorted(by: { $0.timestampValue > $1.timestampValue })
            let dayIntakes = (intakeGroups[date] ?? [])
                .sorted(by: { $0.timestampValue > $1.timestampValue })
            return DaySection(date: date, entries: dayEntries, intakes: dayIntakes)
        }
    }

    func logAsNeeded(item: MedicationTodayModel.AsNeededItem, amount: Decimal?, unit: String?, timestamp: Date) {
        guard let medication = try? context.existingObject(with: item.id) as? Medication else {
            asNeededLoggingError = "Unable to find medication"
            return
        }

        let store = MedicationStore(context: context)
        _ = store.logAsNeeded(medication, amount: amount, unit: unit, at: timestamp)

        do {
            try context.save()
            asNeededLoggingError = nil
            selectedAsNeededItem = nil
            asNeededRefreshToken &+= 1
        } catch {
            context.rollback()
            asNeededLoggingError = error.localizedDescription
        }
    }

    private func promptDelete(_ intake: MedicationIntake) {
        pendingDeleteIntake = intake
        showingDeleteConfirmation = true
    }

    private func delete(_ intake: MedicationIntake) {
        pendingDeleteIntake = nil
        context.perform {
            if intake.managedObjectContext == nil {
                return
            }

            context.delete(intake)
            do {
                try context.save()
                deletionError = nil
            } catch {
                context.rollback()
                deletionError = error.localizedDescription
            }
        }
    }

    private func toggleDayExpansion(_ date: Date) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedDays.contains(date) {
                expandedDays.remove(date)
            } else {
                expandedDays.insert(date)
            }
        }
    }
}

private struct DaySection: Identifiable {
    let date: Date
    let entries: [SymptomEntry]
    let intakes: [MedicationIntake]

    var id: Date { date }
}

struct SymptomEntryRow: View {
    let entry: SymptomEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.timestampValue, format: .dateTime.hour().minute())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if entry.isMenstruating {
                    Text("MENSTRUATING")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.brandAccent.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.brandAccent)
                }

                Spacer()

                Text("Severity \(entry.severity)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.brandAccent)
            }

            if let note = entry.note, note.isEmpty == false {
                Text(note)
                    .font(.body)
                    .foregroundStyle(Color.ink.opacity(0.75))
            }
        }
        .padding(.vertical, 8)
    }
}

private struct TimelineEmptyState: View {
    let addAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Start with today. Auralyst will trace the line.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Add First Entry", action: addAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 24)
    }
}

private struct MedicationDaySummaryRow: View {
    let intakes: [MedicationIntake]
    let isExpanded: Bool
    let toggle: () -> Void

    private var scheduledCount: Int {
        intakes.filter { $0.originValue == .scheduled }.count
    }

    private var asNeededIntakes: [MedicationIntake] {
        intakes.filter { $0.originValue == .asNeeded }
            .sorted(by: { $0.timestampValue > $1.timestampValue })
    }

    private var manualCount: Int {
        intakes.filter { $0.originValue == .manual }.count
    }

    private var summaryText: String {
        var components: [String] = []
        if scheduledCount > 0 {
            components.append("\(scheduledCount) scheduled")
        }
        if asNeededIntakes.isEmpty == false {
            components.append("\(asNeededIntakes.count) as needed")
        }
        if manualCount > 0 {
            components.append("\(manualCount) manual")
        }
        if components.isEmpty {
            components.append("No doses logged")
        }
        return components.joined(separator: " • ")
    }

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Medications")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)

                    Text(summaryText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if asNeededIntakes.isEmpty == false {
                        HStack(spacing: 6) {
                            ForEach(asNeededIntakes.prefix(3), id: \.objectID) { intake in
                                Text(intake.timestampValue, format: .dateTime.hour().minute())
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.brandAccent.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color.brandAccent)
                            }
                            if asNeededIntakes.count > 3 {
                                Text("+\(asNeededIntakes.count - 3)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.brandAccent.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.brandAccent)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Medications")
        .accessibilityHint(isExpanded ? "Hide logged doses" : "Show logged doses")
    }
}

private struct MedicationIntakeSummaryRow: View {
    let intake: MedicationIntake

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(intake.medication?.name ?? "Medication")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)

                VStack(alignment: .leading, spacing: 2) {
                    if let useCase = intake.medication?.useCaseLabel {
                        Text(useCase)
                            .font(.footnote)
                            .foregroundStyle(Color.brandAccent)
                    }

                    let details = detailStrings()
                    if details.isEmpty == false {
                        Text(details.joined(separator: " • "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(intake.timestampValue, format: .dateTime.hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(intake.originDisplayName)
                    .font(.caption.bold())
                    .foregroundStyle(Color.brandAccent)
            }
        }
        .padding(.vertical, 4)
    }

    private func detailStrings() -> [String] {
        var components: [String] = []

        if let scheduleLabel = intake.schedule?.label, scheduleLabel.isEmpty == false {
            components.append(scheduleLabel)
        }

        if let amount = intake.amountValue {
            let formatted = MedicationIntakeSummaryRow.numberFormatter.string(from: amount.nsDecimalNumber) ?? "\(amount)"
            if let unit = intake.unit, unit.isEmpty == false {
                components.append("\(formatted) \(unit)")
            } else {
                components.append(formatted)
            }
        } else if let unit = intake.unit, unit.isEmpty == false {
            components.append(unit)
        }

        return components
    }
}
