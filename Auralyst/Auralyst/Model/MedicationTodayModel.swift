import CoreData
import Foundation
import Observation

@Observable
final class MedicationTodayModel {
    struct ScheduledOccurrence: Identifiable, Hashable {
        let id: String
        let scheduleID: NSManagedObjectID
        let medicationID: NSManagedObjectID
        let medicationName: String
        let medicationUseCase: String?
        let scheduleLabel: String
        let scheduledAt: Date
        let amount: Decimal?
        let unit: String?
        let intakeTimestamp: Date?
        var taken: Bool

        var displayAmount: String? {
            guard let amount else { return nil }
            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 0
            let value = formatter.string(from: amount.nsDecimalNumber) ?? "\(amount)"
            if let unit, unit.isEmpty == false {
                return "\(value) \(unit)"
            }
            return value
        }
    }

    struct AsNeededItem: Identifiable, Hashable {
        let id: NSManagedObjectID
        let medicationName: String
        let medicationUseCase: String?
        let defaultAmount: Decimal?
        let unit: String?
        let lastLoggedAt: Date?

        var displayAmount: String? {
            guard let defaultAmount else { return nil }
            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 0
            let value = formatter.string(from: defaultAmount.nsDecimalNumber) ?? "\(defaultAmount)"
            if let unit, unit.isEmpty == false {
                return "\(value) \(unit)"
            }
            return value
        }
    }

    let journalID: NSManagedObjectID
    var day: Date
    var scheduled: [ScheduledOccurrence] = []
    var asNeeded: [AsNeededItem] = []
    var hasMedications: Bool = false

    init(journalID: NSManagedObjectID, day: Date = Date()) {
        self.journalID = journalID
        self.day = Calendar.current.startOfDay(for: day)
    }

    func refresh(in context: NSManagedObjectContext) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        var newScheduled: [ScheduledOccurrence] = []
        var newAsNeeded: [AsNeededItem] = []

        context.performAndWait {
            let request = NSFetchRequest<Medication>(entityName: "Medication")
            request.predicate = NSPredicate(format: "journal == %@", journalID)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Medication.createdAt, ascending: true)]

            guard let medications = try? context.fetch(request) else {
                scheduled = []
                asNeeded = []
                hasMedications = false
                return
            }

            hasMedications = medications.isEmpty == false
            let store = MedicationStore(context: context, calendar: { calendar })

            for medication in medications {
                if medication.isAsNeeded == true {
                    let item = AsNeededItem(
                        id: medication.objectID,
                        medicationName: medication.name ?? "Untitled",
                        medicationUseCase: medication.useCaseLabel,
                        defaultAmount: medication.defaultAmountValue,
                        unit: medication.defaultUnit,
                        lastLoggedAt: medication.intakeHistory.first?.timestampValue
                    )
                    newAsNeeded.append(item)
                    continue
                }

                for schedule in medication.scheduleList where schedule.isActive {
                    guard let scheduledAt = schedule.occurs(on: dayStart, calendar: calendar) else { continue }
                    let intake = store.scheduledIntake(for: schedule, on: dayStart)
                    let occurrenceID = "\(schedule.objectID.uriRepresentation().absoluteString)-\(dayStart.timeIntervalSinceReferenceDate)"
                    let occurrence = ScheduledOccurrence(
                        id: occurrenceID,
                        scheduleID: schedule.objectID,
                        medicationID: medication.objectID,
                        medicationName: medication.name ?? "Untitled",
                        medicationUseCase: medication.useCaseLabel,
                        scheduleLabel: schedule.label ?? "",
                        scheduledAt: scheduledAt,
                        amount: schedule.amountValue ?? medication.defaultAmountValue,
                        unit: schedule.unit ?? medication.defaultUnit,
                        intakeTimestamp: intake?.timestampValue,
                        taken: intake != nil
                    )
                    newScheduled.append(occurrence)
                }
            }
        }

        let sortedScheduled = newScheduled.sorted { lhs, rhs in
            if lhs.scheduledAt == rhs.scheduledAt {
                return lhs.medicationName < rhs.medicationName
            }
            return lhs.scheduledAt < rhs.scheduledAt
        }

        let sortedAsNeeded = newAsNeeded.sorted { lhs, rhs in
            (lhs.medicationName, lhs.lastLoggedAt ?? .distantPast) < (rhs.medicationName, rhs.lastLoggedAt ?? .distantPast)
        }

        scheduled = sortedScheduled
        asNeeded = sortedAsNeeded
    }
}
