import SwiftUI
@preconcurrency import SQLiteData
import ComposableArchitecture

struct JournalEntriesView: View {
    let journal: SQLiteJournal
    let onAddEntry: () -> Void
    let onShare: () -> Void
    let onExport: () -> Void
    let onImport: () -> Void
    @StateObject private var quickLogStore: StoreOf<MedicationQuickLogFeature>

    // Fetch entries and models for this specific journal
    @FetchAll var entries: [SQLiteSymptomEntry]
    @FetchAll var medications: [SQLiteMedication]
    @FetchAll var medicationIntakes: [SQLiteMedicationIntake]

    struct AsNeededPresentation: Identifiable {
        let medication: SQLiteMedication
        let selectedDate: Date

        var id: UUID { medication.id }
    }

    enum ActiveSheet: Identifiable {
        case medicationManager
        case asNeeded(AsNeededPresentation)

        var id: String {
            switch self {
            case .medicationManager:
                return "medicationManager"
            case .asNeeded(let presentation):
                return "asNeeded-\(presentation.medication.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    init(
        journal: SQLiteJournal,
        onAddEntry: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onImport: @escaping () -> Void
    ) {
        self.journal = journal
        self.onAddEntry = onAddEntry
        self.onShare = onShare
        self.onExport = onExport
        self.onImport = onImport
        self._quickLogStore = StateObject(
            wrappedValue: Store(initialState: MedicationQuickLogFeature.State(journalID: journal.id)) {
                MedicationQuickLogFeature()
            }
        )

        // Filter entries and medications for this journal
        self._entries = FetchAll(SQLiteSymptomEntry.where { $0.journalID.eq(journal.id) })
        self._medications = FetchAll(SQLiteMedication.where { $0.journalID.eq(journal.id) })
        self._medicationIntakes = FetchAll(
            SQLiteMedicationIntake.where {
                $0.medicationID.in(
                    SQLiteMedication
                        .select { $0.id }
                        .where { $0.journalID.eq(journal.id) }
                )
            }
        )
    }

    var body: some View {
        List {
            // Quick log meds from home
            MedicationQuickLogSection(
                store: quickLogStore,
                manageAction: { activeSheet = .medicationManager },
                loggingError: nil,
                presentAsNeeded: { medication, date in
                    activeSheet = .asNeeded(
                        AsNeededPresentation(
                            medication: medication,
                            selectedDate: date
                        )
                    )
                }
            )

            // Days list (symptoms + meds per day)
            Section("Recent Days") {
                ForEach(dayKeys, id: \.self) { day in
                    NavigationLink {
                        DayDetailView(
                            journal: journal,
                            date: day,
                            entries: entriesByDay[day] ?? [],
                            intakes: intakesByDay[day] ?? [],
                            medicationsByID: medicationsByID
                        )
                    } label: {
                        DaySummaryRow(
                            date: day,
                            entries: entriesByDay[day] ?? [],
                            intakes: intakesByDay[day] ?? [],
                            medicationsByID: medicationsByID
                        )
                    }
                }
            }
        }
        .onChange(of: medications) { _, _ in
            quickLogStore.send(.refreshRequested)
        }
        .onChange(of: medicationIntakes) { _, _ in
            quickLogStore.send(.refreshRequested)
        }
        .task(id: journal.id) {
            quickLogStore.send(.task)
        }
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add Entry", action: onAddEntry)
                Menu {
                    Button("Share Journal", action: onShare)
                    Button("Export Data", action: onExport)
                    Button("Import Data", action: onImport)
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(
            item: $activeSheet,
            onDismiss: { activeSheet = nil },
            content: { sheet in
                switch sheet {
                case .medicationManager:
                    MedicationsView(
                        journal: journal,
                        store: Store(initialState: MedicationsFeature.State(journal: journal)) {
                            MedicationsFeature()
                        }
                    )
                case .asNeeded(let presentation):
                    AsNeededIntakeView(
                        store: Store(
                            initialState: AsNeededIntakeFeature.State(
                                medication: presentation.medication,
                                defaultDate: presentation.selectedDate
                            )
                        ) {
                            AsNeededIntakeFeature()
                        }
                    )
                }
            }
        )
    }

    // MARK: - Grouping Helpers

    private var calendar: Calendar { Calendar.current }

    private var medicationsByID: [UUID: SQLiteMedication] {
        Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
    }

    private var entriesByDay: [Date: [SQLiteSymptomEntry]] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
    }

    private var intakesByDay: [Date: [SQLiteMedicationIntake]] {
        Dictionary(grouping: medicationIntakes) { calendar.startOfDay(for: $0.timestamp) }
    }

    private var dayKeys: [Date] {
        let entryDays = Set(entriesByDay.keys)
        let intakeDays = Set(intakesByDay.keys)
        return Array(entryDays.union(intakeDays)).sorted(by: >)
    }
}

// MARK: - Rows & Detail Screens

private struct DaySummaryRow: View {
    let date: Date
    let entries: [SQLiteSymptomEntry]
    let intakes: [SQLiteMedicationIntake]
    let medicationsByID: [UUID: SQLiteMedication]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(date, format: .dateTime.year().month().day())
                    .font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    CountChip(system: "waveform.path.ecg", text: "\(entries.count)")
                    CountChip(system: "pills.fill", text: "\(intakes.count)")
                }
            }

            // Quick preview line(s)
            if let preview = previewLine {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var previewLine: String? {
        var parts: [String] = []
        if let entry = entries.first {
            if let note = entry.note, !note.isEmpty {
                parts.append(note)
            } else {
                parts.append("Severity: \(entry.severity)")
            }
        }
        if !intakes.isEmpty {
            let names: [String] = intakes.prefix(3).compactMap { medicationsByID[$0.medicationID]?.name }
            if !names.isEmpty { parts.append("Meds: " + names.joined(separator: ", ")) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

private struct CountChip: View {
    let system: String
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: system)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial)
        .clipShape(Capsule())
    }
}

private struct DayDetailView: View {
    let journal: SQLiteJournal
    let date: Date
    let entries: [SQLiteSymptomEntry]
    let intakes: [SQLiteMedicationIntake]
    let medicationsByID: [UUID: SQLiteMedication]

    @State private var editingEntryID: UUID?
    @State private var currentIntakes: [SQLiteMedicationIntake] = []

    var body: some View {
        List {
            Section(header: Text("Symptoms")) {
                if entries.isEmpty {
                    Text("No symptom entries logged.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        NavigationLink {
                            SymptomEntryEditorView(entryID: entry.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Severity: \(entry.severity)")
                                        .font(.caption)
                                }
                                if let note = entry.note, !note.isEmpty {
                                    Text(note)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Section(header: Text("Medications")) {
                if currentIntakes.isEmpty {
                    Text("No medications logged.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(currentIntakes) { intake in
                        let med = medicationsByID[intake.medicationID]
                        NavigationLink {
                            MedicationIntakeEditorView(
                                store: Store(initialState: MedicationIntakeEditorFeature.State(intakeID: intake.id)) {
                                    MedicationIntakeEditorFeature()
                                }
                            )
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(med?.name ?? "Medication")
                                        .font(.subheadline.weight(.semibold))
                                    HStack(spacing: 6) {
                                        Text(intake.timestamp, style: .time)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let amount = intake.amount, let unit = intake.unit {
                                            Text("\(amount.cleanAmount) \(unit)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if let notes = intake.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .inlineNavigationTitleDisplay()
        .onAppear {
            currentIntakes = intakes
        }
        .onChange(of: intakes) { _, newValue in
            currentIntakes = newValue
        }
    }

}

#Preview {
    withPreviewDataStore {
        JournalEntriesView(
            journal: SQLiteJournal(),
            onAddEntry: {},
            onShare: {},
            onExport: {},
            onImport: {}
        )
    }
}
