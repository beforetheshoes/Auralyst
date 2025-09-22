import SQLiteData
import Observation
import SwiftUI

struct AddCollaboratorNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore

    let entryID: UUID

    @State private var form = CollaboratorNoteFormModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextEditor(text: $form.text)
                        .frame(minHeight: 140)
                }

                Section("Attribution") {
                    TextField("Author (optional)", text: $form.authorName)
                }
            }
            .navigationTitle("Collaborator Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNote() }
                        .disabled(form.isSaveDisabled)
                }
            }
        }
    }

    private func saveNote() {
        let trimmed = form.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let author = form.authorName.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                guard let entry = dataStore.fetchSymptomEntry(id: entryID) else {
                    assertionFailure("Missing entry for collaborator note")
                    return
                }

                _ = try dataStore.createCollaboratorNote(
                    for: dataStore.fetchJournal(id: entry.journalID)!,
                    entry: entry,
                    authorName: author.isEmpty ? nil : author,
                    text: trimmed
                )

                await MainActor.run {
                    dismiss()
                }
            } catch {
                assertionFailure("Failed to save collaborator note: \(error)")
            }
        }
    }
}

@Observable
final class CollaboratorNoteFormModel {
    var text: String = ""
    var authorName: String = ""

    var isSaveDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview("Collaborator Note") {
    withPreviewDataStore { dataStore in
        let journal = dataStore.createJournal()
        let entry = try! dataStore.createSymptomEntry(for: journal, severity: 5)

        AddCollaboratorNoteView(entryID: entry.id)
    }
}
