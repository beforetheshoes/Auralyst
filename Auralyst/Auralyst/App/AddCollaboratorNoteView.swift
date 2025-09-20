import CoreData
import Observation
import SwiftUI

struct AddCollaboratorNoteView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entryID: NSManagedObjectID

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

        context.perform {
            guard let entry = try? context.existingObject(with: entryID) as? SymptomEntry else {
                assertionFailure("Missing entry for collaborator note")
                return
            }

            let note = CollaboratorNote(context: context)
            note.id = UUID()
            note.timestamp = Date()
            note.text = trimmed
            note.authorName = author.isEmpty ? nil : author
            note.entryRef = entry
            note.journal = entry.journal

            do {
                try context.save()
                Task { @MainActor in
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
    let controller = PersistenceController.preview
    let context = controller.container.viewContext
    PreviewSeed.populateIfNeeded(context: context)
    let request = SymptomEntry.fetchRequest()
    request.fetchLimit = 1
    let entry = try? context.fetch(request).first
    return Group {
        if let entry {
            AddCollaboratorNoteView(entryID: entry.objectID)
                .environment(\.managedObjectContext, context)
        }
    }
}
