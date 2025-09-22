import SQLiteData
import SwiftUI

struct EntryDetailView: View {
    let entry: SQLiteSymptomEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore

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
                        .foregroundColor(.secondary)

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
                            .foregroundColor(.red)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Entry Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Note") {
                        showingAddCollaboratorNote = true
                    }
                }
            }
        .sheet(isPresented: $showingAddCollaboratorNote) {
            AddCollaboratorNoteView(entryID: entry.id)
                .environment(dataStore)
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
    withPreviewDataStore { dataStore in
        let journal = dataStore.createJournal()
        let entry = try! dataStore.createSymptomEntry(for: journal, severity: 5, note: "Test entry")

        EntryDetailView(entry: entry)
    }
}
