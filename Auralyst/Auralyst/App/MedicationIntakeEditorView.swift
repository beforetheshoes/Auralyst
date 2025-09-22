import SQLiteData
import SwiftUI

struct MedicationIntakeEditorView: View {
    let intakeID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore

    @State private var intake: SQLiteMedicationIntake?
    @State private var amountValue: Double?
    @State private var unit: String = ""
    @State private var notes: String = ""
    @State private var timestamp: Date = Date()
    @State private var didLoad = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        Group {
            if intake != nil {
                Form {
                    Section("Medication") {
                        DatePicker(
                            "Logged",
                            selection: $timestamp,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        TextField("Amount", value: $amountValue, formatter: numberFormatter)
                            .keyboardType(.decimalPad)
                        TextField("Unit", text: $unit)
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(2...6)
                    }

                    Section {
                        Button("Delete Dose", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
                .navigationTitle("Edit Dose")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: { dismiss() })
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
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
        .onAppear(perform: loadIfNeeded)
        .confirmationDialog(
            "Delete Dose?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("This removes the logged medication permanently.")
        }
        .alert("Unable to Save", isPresented: Binding(get: { errorMessage != nil }, set: { if $0 == false { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        // Load intake from dataStore
        intake = dataStore.fetchMedicationIntake(id: intakeID)

        if let intake = intake {
            amountValue = intake.amount
            unit = intake.unit ?? ""
            notes = intake.notes ?? ""
            timestamp = intake.timestamp
        }
    }

    private func save() {
        guard let intake else { return }

        Task {
            do {
                let updatedIntake = intake.mergingEditableFields(
                    amount: amountValue,
                    unit: unit.isEmpty ? nil : unit,
                    timestamp: timestamp,
                    notes: notes.isEmpty ? nil : notes
                )

                try dataStore.updateMedicationIntake(updatedIntake)

                await MainActor.run {
                    NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
                    self.intake = updatedIntake
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func delete() {
        guard let intake else { return }

        Task {
            do {
                try dataStore.deleteMedicationIntake(intake)

                await MainActor.run {
                    NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview("Medication Intake Editor") {
    withPreviewDataStore { dataStore in
        let journal = dataStore.createJournal()
        let medication = dataStore.createMedication(for: journal, name: "Ibuprofen")
        let intake = try! dataStore.createMedicationIntake(for: medication, amount: 200, unit: "mg")

        NavigationStack {
            MedicationIntakeEditorView(intakeID: intake.id)
        }
    }
}
