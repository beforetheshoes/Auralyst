import Dependencies
import Foundation
@preconcurrency import SQLiteData
import SwiftUI

struct SymptomEntryEditorView: View {
    let entryID: UUID

    @Environment(\.dismiss) private var dismiss
    @Dependency(\.databaseClient) private var databaseClient

    @State private var loaded = false
    @State private var timestamp: Date = .now
    @State private var overallSeverity: Int = 0
    @State private var isMenstruating: Bool = false
    @State private var note: String = ""
    @State private var originalEntry: SQLiteSymptomEntry?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

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
                DatePicker(
                    "Logged At",
                    selection: $timestamp,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Section {
                Button("Delete Entry", role: .destructive) {
                    showDeleteConfirmation = true
                }
                if let deleteErrorMessage {
                    Text(deleteErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Edit Entry")
        .inlineNavigationTitleDisplay()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                delete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the symptom entry."
                + " Linked notes and intakes will be detached."
            )
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        @Dependency(\.defaultDatabase) var database
        do {
            if let entry = try database.read({ db in
                try SQLiteSymptomEntry.find(entryID).fetchOne(db)
            }) {
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
                try SQLiteSymptomEntry
                    .update(updatedEntry).execute(db)
            }
            dismiss()
        } catch {
            print("Failed to save entry: \(error)")
        }
    }

    private func delete() {
        guard let entry = originalEntry else {
            deleteErrorMessage = "Entry could not be loaded."
            return
        }

        do {
            try databaseClient.deleteSymptomEntry(entry.id)
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}
