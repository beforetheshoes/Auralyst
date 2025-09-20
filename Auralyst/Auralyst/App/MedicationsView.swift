import CoreData
import SwiftUI

struct MedicationsView: View {
    enum EditorMode: Identifiable {
        case create
        case edit(NSManagedObjectID)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let id): return id.uriRepresentation().absoluteString
            }
        }
    }

    let journalID: NSManagedObjectID

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var medications: FetchedResults<Medication>
    @State private var editorMode: EditorMode?

    init(journalID: NSManagedObjectID) {
        self.journalID = journalID
        _medications = FetchRequest(
            entity: Medication.entity(),
            sortDescriptors: [
                NSSortDescriptor(keyPath: \Medication.isAsNeeded, ascending: true),
                NSSortDescriptor(keyPath: \Medication.createdAt, ascending: true)
            ],
            predicate: NSPredicate(format: "journal == %@", journalID),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if medications.isEmpty {
                    VStack(spacing: 12) {
                        Text("No medications yet")
                            .font(.headline)
                            .foregroundStyle(Color.ink)
                        Text("Add scheduled or as-needed medications to quick-log doses and share trends.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    Section("Scheduled") {
                        let scheduled = medications.filter { $0.isAsNeeded == false }
                        if scheduled.isEmpty {
                            Text("No scheduled medications yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(scheduled, id: \.objectID) { medication in
                                MedicationRow(medication: medication) {
                                    editorMode = .edit(medication.objectID)
                                }
                                .swipeActions {
                                    Button("Delete", role: .destructive) {
                                        deleteMedication(medication)
                                    }
                                    Button("Edit") {
                                        editorMode = .edit(medication.objectID)
                                    }
                                }
                            }
                        }
                    }

                    Section("As Needed") {
                        let asNeeded = medications.filter { $0.isAsNeeded == true }
                        if asNeeded.isEmpty {
                            Text("No as-needed medications yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(asNeeded, id: \.objectID) { medication in
                                MedicationRow(medication: medication) {
                                    editorMode = .edit(medication.objectID)
                                }
                                .swipeActions {
                                    Button("Delete", role: .destructive) {
                                        deleteMedication(medication)
                                    }
                                    Button("Edit") {
                                        editorMode = .edit(medication.objectID)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: { dismiss() })
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorMode = .create
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorMode) { mode in
                MedicationEditorView(mode: mode, journalID: journalID)
            }
        }
    }

    private func deleteMedication(_ medication: Medication) {
        context.delete(medication)
        try? context.save()
    }
}

private struct MedicationRow: View {
    let medication: Medication
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(medication.name ?? "Untitled")
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                    if medication.isAsNeeded == true {
                        CapsuleLabel(text: "As Needed")
                    }
                }

                if let useCase = medication.useCaseLabel {
                    Text(useCase)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brandAccent)
                }

                if medication.isAsNeeded == true {
                    if let amount = medication.defaultAmountValue {
                        Text("Default: \(formatted(amount)) \(medication.defaultUnit ?? "")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let unit = medication.defaultUnit, unit.isEmpty == false {
                        Text(unit)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let schedules = medication.scheduleList
                    if schedules.isEmpty {
                        Text("No active schedule")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(schedules, id: \.objectID) { schedule in
                            Text(scheduleSummary(for: schedule))
                                .font(.subheadline)
                                .foregroundStyle(schedule.isActive ? .secondary : .tertiary)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func formatted(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount.nsDecimalNumber) ?? "\(amount)"
    }

    private func scheduleSummary(for schedule: MedicationSchedule) -> String {
        let time = scheduleTime(schedule)
        let amount = schedule.amountValue ?? schedule.medication?.defaultAmountValue
        let unit = schedule.unit ?? schedule.medication?.defaultUnit ?? ""
        var components: [String] = []
        if let label = schedule.label, label.isEmpty == false {
            components.append(label)
        }
        components.append(time)
        if let amount {
            let formattedAmount = formatted(amount)
            if unit.isEmpty {
                components.append(formattedAmount)
            } else {
                components.append("\(formattedAmount) \(unit)")
            }
        } else if unit.isEmpty == false {
            components.append(unit)
        }
        components.append(cadenceDescription(for: schedule))
        return components.joined(separator: " • ")
    }

    private func scheduleTime(_ schedule: MedicationSchedule) -> String {
        var comps = DateComponents()
        comps.hour = Int(schedule.hour)
        comps.minute = Int(schedule.minute)
        let calendar = Calendar.current
        let date = calendar.date(from: comps) ?? Date()
        return date.formatted(.dateTime.hour().minute())
    }

    private func cadenceDescription(for schedule: MedicationSchedule) -> String {
        switch schedule.cadenceValue {
        case .daily:
            return "Daily"
        case .weekly, .custom:
            let days = schedule.weekdays
            if days.isEmpty {
                return "Weekly"
            }
            let names = days.map { $0.shortName }
            return names.joined(separator: " ")
        case .interval:
            let interval = max(Int(schedule.interval), 1)
            return "Every \(interval) day\(interval == 1 ? "" : "s")"
        }
    }
}

private struct CapsuleLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.brandAccent.opacity(0.15), in: Capsule())
    }
}
