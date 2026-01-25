import SwiftUI
import ComposableArchitecture
import Dependencies

struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AddEntryFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                Form {
                    Section("Severity") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Overall")
                                Spacer()
                                Text("\(viewStore.overallSeverity)")
                                    .foregroundStyle(Color.brandAccent)
                                    .monospacedDigit()
                            }
                            Slider(
                                value: viewStore.binding(
                                    get: { Double($0.overallSeverity) },
                                    send: { .binding(.set(\.overallSeverity, Int($0.rounded()))) }
                                ),
                                in: 0...10,
                                step: 1
                            )
                        }
                    }

                    Section("Menstruation") {
                        Toggle(
                            "Menstruating",
                            isOn: viewStore.binding(
                                get: \.isMenstruating,
                                send: { .binding(.set(\.isMenstruating, $0)) }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    Section("Note") {
                        TextEditor(
                            text: viewStore.binding(
                                get: \.note,
                                send: { .binding(.set(\.note, $0)) }
                            )
                        )
                        .frame(minHeight: 120)
                    }

                    Section("Timestamp") {
                        DatePicker(
                            "Logged At",
                            selection: viewStore.binding(
                                get: \.timestamp,
                                send: { .binding(.set(\.timestamp, $0)) }
                            ),
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
                        Button("Save") { viewStore.send(.saveTapped) }
                            .disabled(viewStore.overallSeverity < 0 || viewStore.overallSeverity > 10 || viewStore.isSaving)
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
