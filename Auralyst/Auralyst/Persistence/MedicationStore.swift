import CoreData
import Foundation

final class MedicationStore {
    private let context: NSManagedObjectContext
    private let calendarProvider: () -> Calendar

    init(context: NSManagedObjectContext, calendar: @escaping () -> Calendar = { Calendar.current }) {
        self.context = context
        self.calendarProvider = calendar
    }

    @discardableResult
    func setScheduledIntake(
        _ schedule: MedicationSchedule,
        on day: Date,
        taken: Bool,
        loggedAt overrideTimestamp: Date? = nil
    ) -> MedicationIntake? {
        guard let scheduledAt = schedule.occurs(on: day, calendar: calendarProvider()) else {
            return nil
        }

        if taken {
            if let existing = existingScheduledIntake(for: schedule, at: scheduledAt) {
                return existing
            }
            let intake = MedicationIntake(context: context)
            intake.id = UUID()
            intake.origin = MedicationIntake.Origin.scheduled.rawValue
            intake.timestamp = overrideTimestamp ?? Date()
            intake.scheduledDate = scheduledAt
            intake.schedule = schedule
            intake.medication = schedule.medication
            if let amount = schedule.amountValue {
                intake.amount = amount.nsDecimalNumber
            } else if let fallback = schedule.medication?.defaultAmountValue {
                intake.amount = fallback.nsDecimalNumber
            }
            if let unit = schedule.unit ?? schedule.medication?.defaultUnit {
                intake.unit = unit
            }
            schedule.medication?.updatedAt = Date()
            return intake
        } else {
            if let existing = existingScheduledIntake(for: schedule, at: scheduledAt) {
                context.delete(existing)
                schedule.medication?.updatedAt = Date()
            }
            return nil
        }
    }

    @discardableResult
    func logAsNeeded(_ medication: Medication, amount: Decimal?, unit: String?, at timestamp: Date = Date()) -> MedicationIntake {
        let resolvedAmount = amount ?? medication.defaultAmountValue
        let resolvedUnit = unit ?? medication.defaultUnit ?? medication.scheduleList.first?.unit

        let intake = MedicationIntake(context: context)
        intake.id = UUID()
        intake.origin = MedicationIntake.Origin.asNeeded.rawValue
        intake.timestamp = timestamp
        intake.medication = medication
        if let resolvedAmount {
            intake.amount = resolvedAmount.nsDecimalNumber
            medication.defaultAmount = resolvedAmount.nsDecimalNumber
        }
        if let resolvedUnit {
            intake.unit = resolvedUnit
            medication.defaultUnit = resolvedUnit
        }
        medication.updatedAt = Date()
        return intake
    }

    func hasLoggedSchedule(_ schedule: MedicationSchedule, on day: Date) -> Bool {
        guard let scheduledAt = schedule.occurs(on: day, calendar: calendarProvider()) else {
            return false
        }
        return existingScheduledIntake(for: schedule, at: scheduledAt) != nil
    }

    func scheduledIntake(for schedule: MedicationSchedule, on day: Date) -> MedicationIntake? {
        guard let scheduledAt = schedule.occurs(on: day, calendar: calendarProvider()) else {
            return nil
        }
        return existingScheduledIntake(for: schedule, at: scheduledAt)
    }

    private func existingScheduledIntake(for schedule: MedicationSchedule, at scheduledAt: Date) -> MedicationIntake? {
        guard let intakes = schedule.intakes as? Set<MedicationIntake> else { return nil }
        let tolerance: TimeInterval = 60 * 15
        return intakes.first(where: { intake in
            guard let occurrence = intake.scheduledDate else { return false }
            return abs(occurrence.timeIntervalSince(scheduledAt)) <= tolerance
        })
    }
}
