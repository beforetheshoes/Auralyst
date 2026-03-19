@preconcurrency import SQLiteData
import SwiftUI
import ComposableArchitecture
import Dependencies

struct AddCollaboratorNoteView: View {
    @Bindable var store: StoreOf<AddCollaboratorNoteFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextEditor(text: $store.text)
                        .frame(minHeight: 140)
                }

                Section("Attribution") {
                    TextField("Author (optional)", text: $store.authorName)
                }
            }
            .navigationTitle("Collaborator Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.send(.saveTapped) }
                        .disabled(store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSaving)
                }
            }
            .alert(
                "Unable to Save",
                isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in store.send(.clearError) })
            ) {
                Button("OK") { store.send(.clearError) }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .onChange(of: store.didSave) { _, didSave in
                guard didSave else { return }
                store.send(.clearDidSave)
                dismiss()
            }
        }
    }
}

#Preview("Collaborator Note") {
    withPreviewDataStore {
        let databaseClient = DependencyValues._current.databaseClient
        let journal = databaseClient.createJournal()
        let entry = previewValue { try databaseClient.createSymptomEntry(journal, 5, nil, .now, false) }

        AddCollaboratorNoteView(
            store: Store(initialState: AddCollaboratorNoteFeature.State(entryID: entry.id)) {
                AddCollaboratorNoteFeature()
            }
        )
    }
}
