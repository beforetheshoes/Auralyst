import SwiftUI
@preconcurrency import SQLiteData
import ComposableArchitecture

enum EditorMode: Identifiable, Equatable {
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
    let store: StoreOf<MedicationsFeature>
    @Environment(\.dismiss) private var dismiss

    @FetchAll var medications: [SQLiteMedication]

    init(journal: SQLiteJournal, store: StoreOf<MedicationsFeature>) {
        self.store = store
        self._medications = FetchAll(SQLiteMedication.where { $0.journalID.eq(journal.id) })
    }

    var body: some View {
        NavigationStack {
            List {
                if medications.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Text("No medications yet")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Text("Add your first medication to start tracking doses and schedules.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical)
                    }
                } else {
                    ForEach(medications) { medication in
                        medicationRow(medication, store: store)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.send(.deleteMedication(medication.id))
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Medications")
            .inlineNavigationTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") { store.send(.addTapped) }
                }
            }
            .sheet(
                item: Binding(
                    get: { store.editorMode },
                    set: { store.send(.setEditorMode($0)) }
                )
            ) { mode in
                switch mode {
                case .create:
                    MedicationEditorView(
                        store: Store(
                            initialState: MedicationEditorFeature.State(journalID: store.journal.id)
                        ) {
                            MedicationEditorFeature()
                        }
                    )
                case .edit(let medicationID):
                    MedicationEditorView(
                        store: Store(
                            initialState: MedicationEditorFeature.State(
                                journalID: store.journal.id,
                                medicationID: medicationID
                            )
                        ) {
                            MedicationEditorFeature()
                        }
                    )
                }
            }
        }
    }
}

@MainActor
private func medicationRow(
    _ medication: SQLiteMedication,
    store: StoreOf<MedicationsFeature>
) -> some View {
    HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
            Text(medication.name)
                .font(.headline)

            // Amount + unit
            if let amount = medication.defaultAmount, let unit = medication.defaultUnit {
                Text("\(amount.description) \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Type: As Needed or Scheduled
            Text((medication.isAsNeeded ?? false) ? "As Needed" : "Scheduled")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Notes if present
            if let notes = medication.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }

        Spacer()

        Button("Edit") {
            store.send(.editTapped(medication.id))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    .padding(.vertical, 2)
}

// MedicationEditorView is now in its own file

#Preview {
    withPreviewDataStore {
        let journal = SQLiteJournal()
        MedicationsView(
            journal: journal,
            store: Store(initialState: MedicationsFeature.State(journal: journal)) {
                MedicationsFeature()
            }
        )
    }
}
