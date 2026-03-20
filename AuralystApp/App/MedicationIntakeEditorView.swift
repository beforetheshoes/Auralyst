import SwiftUI
import ComposableArchitecture
import Dependencies

struct MedicationIntakeEditorView: View {
    @Bindable var store: StoreOf<MedicationIntakeEditorFeature>
    @Environment(\.dismiss) private var dismiss

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        Group {
            if store.intake != nil {
                Form {
                    Section("Medication") {
                        DatePicker(
                            "Logged",
                            selection: $store.timestamp,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        TextField(
                            "Amount",
                            value: $store.amountValue,
                            formatter: numberFormatter
                        )
                        .decimalPadKeyboard()
                        TextField("Unit", text: $store.unit)
                        TextField("Notes", text: $store.notes, axis: .vertical)
                            .lineLimit(2...6)
                    }

                    Section {
                        Button("Delete Dose", role: .destructive) {
                            store.send(.deleteTapped)
                        }
                    }
                }
                .navigationTitle("Edit Dose")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: { dismiss() })
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: { store.send(.saveTapped) })
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
        .task { store.send(.task) }
        .confirmationDialog(
            "Delete Dose?",
            isPresented: $store.showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                store.send(.deleteConfirmed)
            }
        } message: {
            Text("This removes the logged medication permanently.")
        }
        .alert(
            "Unable to Save",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in store.send(.clearError) })
        ) {
            Button("OK", role: .cancel) { store.send(.clearError) }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: store.didFinish) { _, finished in
            guard finished else { return }
            store.send(.clearDidFinish)
            dismiss()
        }
    }
}

#Preview("Medication Intake Editor") {
    withPreviewDataStore {
        let databaseClient = DependencyValues._current.databaseClient
        let journal = previewValue { try databaseClient.createJournal() }
        let medication = databaseClient.createMedication(journal, "Ibuprofen", nil, nil)
        let intake = previewValue { try databaseClient.createMedicationIntake(medication, 200, "mg") }

        NavigationStack {
            MedicationIntakeEditorView(
                store: Store(initialState: MedicationIntakeEditorFeature.State(intakeID: intake.id)) {
                    MedicationIntakeEditorFeature()
                }
            )
        }
    }
}
