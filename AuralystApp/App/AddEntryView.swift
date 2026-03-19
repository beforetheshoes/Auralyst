import SwiftUI
import ComposableArchitecture
import Dependencies

struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: StoreOf<AddEntryFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section("Severity") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Overall")
                            Spacer()
                            Text("\(store.overallSeverity)")
                                .foregroundStyle(Color.brandAccent)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(store.overallSeverity) },
                                set: { store.send(.binding(.set(\.overallSeverity, Int($0.rounded())))) }
                            ),
                            in: 0...10,
                            step: 1
                        )
                    }
                }

                Section("Menstruation") {
                    Toggle("Menstruating", isOn: $store.isMenstruating)
                        .toggleStyle(.switch)
                }

                Section("Note") {
                    TextEditor(text: $store.note)
                        .frame(minHeight: 120)
                }

                Section("Timestamp") {
                    DatePicker(
                        "Logged At",
                        selection: $store.timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            .navigationTitle("New Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.send(.saveTapped) }
                        .disabled(store.overallSeverity < 0 || store.overallSeverity > 10 || store.isSaving)
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

#Preview("Add Entry") {
    withPreviewDataStore {
        let journal = DependencyValues._current.databaseClient.createJournal()
        AddEntryView(
            store: Store(initialState: AddEntryFeature.State(journalID: journal.id)) {
                AddEntryFeature()
            }
        )
    }
}
