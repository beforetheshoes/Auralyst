import CoreData
import Foundation

extension Journal {
    var wrappedEntries: [SymptomEntry] {
        guard let entries = entries as? Set<SymptomEntry> else { return [] }
        return entries.sorted { lhs, rhs in
            let lhsTimestamp = lhs.timestampValue
            let rhsTimestamp = rhs.timestampValue
            if lhsTimestamp == rhsTimestamp {
                let lhsID = lhs.id?.uuidString ?? ""
                let rhsID = rhs.id?.uuidString ?? ""
                return lhsID > rhsID
            }
            return lhsTimestamp > rhsTimestamp
        }
    }

    var wrappedMedications: [Medication] {
        guard let meds = medications as? Set<Medication> else { return [] }
        return meds.sorted { lhs, rhs in
            let lhsName = lhs.name ?? ""
            let rhsName = rhs.name ?? ""
            let comparison = lhsName.localizedCaseInsensitiveCompare(rhsName)
            if comparison == .orderedSame {
                return lhs.createdAtValue > rhs.createdAtValue
            }
            return comparison == .orderedAscending
        }
    }
}

extension SymptomEntry {
    var timestampValue: Date { timestamp ?? .distantPast }

    var groupingDate: Date { timestampValue }

    var collaboratorNotes: [CollaboratorNote] {
        guard let notes = notes as? Set<CollaboratorNote> else { return [] }
        return notes.sorted { $0.timestampValue < $1.timestampValue }
    }

    var medicationLogs: [MedicationIntake] {
        guard let intakes = medicationIntakes as? Set<MedicationIntake> else { return [] }
        return intakes.sorted { $0.timestampValue > $1.timestampValue }
    }

    var sentimentScoreValue: Double? {
        (value(forKey: "sentimentScore") as? NSNumber)?.doubleValue
    }
}

extension CollaboratorNote {
    var timestampValue: Date { timestamp ?? .distantPast }
}

extension Medication {
    var createdAtValue: Date { createdAt ?? .distantPast }

    var defaultAmountValue: Decimal? {
        guard let number = defaultAmount else { return nil }
        return number.decimalValue
    }

    var useCaseLabel: String? {
        guard let label = useCase?.trimmingCharacters(in: .whitespacesAndNewlines), label.isEmpty == false else {
            return nil
        }
        return label
    }

    var scheduleList: [MedicationSchedule] {
        guard let items = scheduleItems as? Set<MedicationSchedule> else { return [] }
        return items.sorted { lhs, rhs in
            let lhsOrder = Int(lhs.sortOrder)
            let rhsOrder = Int(rhs.sortOrder)
            if lhsOrder == rhsOrder {
                if lhs.hour == rhs.hour {
                    return lhs.minute < rhs.minute
                }
                return lhs.hour < rhs.hour
            }
            return lhsOrder < rhsOrder
        }
    }

    var intakeHistory: [MedicationIntake] {
        guard let intakes = intakes as? Set<MedicationIntake> else { return [] }
        return intakes.sorted { $0.timestampValue > $1.timestampValue }
    }
}

extension MedicationSchedule {
    enum Cadence: String, CaseIterable, Identifiable {
        case daily
        case weekly
        case interval
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .interval: return "Every N Days"
            case .custom: return "Custom"
            }
        }
    }

    var cadenceValue: Cadence {
        Cadence(rawValue: cadence ?? "") ?? .daily
    }

    var timeZone: TimeZone {
        if let identifier = timeZoneIdentifier, let zone = TimeZone(identifier: identifier) {
            return zone
        }
        return .current
    }

    var occurrenceTime: DateComponents {
        DateComponents(hour: Int(hour), minute: Int(minute))
    }

    var amountValue: Decimal? {
        guard let number = amount else { return nil }
        return number.decimalValue
    }

    func occurs(on day: Date, calendar baseCalendar: Calendar = .current) -> Date? {
        guard isActive else { return nil }
        let hourValue = Int(hour)
        let minuteValue = Int(minute)
        guard hourValue >= 0, minuteValue >= 0 else { return nil }

        var calendar = baseCalendar
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: day)

        switch cadenceValue {
        case .daily:
            break
        case .weekly, .custom:
            let weekday = calendar.component(.weekday, from: startOfDay)
            if daysOfWeekMask > 0 {
                let bitIndex = (weekday % 7)
                let mask = 1 << bitIndex
                if Int(daysOfWeekMask) & mask == 0 {
                    return nil
                }
            }
        case .interval:
            guard let anchor = startDate else { break }
            let effectiveInterval = max(Int(interval), 1)
            let anchorDay = calendar.startOfDay(for: anchor)
            guard let distance = calendar.dateComponents([.day], from: anchorDay, to: startOfDay).day else {
                return nil
            }
            if distance < 0 || distance % effectiveInterval != 0 {
                return nil
            }
        }

        var components = calendar.dateComponents([.year, .month, .day], from: startOfDay)
        components.hour = hourValue
        components.minute = minuteValue
        return calendar.date(from: components)
    }

    func intake(on occurrence: Date, tolerance: TimeInterval = 60 * 15) -> MedicationIntake? {
        guard let intakes = self.intakes as? Set<MedicationIntake> else { return nil }
        return intakes.first { intake in
            guard let scheduled = intake.scheduledDate else { return false }
            return abs(scheduled.timeIntervalSince(occurrence)) <= tolerance
        }
    }
}

extension MedicationIntake {
    enum Origin: String {
        case scheduled
        case asNeeded
        case manual
    }

    var originValue: Origin {
        Origin(rawValue: origin ?? "") ?? .manual
    }

    var timestampValue: Date { timestamp ?? .distantPast }

    var amountValue: Decimal? {
        guard let number = amount else { return nil }
        return number.decimalValue
    }

    var originDisplayName: String {
        switch originValue {
        case .scheduled:
            return "Scheduled"
        case .asNeeded:
            return "As Needed"
        case .manual:
            return "Manual"
        }
    }

    var groupingDate: Date { scheduledDate ?? timestampValue }
}
