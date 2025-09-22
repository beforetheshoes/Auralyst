import SQLiteData
import Observation
import SwiftUI

struct AddEntryView: View {
    let journalID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore

    @State private var form = EntryFormModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Severity") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Overall")
                            Spacer()
                            Text("\(form.overallSeverity)")
                                .foregroundStyle(Color.brandAccent)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(form.overallSeverity) },
                            set: { form.overallSeverity = Int($0.rounded()) }
                        ), in: 0...10, step: 1)
                    }
                }

                Section("Menstruation") {
                    Toggle("Menstruating", isOn: $form.isMenstruating)
                        .toggleStyle(.switch)
                }

                Section("Note") {
                    TextEditor(text: $form.note)
                        .frame(minHeight: 120)
                }

                Section("Timestamp") {
                    DatePicker("Logged At", selection: $form.timestamp, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("New Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .disabled(form.isSaveDisabled)
                }
            }
        }
    }

    private func saveEntry() {
        Task {
            do {
                guard let journal = dataStore.fetchJournal(id: journalID) else {
                    assertionFailure("Missing journal for new entry")
                    return
                }

                _ = try dataStore.createSymptomEntry(
                    for: journal,
                    severity: Int16(form.overallSeverity),
                    note: form.note.isEmpty ? nil : form.note,
                    timestamp: form.timestamp,
                    isMenstruating: form.isMenstruating
                )

                await MainActor.run {
                    dismiss()
                }
            } catch {
                assertionFailure("Failed to save entry: \(error)")
            }
        }
    }
}

@Observable
final class EntryFormModel {
    var timestamp: Date = .now
    var overallSeverity: Int = 0
    var isMenstruating: Bool = false
    var note: String = ""

    var isSaveDisabled: Bool {
        overallSeverity < 0 || overallSeverity > 10
    }
}

#Preview("Add Entry") {
    withPreviewDataStore { dataStore in
        let journal = dataStore.createJournal()
        AddEntryView(journalID: journal.id)
    }
}
