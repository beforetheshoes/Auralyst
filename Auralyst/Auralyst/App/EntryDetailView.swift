import CoreData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest private var entryResults: FetchedResults<SymptomEntry>

    @State private var showingAddCollaboratorNote = false
    @State private var editingIntake: MedicationIntake?
    @State private var pendingDeleteIntake: MedicationIntake?
    @State private var showingDeleteConfirmation = false
    @State private var deletionError: String?

    init(entryID: NSManagedObjectID) {
        _entryResults = FetchRequest(
            entity: SymptomEntry.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "SELF == %@", entryID)
        )
    }

    private var entry: SymptomEntry? {
        entryResults.first
    }

    var body: some View {
        Group {
            if let entry {
                List {
                    Section("Logged") {
                        LabeledContent("Severity") {
                            Text(severityText(for: entry))
                                .font(.headline)
                                .foregroundStyle(Color.brandAccent)
                        }

                        LabeledContent("Menstruating") {
                            Text(entry.isMenstruating ? "Yes" : "No")
                                .font(.body)
                                .foregroundStyle(entry.isMenstruating ? Color.brandAccent : .secondary)
                        }

                        LabeledContent("Timestamp") {
                            VStack(alignment: .trailing) {
                                Text(entry.timestampValue, style: .date)
                                Text(entry.timestampValue, style: .time)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let note = entry.note {
                            Text(note)
                                .font(.body)
                                .foregroundStyle(Color.ink.opacity(0.8))
                                .padding(.top, 4)
                        }
                    }

                    if entry.medicationLogs.isEmpty == false {
                        Section("Medications") {
                            ForEach(entry.medicationLogs, id: \.objectID) { intake in
                                MedicationIntakeRow(intake: intake)
                                    .modifier(IntakeActionsModifier(
                                        onEdit: { editingIntake = intake },
                                        onDelete: { promptDelete(intake) }
                                    ))
                            }
                        }
                    }

                    Section("Collaborator Notes") {
                        let collaboratorNotes = entry.collaboratorNotes
                        if collaboratorNotes.isEmpty {
                            Text("No collaborator notes yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(collaboratorNotes) { note in
                                CollaboratorNoteRow(note: note)
                            }
                        }
                    }
                }
                .navigationTitle(entry.timestampValue.formatted(date: .abbreviated, time: .omitted))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddCollaboratorNote = true
                        } label: {
                            Label("Add Note", systemImage: "bubble.left")
                        }
                    }
                }
                .sheet(isPresented: $showingAddCollaboratorNote) {
                    AddCollaboratorNoteView(entryID: entry.objectID)
                }
                .sheet(item: $editingIntake, onDismiss: { editingIntake = nil }) { intake in
                    MedicationIntakeEditorView(intakeID: intake.objectID)
                }
                .confirmationDialog(
                    "Delete Dose?",
                    isPresented: $showingDeleteConfirmation,
                    presenting: pendingDeleteIntake
                ) { intake in
                    Button("Delete", role: .destructive) {
                        delete(intake)
                    }
                } message: { _ in
                    Text("This removes the logged medication from the entry.")
                }
                .alert("Unable to Delete", isPresented: Binding(get: { deletionError != nil }, set: { if $0 == false { deletionError = nil } })) {
                    Button("OK", role: .cancel) { deletionError = nil }
                } message: {
                    Text(deletionError ?? "")
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading entry…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func severityText(for entry: SymptomEntry) -> String {
        if entry.severity >= 0 {
            return "Severity \(entry.severity)/10"
        }
        if entry.headache > 0 || entry.nausea > 0 || entry.anxiety > 0 {
            return [
                formattedSymptom("Headache", value: entry.headache),
                formattedSymptom("Nausea", value: entry.nausea),
                formattedSymptom("Anxiety", value: entry.anxiety)
            ].compactMap { $0 }.joined(separator: "  •  ")
        }
        return "Not set"
    }

    private func formattedSymptom(_ label: String, value: Int16) -> String? {
        guard value > 0 else { return nil }
        return "\(label): \(value)"
    }

    private func promptDelete(_ intake: MedicationIntake) {
        pendingDeleteIntake = intake
        showingDeleteConfirmation = true
    }

    private func delete(_ intake: MedicationIntake) {
        pendingDeleteIntake = nil
        context.perform {
            if intake.managedObjectContext == nil {
                return
            }

            context.delete(intake)
            do {
                try context.save()
                deletionError = nil
            } catch {
                context.rollback()
                deletionError = error.localizedDescription
            }
        }
    }
}

private struct CollaboratorNoteRow: View {
    let note: CollaboratorNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.text ?? "")
                .font(.body)
                .foregroundStyle(Color.ink)
            HStack(spacing: 8) {
                if let author = note.authorName {
                    Text(author)
                        .font(.footnote)
                        .foregroundStyle(Color.brandAccent)
                }
                Text(note.timestampValue, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MedicationIntakeRow: View {
    let intake: MedicationIntake

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(intake.medication?.name ?? "Medication")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(intake.timestampValue, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if let amount = intake.amountValue {
                    let formatted = NumberFormatter.localizedString(from: amount.nsDecimalNumber, number: .decimal)
                    if let unit = intake.unit, unit.isEmpty == false {
                        Text("\(formatted) \(unit)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(formatted)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let unit = intake.unit, unit.isEmpty == false {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                switch intake.originValue {
                case .scheduled:
                    if let label = intake.schedule?.label, label.isEmpty == false {
                        IntakeTag(text: label, tint: Color.brandAccent)
                    } else {
                        IntakeTag(text: "Scheduled", tint: Color.brandAccent)
                    }
                case .asNeeded:
                    IntakeTag(text: "As Needed", tint: Color.brandPrimary)
                case .manual:
                    IntakeTag(text: "Manual", tint: .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct IntakeTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

#Preview("Entry Detail") {
    let controller = PersistenceController.preview
    let context = controller.container.viewContext
    PreviewSeed.populateIfNeeded(context: context)
    let request = SymptomEntry.fetchRequest()
    request.fetchLimit = 1
    let entry = try? context.fetch(request).first

    return Group {
        if let entry {
            NavigationStack {
                EntryDetailView(entryID: entry.objectID)
            }
        } else {
            Text("Preview entry unavailable")
                .foregroundStyle(.secondary)
        }
    }
    .environment(\.managedObjectContext, context)
}
