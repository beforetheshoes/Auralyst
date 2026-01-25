@preconcurrency import SQLiteData
import SwiftUI
import ComposableArchitecture
import Dependencies

struct AddCollaboratorNoteView: View {
    let store: StoreOf<AddCollaboratorNoteFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                Form {
                    Section("Note") {
                        TextEditor(
                            text: viewStore.binding(
                                get: \.text,
                                send: { .binding(.set(\.text, $0)) }
                            )
                        )
                        .frame(minHeight: 140)
                    }

                    Section("Attribution") {
                        TextField(
                            "Author (optional)",
                            text: viewStore.binding(
                                get: \.authorName,
                                send: { .binding(.set(\.authorName, $0)) }
                            )
                        )
                    }
                }
                .navigationTitle("Collaborator Note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { viewStore.send(.saveTapped) }
                            .disabled(viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewStore.isSaving)
                    }
                }
                .alert(
                    "Unable to Save",
                    isPresented: viewStore.binding(
                        get: { $0.errorMessage != nil },
                        send: { _ in .clearError }
                    )
                ) {
                    Button("OK") { viewStore.send(.clearError) }
                } message: {
                    Text(viewStore.errorMessage ?? "")
                }
                .onChange(of: viewStore.didSave) { _, didSave in
                    guard didSave else { return }
                    viewStore.send(.clearDidSave)
                    dismiss()
                }
            }
        }
    }
}

#Preview("Collaborator Note") {
    withPreviewDataStore {
        let databaseClient = DependencyValues._current.databaseClient
        let journal = databaseClient.createJournal()
        let entry = try! databaseClient.createSymptomEntry(journal, 5, nil, .now, false)

        AddCollaboratorNoteView(
            store: Store(initialState: AddCollaboratorNoteFeature.State(entryID: entry.id)) {
                AddCollaboratorNoteFeature()
            }
        )
    }
}
