import CoreData
import Observation
import SwiftUI

struct AddEntryView: View {
    let journalID: NSManagedObjectID

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

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
        context.perform {
            guard let journal = try? context.existingObject(with: journalID) as? Journal else {
                assertionFailure("Missing journal for new entry")
                return
            }

            let entry = SymptomEntry(context: context)
            entry.id = UUID()
            entry.timestamp = form.timestamp
            entry.severity = Int16(form.overallSeverity)
            entry.isMenstruating = form.isMenstruating
            entry.note = form.note.isEmpty ? nil : form.note
            entry.journal = journal

            do {
                try context.save()
                dismiss()
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
    let controller = PersistenceController.preview
    let context = controller.container.viewContext
    PreviewSeed.populateIfNeeded(context: context)
    let journal = try? context.fetch(Journal.fetchRequest()).first
    return Group {
        if let journal {
            AddEntryView(journalID: journal.objectID)
                .environment(\.managedObjectContext, context)
        }
    }
}
