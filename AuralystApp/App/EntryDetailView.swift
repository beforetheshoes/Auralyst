@preconcurrency import SQLiteData
import SwiftUI
import Dependencies
import ComposableArchitecture

struct EntryDetailView: View {
    let entry: SQLiteSymptomEntry

    @Environment(\.dismiss) private var dismiss

    @State private var showingAddCollaboratorNote = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Symptom Entry")
                        .font(.largeTitle)
                        .bold()

                    Text(entry.timestamp, format: .dateTime)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if let note = entry.note {
                        Text(note)
                            .font(.body)
                    }

                    // Show severity metrics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Severity Levels")
                            .font(.headline)

                        severityRow("Overall", value: entry.severity)

                        if let headache = entry.headache {
                            severityRow("Headache", value: headache)
                        }

                        if let nausea = entry.nausea {
                            severityRow("Nausea", value: nausea)
                        }

                        if let anxiety = entry.anxiety {
                            severityRow("Anxiety", value: anxiety)
                        }
                    }

                    if entry.isMenstruating == true {
                        Label("Menstruating", systemImage: "circle.fill")
                            .foregroundStyle(.red)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Entry Details")
            .inlineNavigationTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Note") {
                        showingAddCollaboratorNote = true
                    }
                }
            }
        .sheet(isPresented: $showingAddCollaboratorNote) {
            AddCollaboratorNoteView(
                store: Store(initialState: AddCollaboratorNoteFeature.State(entryID: entry.id)) {
                    AddCollaboratorNoteFeature()
                }
            )
        }
    }
    }

    private func severityRow(_ label: String, value: Int16) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)/10")
                .bold()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    withPreviewDataStore {
        let databaseClient = DependencyValues._current.databaseClient
        let journal = databaseClient.createJournal()
        let entry = previewValue { try databaseClient.createSymptomEntry(journal, 5, "Test entry", .now, false) }

        EntryDetailView(entry: entry)
    }
}
