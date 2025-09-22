import SwiftUI
import SQLiteData
import Dependencies

enum EditorMode: Identifiable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let id): return "edit-\(id)"
        }
    }
}

struct MedicationsView: View {
    let journal: SQLiteJournal
    @Environment(\.dismiss) private var dismiss

    @FetchAll var medications: [SQLiteMedication]

    @State private var showingAddMedication = false
    @State private var medicationToEdit: SQLiteMedication?

    init(journal: SQLiteJournal) {
        self.journal = journal
        self._medications = FetchAll(SQLiteMedication.where { $0.journalID == journal.id })
    }

    @State private var editorMode: EditorMode?

    var body: some View {
        NavigationStack {
            List {
                if medications.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Text("No medications yet")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Text("Add your first medication to start tracking doses and schedules.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical)
                    }
                } else {
                    ForEach(medications) { medication in
                        medicationRow(medication)
                    }
                }
            }
            .navigationTitle("Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") { editorMode = .create }
                }
            }
            .sheet(item: $editorMode) { mode in
                switch mode {
                case .create:
                    MedicationEditorView(journalID: journal.id)
                case .edit(let medicationID):
                    MedicationEditorView(journalID: journal.id, medicationID: medicationID)
                }
            }
        }
    }

    private func medicationRow(_ medication: SQLiteMedication) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .font(.headline)

                // Amount + unit
                if let amount = medication.defaultAmount, let unit = medication.defaultUnit {
                    Text("\(amount.description) \(unit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Type: As Needed or Scheduled
                Text((medication.isAsNeeded ?? false) ? "As Needed" : "Scheduled")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Notes if present
                if let notes = medication.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button("Edit") {
                editorMode = .edit(medication.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

}

// MedicationEditorView is now in its own file

#Preview {
    withPreviewDataStore { _ in
        MedicationsView(journal: SQLiteJournal())
    }
}
