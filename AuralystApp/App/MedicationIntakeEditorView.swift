import SwiftUI
import ComposableArchitecture
import Dependencies

struct MedicationIntakeEditorView: View {
    let store: StoreOf<MedicationIntakeEditorFeature>
    @Environment(\.dismiss) private var dismiss

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Group {
                if viewStore.intake != nil {
                    Form {
                        Section("Medication") {
                            DatePicker(
                                "Logged",
                                selection: viewStore.binding(
                                    get: \.timestamp,
                                    send: { .binding(.set(\.timestamp, $0)) }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            TextField(
                                "Amount",
                                value: viewStore.binding(
                                    get: { $0.amountValue },
                                    send: { .binding(.set(\.amountValue, $0)) }
                                ),
                                formatter: numberFormatter
                            )
                            .decimalPadKeyboard()
                            TextField(
                                "Unit",
                                text: viewStore.binding(
                                    get: \.unit,
                                    send: { .binding(.set(\.unit, $0)) }
                                )
                            )
                            TextField(
                                "Notes",
                                text: viewStore.binding(
                                    get: \.notes,
                                    send: { .binding(.set(\.notes, $0)) }
                                ),
                                axis: .vertical
                            )
                            .lineLimit(2...6)
                        }

                        Section {
                            Button("Delete Dose", role: .destructive) {
                                viewStore.send(.deleteTapped)
                            }
                        }
                    }
                    .navigationTitle("Edit Dose")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", action: { dismiss() })
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save", action: { viewStore.send(.saveTapped) })
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading dose…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task { viewStore.send(.task) }
            .confirmationDialog(
                "Delete Dose?",
                isPresented: viewStore.binding(
                    get: \.showDeleteConfirmation,
                    send: { .binding(.set(\.showDeleteConfirmation, $0)) }
                )
            ) {
                Button("Delete", role: .destructive) {
                    viewStore.send(.deleteConfirmed)
                }
            } message: {
                Text("This removes the logged medication permanently.")
            }
            .alert(
                "Unable to Save",
                isPresented: viewStore.binding(
                    get: { $0.errorMessage != nil },
                    send: { _ in .clearError }
                )
            ) {
                Button("OK", role: .cancel) { viewStore.send(.clearError) }
            } message: {
                Text(viewStore.errorMessage ?? "")
            }
            .onChange(of: viewStore.didFinish) { _, finished in
                guard finished else { return }
                viewStore.send(.clearDidFinish)
                dismiss()
            }
        }
    }
}

#Preview("Medication Intake Editor") {
    withPreviewDataStore {
        let databaseClient = DependencyValues._current.databaseClient
        let journal = databaseClient.createJournal()
        let medication = databaseClient.createMedication(journal, "Ibuprofen", nil, nil)
        let intake = try! databaseClient.createMedicationIntake(medication, 200, "mg")

        NavigationStack {
            MedicationIntakeEditorView(
                store: Store(initialState: MedicationIntakeEditorFeature.State(intakeID: intake.id)) {
                    MedicationIntakeEditorFeature()
                }
            )
        }
    }
}
