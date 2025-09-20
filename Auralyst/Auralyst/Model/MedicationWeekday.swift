import Foundation

enum MedicationWeekday: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int { rawValue }

    var displayName: String {
        let symbols = Calendar.current.weekdaySymbols
        let index = (rawValue - 1) % symbols.count
        return symbols[index]
    }

    var shortName: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = (rawValue - 1) % symbols.count
        return symbols[index]
    }

    static func mask(for days: [MedicationWeekday]) -> Int16 {
        days.reduce(into: Int16(0)) { result, day in
            let bit = Int16(1 << ((day.rawValue - 1) % 7))
            result |= bit
        }
    }

    static func days(from mask: Int16) -> [MedicationWeekday] {
        MedicationWeekday.allCases.filter { day in
            let bit = Int16(1 << ((day.rawValue - 1) % 7))
            return mask & bit == bit
        }
    }
}

extension MedicationSchedule {
    var weekdays: [MedicationWeekday] {
        MedicationWeekday.days(from: daysOfWeekMask)
    }

    func includes(weekday: MedicationWeekday) -> Bool {
        let bit = Int16(1 << ((weekday.rawValue - 1) % 7))
        return daysOfWeekMask & bit == bit
    }
}
