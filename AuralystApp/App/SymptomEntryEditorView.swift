import ComposableArchitecture
import SwiftUI

struct SymptomEntryEditorView: View {
    @Bindable var store: StoreOf<SymptomEntryEditorFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if store.entry != nil {
                Form {
                    Section("Severity") {
                        HStack {
                            Text("Overall")
                            Spacer()
                            Text("\(store.severity)")
                                .foregroundStyle(Color.brandAccent)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(store.severity) },
                            set: { store.severity = Int($0.rounded()) }
                        ), in: 0...10, step: 1)
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

                    Section {
                        Button("Delete Entry", role: .destructive) {
                            store.send(.deleteTapped)
                        }
                    }
                }
                .navigationTitle("Edit Entry")
                .inlineNavigationTitleDisplay()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { store.send(.saveTapped) }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading entry…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { store.send(.task) }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $store.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                store.send(.deleteConfirmed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the symptom entry."
                + " Linked notes and intakes will be detached."
            )
        }
        .alert(
            "Unable to Save",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { _ in store.send(.clearError) }
            )
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
