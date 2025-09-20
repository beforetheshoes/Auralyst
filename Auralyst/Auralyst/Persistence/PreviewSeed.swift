import CoreData
import Foundation

enum PreviewSeed {
    static func populateIfNeeded(context: NSManagedObjectContext) {
        let request = NSFetchRequest<Journal>(entityName: "Journal")
        request.fetchLimit = 1
        if let existing = try? context.fetch(request), existing.isEmpty == false {
            return
        }

        let journal = Journal(context: context)
        journal.id = UUID()
        journal.createdAt = Date()

        let scheduleTimeZone = TimeZone.current
        let medicationStore = MedicationStore(context: context)

        let dailyMedication = Medication(context: context)
        dailyMedication.id = UUID()
        dailyMedication.createdAt = Date().addingTimeInterval(-86400 * 14)
        dailyMedication.updatedAt = Date()
        dailyMedication.name = "Sertraline"
        dailyMedication.useCase = "Mood"
        dailyMedication.isAsNeeded = false
        dailyMedication.defaultAmount = Decimal(50).nsDecimalNumber
        dailyMedication.defaultUnit = "mg"
        dailyMedication.journal = journal

        let morningSchedule = MedicationSchedule(context: context)
        morningSchedule.id = UUID()
        morningSchedule.label = "Morning"
        morningSchedule.cadence = MedicationSchedule.Cadence.daily.rawValue
        morningSchedule.hour = 8
        morningSchedule.minute = 0
        morningSchedule.sortOrder = 0
        morningSchedule.isActive = true
        morningSchedule.startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        morningSchedule.timeZoneIdentifier = scheduleTimeZone.identifier
        morningSchedule.amount = Decimal(50).nsDecimalNumber
        morningSchedule.unit = "mg"
        morningSchedule.medication = dailyMedication

        let eveningSchedule = MedicationSchedule(context: context)
        eveningSchedule.id = UUID()
        eveningSchedule.label = "Evening"
        eveningSchedule.cadence = MedicationSchedule.Cadence.interval.rawValue
        eveningSchedule.interval = 2
        eveningSchedule.hour = 20
        eveningSchedule.minute = 30
        eveningSchedule.sortOrder = 1
        eveningSchedule.isActive = true
        eveningSchedule.startDate = Calendar.current.date(byAdding: .day, value: -28, to: Date())
        eveningSchedule.timeZoneIdentifier = scheduleTimeZone.identifier
        eveningSchedule.amount = Decimal(25).nsDecimalNumber
        eveningSchedule.unit = "mg"
        eveningSchedule.medication = dailyMedication

        let rescueMedication = Medication(context: context)
        rescueMedication.id = UUID()
        rescueMedication.createdAt = Date().addingTimeInterval(-86400 * 10)
        rescueMedication.updatedAt = Date()
        rescueMedication.name = "Hydroxyzine"
        rescueMedication.useCase = "Anxiety"
        rescueMedication.isAsNeeded = true
        rescueMedication.defaultAmount = Decimal(25).nsDecimalNumber
        rescueMedication.defaultUnit = "mg"
        rescueMedication.journal = journal

        let today = Calendar.current.startOfDay(for: Date())
        for offset in 0..<5 {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) ?? today
            if let intake = medicationStore.setScheduledIntake(morningSchedule, on: day, taken: true) {
                if let scheduledDate = intake.scheduledDate { intake.timestamp = scheduledDate }
            }

            if offset % 2 == 0,
               let intake = medicationStore.setScheduledIntake(eveningSchedule, on: day, taken: true) {
                if let scheduledDate = intake.scheduledDate { intake.timestamp = scheduledDate }
            }

            if offset == 1 {
                let loggedAt = Calendar.current.date(byAdding: .hour, value: -6, to: day) ?? day
                _ = medicationStore.logAsNeeded(rescueMedication, amount: Decimal(25), unit: "mg", at: loggedAt)
            }
        }

        for offset in 0..<5 {
            let entry = SymptomEntry(context: context)
            entry.id = UUID()
            entry.timestamp = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            entry.severity = Int16(Int.random(in: 0...8))
            entry.isMenstruating = offset <= 1
            entry.note = offset == 0 ? "Baseline calm morning." : nil
            entry.sentimentScore = offset == 0 ? 0.7 : 0.2
            entry.sentimentLabel = offset == 0 ? "Positive" : "Neutral"
            entry.journal = journal

            if offset == 1 {
                let note = CollaboratorNote(context: context)
                note.id = UUID()
                note.timestamp = Date()
                note.text = "Saw improvement after earlier bedtime."
                note.authorName = "Taylor"
                note.entryRef = entry
                note.journal = journal
            }
        }

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to seed preview data: \(error)")
        }
    }
}
