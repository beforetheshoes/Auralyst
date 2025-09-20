import CoreData
import SwiftUI

struct MedicationIntakeEditorView: View {
    let intakeID: NSManagedObjectID

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var intakeResults: FetchedResults<MedicationIntake>

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

    init(intakeID: NSManagedObjectID) {
        self.intakeID = intakeID
        _intakeResults = FetchRequest(
            entity: MedicationIntake.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "SELF == %@", intakeID)
        )
    }

    private var intake: MedicationIntake? {
        intakeResults.first
    }

    var body: some View {
        Group {
            if let intake {
                Form {
                    Section(intake.medication?.name ?? "Medication") {
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
#if os(macOS)
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        Button("Save", action: save)
                            .keyboardShortcut(.defaultAction)
                    }
#else
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .keyboardShortcut(.defaultAction)
                    }
#endif
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
        guard didLoad == false, let intake else { return }
        didLoad = true

        amountValue = intake.amountValue.map { NSDecimalNumber(decimal: $0).doubleValue }
        unit = intake.unit ?? ""
        notes = intake.notes ?? ""
        timestamp = intake.timestamp ?? Date()
    }

    private func save() {
        guard let intake else { return }
        context.perform {
            intake.timestamp = timestamp

            if let amountValue {
                let decimalAmount = Decimal(amountValue)
                intake.amount = NSDecimalNumber(decimal: decimalAmount)
            } else {
                intake.amount = nil
            }

            let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
            intake.unit = trimmedUnit.isEmpty ? nil : trimmedUnit

            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            intake.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

            intake.medication?.updatedAt = Date()

            do {
                try context.save()
                dismiss()
            } catch {
                context.rollback()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete() {
        guard let intake else { return }
        context.perform {
            context.delete(intake)
            do {
                try context.save()
                dismiss()
            } catch {
                context.rollback()
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview("Medication Intake Editor") {
    let controller = PersistenceController.preview
    let context = controller.container.viewContext
    PreviewSeed.populateIfNeeded(context: context)

    let request = MedicationIntake.fetchRequest()
    request.fetchLimit = 1
    request.sortDescriptors = [NSSortDescriptor(keyPath: \MedicationIntake.timestamp, ascending: false)]
    let intake = try? context.fetch(request).first

    return NavigationStack {
        if let intake {
            MedicationIntakeEditorView(intakeID: intake.objectID)
        } else {
            Text("No sample intake available")
                .foregroundStyle(.secondary)
        }
    }
    .environment(\.managedObjectContext, context)
}
