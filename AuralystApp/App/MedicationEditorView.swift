import Foundation
import SwiftUI
import ComposableArchitecture

struct MedicationEditorView: View {
    @Bindable var store: StoreOf<MedicationEditorFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                medicationDetailsSection()

                if !store.isAsNeeded {
                    scheduleSection()
                }

                if store.medicationID != nil {
                    deleteSection()
                }
            }
        }
        .navigationTitle(store.medicationID == nil ? "Add Medication" : "Edit Medication")
        .inlineNavigationTitleDisplay()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { store.send(.saveTapped) }
                    .disabled(store.name.isEmpty || store.isSaving)
            }
        }
        .task { store.send(.task) }
        .confirmationDialog(
            "Delete Medication?",
            isPresented: $store.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { store.send(.deleteConfirmed) }
            Button("Cancel", role: .cancel) { store.send(.binding(.set(\.showDeleteConfirmation, false))) }
        }
        .alert(
            "Unable to Save",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in store.send(.clearError) })
        ) {
            Button("OK") { store.send(.clearError) }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: store.didFinish) { _, finished in
            guard finished else { return }
            store.send(.clearDidFinish)
            dismiss()
        }
    }

    private func medicationDetailsSection() -> some View {
        Section("Medication Details") {
            TextField("Name", text: $store.name)
            Toggle("As Needed", isOn: $store.isAsNeeded)
                .toggleStyle(.switch)
            TextField("Default Amount", text: $store.defaultAmount)
                .decimalPadKeyboard()
            TextField("Unit (e.g., mg, ml)", text: $store.defaultUnit)
            TextField("Use Case (e.g., pain, sleep)", text: $store.useCase)
            TextField("Notes", text: $store.notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private func scheduleSection() -> some View {
        Section("Schedule") {
            if store.scheduleDrafts.isEmpty {
                Text("Add one or more daily doses with time and amount.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($store.scheduleDrafts) { $draft in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        labelField($draft.label)

                        Spacer()

                        Button(role: .destructive) {
                            store.send(.removeDose(draft.id))
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        TextField("Amount", text: $draft.amount)
                            .decimalPadKeyboard()
                            .frame(maxWidth: 120)
                        TextField("Unit", text: $draft.unit)
                            .frame(maxWidth: 80)
                        Spacer()
                        DatePicker("Time", selection: $draft.time, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                    }
                }
                .padding(.vertical, 4)
            }

            Button(
                action: { store.send(.addDoseTapped) },
                label: { Label("Add Dose", systemImage: "plus") }
            )
        }
    }

    private func deleteSection() -> some View {
        Section {
            Button(role: .destructive) {
                store.send(.deleteTapped)
            } label: {
                Text("Delete Medication")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func labelField(_ binding: Binding<String>) -> some View {
        #if os(iOS)
        TextField("Label (e.g., Morning)", text: binding)
            .textInputAutocapitalization(.words)
        #else
        TextField("Label (e.g., Morning)", text: binding)
        #endif
    }

}

#Preview {
    withPreviewDataStore {
        MedicationEditorView(
            store: Store(initialState: MedicationEditorFeature.State(journalID: UUID())) {
                MedicationEditorFeature()
            }
        )
    }
}
