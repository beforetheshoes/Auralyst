import Foundation
import SwiftUI
import ComposableArchitecture

struct MedicationEditorView: View {
    let store: StoreOf<MedicationEditorFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                Form {
                    medicationDetailsSection(viewStore: viewStore)

                    if !viewStore.isAsNeeded {
                        scheduleSection(viewStore: viewStore)
                    }

                    if viewStore.medicationID != nil {
                        deleteSection(viewStore: viewStore)
                    }
                }
            }
            .navigationTitle(viewStore.medicationID == nil ? "Add Medication" : "Edit Medication")
            .inlineNavigationTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { viewStore.send(.saveTapped) }
                        .disabled(viewStore.name.isEmpty || viewStore.isSaving)
                }
            }
            .task { viewStore.send(.task) }
            .confirmationDialog(
                "Delete Medication?",
                isPresented: viewStore.binding(
                    get: \.showDeleteConfirmation,
                    send: { .binding(.set(\.showDeleteConfirmation, $0)) }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { viewStore.send(.deleteConfirmed) }
                Button("Cancel", role: .cancel) { viewStore.send(.binding(.set(\.showDeleteConfirmation, false))) }
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
            .onChange(of: viewStore.didFinish) { _, finished in
                guard finished else { return }
                viewStore.send(.clearDidFinish)
                dismiss()
            }
        }
    }

    private func medicationDetailsSection(viewStore: ViewStore<MedicationEditorFeature.State, MedicationEditorFeature.Action>) -> some View {
        Section("Medication Details") {
            TextField("Name", text: viewStore.binding(get: \.name, send: { .binding(.set(\.name, $0)) }))
            Toggle("As Needed", isOn: viewStore.binding(get: \.isAsNeeded, send: { .binding(.set(\.isAsNeeded, $0)) }))
                .toggleStyle(.switch)
            TextField("Default Amount", text: viewStore.binding(get: \.defaultAmount, send: { .binding(.set(\.defaultAmount, $0)) }))
                .decimalPadKeyboard()
            TextField("Unit (e.g., mg, ml)", text: viewStore.binding(get: \.defaultUnit, send: { .binding(.set(\.defaultUnit, $0)) }))
            TextField("Use Case (e.g., pain, sleep)", text: viewStore.binding(get: \.useCase, send: { .binding(.set(\.useCase, $0)) }))
            TextField("Notes", text: viewStore.binding(get: \.notes, send: { .binding(.set(\.notes, $0)) }), axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private func scheduleSection(viewStore: ViewStore<MedicationEditorFeature.State, MedicationEditorFeature.Action>) -> some View {
        Section("Schedule") {
            if viewStore.scheduleDrafts.isEmpty {
                Text("Add one or more daily doses with time and amount.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(
                viewStore.binding(
                    get: \.scheduleDrafts,
                    send: { .binding(.set(\.scheduleDrafts, $0)) }
                )
            ) { $draft in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        labelField($draft.label)

                        Spacer()

                        Button(role: .destructive) {
                            viewStore.send(.removeDose(draft.id))
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

            Button(action: { viewStore.send(.addDoseTapped) }) {
                Label("Add Dose", systemImage: "plus")
            }
        }
    }

    private func deleteSection(viewStore: ViewStore<MedicationEditorFeature.State, MedicationEditorFeature.Action>) -> some View {
        Section {
            Button(role: .destructive) {
                viewStore.send(.deleteTapped)
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
