import SwiftUI
import SQLiteData
import Dependencies

struct JournalEntriesView: View {
    let journal: SQLiteJournal
    let onAddEntry: () -> Void
    let onShare: () -> Void
    let onExport: () -> Void

    // Fetch entries and models for this specific journal
    @FetchAll var entries: [SQLiteSymptomEntry]
    @FetchAll var medications: [SQLiteMedication]
    @FetchAll(SQLiteMedicationIntake.all) var medicationIntakes

    @State private var showingMedicationManager = false

    init(
        journal: SQLiteJournal,
        onAddEntry: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onExport: @escaping () -> Void
    ) {
        self.journal = journal
        self.onAddEntry = onAddEntry
        self.onShare = onShare
        self.onExport = onExport

        // Filter entries and medications for this journal
        self._entries = FetchAll(SQLiteSymptomEntry.where { $0.journalID == journal.id })
        self._medications = FetchAll(SQLiteMedication.where { $0.journalID == journal.id })
    }

    var body: some View {
        List {
            // Quick log meds from home
            MedicationQuickLogSection(
                journalID: journal.id,
                manageAction: { showingMedicationManager = true },
                loggingError: nil
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
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add Entry", action: onAddEntry)
                Menu {
                    Button("Share Journal", action: onShare)
                    Button("Export Data", action: onExport)
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingMedicationManager) {
            MedicationsView(journal: journal)
        }
    }

    // MARK: - Grouping Helpers

    private var calendar: Calendar { Calendar.current }

    private var medicationsByID: [UUID: SQLiteMedication] {
        Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
    }

    private var entriesByDay: [Date: [SQLiteSymptomEntry]] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
    }

    private var relevantIntakes: [SQLiteMedicationIntake] {
        let medIDs = Set(medications.map { $0.id })
        return medicationIntakes.filter { medIDs.contains($0.medicationID) }
    }

    private var intakesByDay: [Date: [SQLiteMedicationIntake]] {
        Dictionary(grouping: relevantIntakes) { calendar.startOfDay(for: $0.timestamp) }
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
        if let e = entries.first {
            if let note = e.note, !note.isEmpty { parts.append(note) }
            else { parts.append("Severity: \(e.severity)") }
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
                if intakes.isEmpty {
                    Text("No medications logged.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(intakes) { intake in
                        let med = medicationsByID[intake.medicationID]
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(med?.name ?? "Medication")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
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
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SymptomEntryEditorView: View {
    let entryID: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    @State private var timestamp: Date = .now
    @State private var overallSeverity: Int = 0
    @State private var isMenstruating: Bool = false
    @State private var note: String = ""
    @State private var originalEntry: SQLiteSymptomEntry?

    var body: some View {
        Form {
            Section("Severity") {
                HStack {
                    Text("Overall")
                    Spacer()
                    Text("\(overallSeverity)")
                        .foregroundStyle(Color.brandAccent)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(overallSeverity) },
                    set: { overallSeverity = Int($0.rounded()) }
                ), in: 0...10, step: 1)
            }

            Section("Menstruation") {
                Toggle("Menstruating", isOn: $isMenstruating)
                    .toggleStyle(.switch)
            }

            Section("Note") {
                TextEditor(text: $note)
                    .frame(minHeight: 120)
            }

            Section("Timestamp") {
                DatePicker("Logged At", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
            }
        }
        .navigationTitle("Edit Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        @Dependency(\.defaultDatabase) var database
        do {
            if let entry = try database.read({ db in try SQLiteSymptomEntry.find(entryID).fetchOne(db) }) {
                originalEntry = entry
                timestamp = entry.timestamp
                overallSeverity = Int(entry.severity)
                isMenstruating = entry.isMenstruating ?? false
                note = entry.note ?? ""
            }
        } catch {
            print("Failed to load entry: \(error)")
        }
    }

    private func save() {
        @Dependency(\.defaultDatabase) var database
        let noteParam = note.isEmpty ? nil : note
        guard let entry = originalEntry else {
            assertionFailure("Attempting to save a missing symptom entry")
            return
        }

        let updatedEntry = SQLiteSymptomEntry(
            id: entry.id,
            timestamp: timestamp,
            journalID: entry.journalID,
            severity: Int16(overallSeverity),
            headache: entry.headache,
            nausea: entry.nausea,
            anxiety: entry.anxiety,
            isMenstruating: isMenstruating,
            note: noteParam,
            sentimentLabel: entry.sentimentLabel,
            sentimentScore: entry.sentimentScore
        )

        do {
            try database.write { db in
                try SQLiteSymptomEntry.update(updatedEntry).execute(db)
            }
            dismiss()
        } catch {
            print("Failed to save entry: \(error)")
        }
    }
}

private extension Double {
    var cleanAmount: String {
        if floor(self) == self { return String(Int(self)) }
        return String(self)
    }
}

#Preview {
    withPreviewDataStore { _ in
        JournalEntriesView(
            journal: SQLiteJournal(),
            onAddEntry: {},
            onShare: {},
            onExport: {}
        )
    }
}
