import Foundation
import Observation
import SQLiteData

@MainActor
@Observable
final class MedicationQuickLogModel {
    let journalID: UUID

    var selectedDate: Date {
        didSet {
            let normalized = Self.normalize(selectedDate)
            if normalized != selectedDate {
                selectedDate = normalized
                return
            }
            rebuildSnapshot()
        }
    }

    private(set) var snapshot: MedicationQuickLogSnapshot = .empty

    @ObservationIgnored
    @FetchAll var medicationRows: [SQLiteMedication] {
        didSet { rebuildSnapshot() }
    }

    @ObservationIgnored
    @FetchAll var scheduleRows: [SQLiteMedicationSchedule] {
        didSet { rebuildSnapshot() }
    }

    @ObservationIgnored
    @FetchAll var intakeRows: [SQLiteMedicationIntake] {
        didSet { rebuildSnapshot() }
    }

    init(journalID: UUID, initialDate: Date = Date()) {
        self.journalID = journalID
        self.selectedDate = Self.normalize(initialDate)
        self._medicationRows = FetchAll(
            SQLiteMedication
                .where { $0.journalID == journalID }
                .order { $0.name.asc() }
        )
        self._scheduleRows = FetchAll(SQLiteMedicationSchedule.all)
        self._intakeRows = FetchAll(SQLiteMedicationIntake.all)
        rebuildSnapshot()
    }

    func refresh() {
        rebuildSnapshot()
    }
}

private extension MedicationQuickLogModel {
    static func normalize(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    func rebuildSnapshot() {
        let meds = medicationRows
            .filter { $0.journalID == journalID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let schedules = Self.buildSchedulesIndex(from: scheduleRows, medications: meds)
        let taken = Self.buildTakenIndex(from: intakeRows, medications: meds, on: selectedDate)
        snapshot = MedicationQuickLogSnapshot(
            medications: meds,
            schedulesByMedication: schedules,
            takenByScheduleID: taken
        )
    }

    static func buildSchedulesIndex(from schedules: [SQLiteMedicationSchedule], medications: [SQLiteMedication]) -> [UUID: [SQLiteMedicationSchedule]] {
        let medicationIDs = Set(medications.map(\.id))
        return schedules
            .filter { medicationIDs.contains($0.medicationID) }
            .reduce(into: [UUID: [SQLiteMedicationSchedule]]()) { result, schedule in
                result[schedule.medicationID, default: []].append(schedule)
            }
    }

    static func buildTakenIndex(
        from intakes: [SQLiteMedicationIntake],
        medications: [SQLiteMedication],
        on date: Date
    ) -> [UUID: SQLiteMedicationIntake] {
        let medicationIDs = Set(medications.map(\.id))
        let bounds = dayBounds(for: date)
        return intakes.reduce(into: [UUID: SQLiteMedicationIntake]()) { result, intake in
            guard medicationIDs.contains(intake.medicationID) else { return }
            guard intake.timestamp >= bounds.start && intake.timestamp < bounds.end else { return }
            if let scheduleID = intake.scheduleID {
                result[scheduleID] = intake
            } else {
                result[intake.medicationID] = intake
            }
        }
    }

    static func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }
}
