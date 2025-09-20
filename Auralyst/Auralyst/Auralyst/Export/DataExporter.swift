import CoreData
import Foundation

struct DataExportSummary {
    let exportedEntries: Int
    let exportedMedications: Int
    let exportedSchedules: Int
    let exportedIntakes: Int
}

protocol DataExporting {
    func exportCSVBundle(to url: URL, context: NSManagedObjectContext) throws -> DataExportSummary
    func exportJSON(to url: URL, context: NSManagedObjectContext) throws -> DataExportSummary
}

struct DataExporter: DataExporting {
    func exportCSVBundle(to url: URL, context: NSManagedObjectContext) throws -> DataExportSummary {
        let exportData = try makeExportData(context: context)

        let csvEntries: [ZipArchive.Entry] = [
            ZipArchive.Entry(
                fileName: "symptom_entries.csv",
                data: CSVBuilder(headers: SymptomEntryExport.csvHeaders)
                    .appending(rows: exportData.entries.map(\.csvRow))
                    .utf8Data
            ),
            ZipArchive.Entry(
                fileName: "medications.csv",
                data: CSVBuilder(headers: MedicationExport.csvHeaders)
                    .appending(rows: exportData.medications.map(\.csvRow))
                    .utf8Data
            ),
            ZipArchive.Entry(
                fileName: "medication_schedules.csv",
                data: CSVBuilder(headers: MedicationScheduleExport.csvHeaders)
                    .appending(rows: exportData.schedules.map(\.csvRow))
                    .utf8Data
            ),
            ZipArchive.Entry(
                fileName: "medication_intakes.csv",
                data: CSVBuilder(headers: MedicationIntakeExport.csvHeaders)
                    .appending(rows: exportData.intakes.map(\.csvRow))
                    .utf8Data
            )
        ]

        let archiveData = try ZipArchive(entries: csvEntries).makeData()
        try archiveData.write(to: url, options: .atomic)

        return exportData.summary
    }

    func exportJSON(to url: URL, context: NSManagedObjectContext) throws -> DataExportSummary {
        let exportData = try makeExportData(context: context)

        let payload = ExportPayload(
            generatedAt: Date(),
            entries: exportData.entries,
            medications: exportData.medications
        )

        let data = try JSONEncoder.exportEncoder.encode(payload)
        try data.write(to: url, options: .atomic)

        return exportData.summary
    }

    // MARK: - Private

    private func makeExportData(context: NSManagedObjectContext) throws -> ExportData {
        var result: Result<ExportData, Error>!

        context.performAndWait {
            do {
                let entryRequest = NSFetchRequest<SymptomEntry>(entityName: "SymptomEntry")
                entryRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SymptomEntry.timestamp, ascending: true)]
                let entries = try context.fetch(entryRequest)

                let medicationRequest = NSFetchRequest<Medication>(entityName: "Medication")
                medicationRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Medication.createdAt, ascending: true)]
                let medications = try context.fetch(medicationRequest)

                let intakeRequest = NSFetchRequest<MedicationIntake>(entityName: "MedicationIntake")
                intakeRequest.sortDescriptors = [NSSortDescriptor(keyPath: \MedicationIntake.timestamp, ascending: true)]
                let allIntakes = try context.fetch(intakeRequest)

                let assignments = assignIntakes(allIntakes, to: entries)
                let intakesByID = Dictionary(uniqueKeysWithValues: allIntakes.map { ($0.objectID, $0) })
                var entryIntakes: [NSManagedObjectID: [MedicationIntake]] = [:]
                for (intakeID, entry) in assignments {
                    if let intake = intakesByID[intakeID] {
                        entryIntakes[entry.objectID, default: []].append(intake)
                    }
                }

                let entryExports = entries.map { entry -> SymptomEntryExport in
                    let identifier = ExportIdentifier.identifier(for: entry)
                    let associated = entryIntakes[entry.objectID] ?? []
                    var seen = Set<String>()
                    let intakeIdentifiers = associated
                        .sorted { $0.timestampValue < $1.timestampValue }
                        .compactMap { intake -> String? in
                            let value = ExportIdentifier.identifier(for: intake)
                            guard seen.insert(value).inserted else { return nil }
                            return value
                        }
                    return SymptomEntryExport.make(
                        from: entry,
                        identifier: identifier,
                        medicationIntakeIdentifiers: intakeIdentifiers
                    )
                }

                let medicationExports = medications.map { medication -> MedicationExport in
                    let identifier = ExportIdentifier.identifier(for: medication)
                    let schedules = medication.scheduleList.map { schedule in
                        MedicationScheduleExport.make(
                            from: schedule,
                            identifier: ExportIdentifier.identifier(for: schedule),
                            medicationIdentifier: identifier
                        )
                    }
                    let intakes = medication.intakeHistory.map { intake in
                        MedicationIntakeExport.make(
                            from: intake,
                            identifier: ExportIdentifier.identifier(for: intake),
                            medicationIdentifier: identifier,
                            scheduleIdentifier: intake.schedule.map { ExportIdentifier.identifier(for: $0) },
                            entryIdentifier: assignments[intake.objectID].map { ExportIdentifier.identifier(for: $0) }
                        )
                    }
                    return MedicationExport.make(
                        from: medication,
                        identifier: identifier,
                        schedules: schedules,
                        intakes: intakes
                    )
                }

                let scheduleExports = medicationExports.flatMap(\.schedules)
                let intakeExports = medicationExports.flatMap(\.intakes)

                result = .success(
                    ExportData(
                        entries: entryExports,
                        medications: medicationExports,
                        schedules: scheduleExports,
                        intakes: intakeExports
                    )
                )
            } catch {
                result = .failure(error)
            }
        }

        return try result.get()
    }
}

private extension DataExporter {
    func assignIntakes(_ intakes: [MedicationIntake], to entries: [SymptomEntry]) -> [NSManagedObjectID: SymptomEntry] {
        guard intakes.isEmpty == false, entries.isEmpty == false else { return [:] }

        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.objectID, $0) })
        let entriesByJournal = Dictionary(grouping: entries) { $0.journal?.objectID }
        let calendar = Calendar.current

        var mapping: [NSManagedObjectID: SymptomEntry] = [:]

        for intake in intakes {
            if let entry = intake.entry, let resolved = entriesByID[entry.objectID] {
                mapping[intake.objectID] = resolved
                continue
            }

            guard
                let journalID = intake.entry?.journal?.objectID
                    ?? intake.medication?.journal?.objectID
                    ?? intake.schedule?.medication?.journal?.objectID,
                let candidates = entriesByJournal[journalID],
                candidates.isEmpty == false
            else {
                continue
            }

            let intakeMoment = intake.timestamp ?? intake.scheduledDate ?? .distantPast
            let sameDay = candidates.filter { candidate in
                calendar.isDate(candidate.timestampValue, inSameDayAs: intakeMoment)
            }

            guard sameDay.isEmpty == false else { continue }

            if sameDay.count == 1 {
                mapping[intake.objectID] = sameDay[0]
                continue
            }

            let nearest = sameDay.min { lhs, rhs in
                abs(lhs.timestampValue.timeIntervalSince(intakeMoment)) < abs(rhs.timestampValue.timeIntervalSince(intakeMoment))
            }

            if let nearest {
                mapping[intake.objectID] = nearest
            }
        }

        return mapping
    }
}

private struct ExportData {
    let entries: [SymptomEntryExport]
    let medications: [MedicationExport]
    let schedules: [MedicationScheduleExport]
    let intakes: [MedicationIntakeExport]

    var summary: DataExportSummary {
        DataExportSummary(
            exportedEntries: entries.count,
            exportedMedications: medications.count,
            exportedSchedules: schedules.count,
            exportedIntakes: intakes.count
        )
    }
}

private enum ExportIdentifier {
    static func identifier(for entry: SymptomEntry) -> String {
        entry.id?.uuidString ?? entry.objectID.uriRepresentation().absoluteString
    }

    static func identifier(for medication: Medication) -> String {
        medication.id?.uuidString ?? medication.objectID.uriRepresentation().absoluteString
    }

    static func identifier(for schedule: MedicationSchedule) -> String {
        schedule.id?.uuidString ?? schedule.objectID.uriRepresentation().absoluteString
    }

    static func identifier(for intake: MedicationIntake) -> String {
        intake.id?.uuidString ?? intake.objectID.uriRepresentation().absoluteString
    }
}

private struct CSVBuilder {
    private let headers: [String]
    private var rows: [[String]] = []

    init(headers: [String]) {
        self.headers = headers
    }

    mutating func appendRow(_ row: [String]) {
        rows.append(row)
    }

    mutating func append(rows newRows: [[String]]) {
        newRows.forEach { appendRow($0) }
    }

    func appending(rows newRows: [[String]]) -> CSVBuilder {
        var copy = self
        copy.append(rows: newRows)
        return copy
    }

    var string: String {
        ([headers] + rows)
            .map { row in
                row.map { CSVBuilder.escapeField($0) }.joined(separator: ",")
            }
            .joined(separator: "\n")
    }

    var utf8Data: Data {
        Data(string.utf8)
    }

    func write(to url: URL) throws {
        try string.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func escapeField(_ field: String) -> String {
        if field.contains(where: { ",\"\n".contains($0) }) {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}

private struct ZipArchive {
    struct Entry {
        let fileName: String
        let data: Data
    }

    enum ArchiveError: Error {
        case invalidFilename(String)
    }

    private let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries
    }

    func makeData() throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var entryCount: UInt16 = 0

        for entry in entries {
            guard let fileNameData = entry.fileName.data(using: .utf8) else {
                throw ArchiveError.invalidFilename(entry.fileName)
            }

            let crc = CRC32.checksum(entry.data)
            let offset = UInt32(archive.count)

            archive.appendUInt32LE(0x04034B50)
            archive.appendUInt16LE(20) // version needed to extract (2.0)
            archive.appendUInt16LE(0) // general purpose bit flag
            archive.appendUInt16LE(0) // compression method (store)
            archive.appendUInt16LE(0) // modification time
            archive.appendUInt16LE(0) // modification date
            archive.appendUInt32LE(crc)
            archive.appendUInt32LE(UInt32(entry.data.count))
            archive.appendUInt32LE(UInt32(entry.data.count))
            archive.appendUInt16LE(UInt16(fileNameData.count))
            archive.appendUInt16LE(0) // extra field length
            archive.append(fileNameData)
            archive.append(entry.data)

            centralDirectory.appendUInt32LE(0x02014B50)
            centralDirectory.appendUInt16LE(20) // version made by
            centralDirectory.appendUInt16LE(20) // version needed to extract
            centralDirectory.appendUInt16LE(0) // general purpose bit flag
            centralDirectory.appendUInt16LE(0) // compression method
            centralDirectory.appendUInt16LE(0) // modification time
            centralDirectory.appendUInt16LE(0) // modification date
            centralDirectory.appendUInt32LE(crc)
            centralDirectory.appendUInt32LE(UInt32(entry.data.count))
            centralDirectory.appendUInt32LE(UInt32(entry.data.count))
            centralDirectory.appendUInt16LE(UInt16(fileNameData.count))
            centralDirectory.appendUInt16LE(0) // extra field length
            centralDirectory.appendUInt16LE(0) // file comment length
            centralDirectory.appendUInt16LE(0) // disk number start
            centralDirectory.appendUInt16LE(0) // internal file attributes
            centralDirectory.appendUInt32LE(0) // external file attributes
            centralDirectory.appendUInt32LE(offset)
            centralDirectory.append(fileNameData)

            entryCount = entryCount &+ 1
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset

        archive.appendUInt32LE(0x06054B50)
        archive.appendUInt16LE(0) // number of this disk
        archive.appendUInt16LE(0) // disk where central directory starts
        archive.appendUInt16LE(entryCount)
        archive.appendUInt16LE(entryCount)
        archive.appendUInt32LE(centralDirectorySize)
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0) // comment length

        return archive
    }
}

private enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = 0xEDB88320 ^ (crc >> 1)
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { append(contentsOf: $0) }
    }
}

private extension JSONEncoder {
    static var exportEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private struct ExportPayload: Codable {
    let generatedAt: Date
    let entries: [SymptomEntryExport]
    let medications: [MedicationExport]
}

private struct SymptomEntryExport: Sendable, Codable {
    let id: UUID?
    let identifier: String
    let timestamp: Date
    let severity: Int16
    let headache: Int16
    let nausea: Int16
    let anxiety: Int16
    let note: String?
    let isMenstruating: Bool
    let sentimentLabel: String?
    let sentimentScore: Double?
    let medicationIntakeIdentifiers: [String]

    static func make(from entry: SymptomEntry, identifier: String, medicationIntakeIdentifiers: [String]) -> SymptomEntryExport {
        SymptomEntryExport(
            id: entry.id,
            identifier: identifier,
            timestamp: entry.timestampValue,
            severity: entry.severity,
            headache: entry.headache,
            nausea: entry.nausea,
            anxiety: entry.anxiety,
            note: entry.note,
            isMenstruating: entry.isMenstruating,
            sentimentLabel: entry.sentimentLabel,
            sentimentScore: entry.sentimentScoreValue,
            medicationIntakeIdentifiers: medicationIntakeIdentifiers
        )
    }

    static let csvHeaders = [
        "id",
        "timestamp",
        "severity",
        "headache",
        "nausea",
        "anxiety",
        "note",
        "isMenstruating",
        "sentimentLabel",
        "sentimentScore",
        "medicationIntakeIDs"
    ]

    var csvRow: [String] {
        [
            identifier,
            timestamp.iso8601ExportString,
            String(severity),
            String(headache),
            String(nausea),
            String(anxiety),
            note ?? "",
            String(isMenstruating),
            sentimentLabel ?? "",
            sentimentScore.map { String($0) } ?? "",
            medicationIntakeIdentifiers.joined(separator: "|")
        ]
    }
}

private struct MedicationExport: Sendable, Codable {
    let id: UUID?
    let identifier: String
    let name: String?
    let createdAt: Date?
    let defaultAmount: Decimal?
    let defaultUnit: String?
    let useCase: String?
    let notes: String?
    let isAsNeeded: Bool
    let schedules: [MedicationScheduleExport]
    let intakes: [MedicationIntakeExport]

    static func make(from medication: Medication, identifier: String, schedules: [MedicationScheduleExport], intakes: [MedicationIntakeExport]) -> MedicationExport {
        MedicationExport(
            id: medication.id,
            identifier: identifier,
            name: medication.name,
            createdAt: medication.createdAt,
            defaultAmount: medication.defaultAmountValue,
            defaultUnit: medication.defaultUnit,
            useCase: medication.useCase,
            notes: medication.notes,
            isAsNeeded: medication.isAsNeeded,
            schedules: schedules,
            intakes: intakes
        )
    }

    private var scheduleIdentifiers: [String] {
        schedules.map(\.identifier)
    }

    private var intakeIdentifiers: [String] {
        intakes.map(\.identifier)
    }

    static let csvHeaders = [
        "id",
        "name",
        "createdAt",
        "defaultAmount",
        "defaultUnit",
        "useCase",
        "notes",
        "isAsNeeded",
        "scheduleIDs",
        "intakeIDs"
    ]

    var csvRow: [String] {
        [
            identifier,
            createdAt?.iso8601ExportString ?? "",
            name ?? "",
            defaultAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
            defaultUnit ?? "",
            useCase ?? "",
            notes ?? "",
            String(isAsNeeded),
            scheduleIdentifiers.joined(separator: "|"),
            intakeIdentifiers.joined(separator: "|")
        ]
    }
}

private struct MedicationScheduleExport: Sendable, Codable {
    let id: UUID?
    let identifier: String
    let medicationID: UUID?
    let medicationIdentifier: String
    let label: String?
    let cadence: String
    let interval: Int16
    let weekdays: [Int]
    let hour: Int16
    let minute: Int16
    let amount: Decimal?
    let unit: String?
    let isActive: Bool
    let sortOrder: Int16
    let startDate: Date?
    let timeZoneIdentifier: String?

    static func make(from schedule: MedicationSchedule, identifier: String, medicationIdentifier: String) -> MedicationScheduleExport {
        MedicationScheduleExport(
            id: schedule.id,
            identifier: identifier,
            medicationID: schedule.medication?.id,
            medicationIdentifier: medicationIdentifier,
            label: schedule.label,
            cadence: schedule.cadence ?? MedicationSchedule.Cadence.daily.rawValue,
            interval: schedule.interval,
            weekdays: schedule.weekdays.map(\.rawValue),
            hour: schedule.hour,
            minute: schedule.minute,
            amount: schedule.amountValue,
            unit: schedule.unit,
            isActive: schedule.isActive,
            sortOrder: schedule.sortOrder,
            startDate: schedule.startDate,
            timeZoneIdentifier: schedule.timeZoneIdentifier
        )
    }

    static let csvHeaders = [
        "id",
        "medicationID",
        "label",
        "cadence",
        "interval",
        "weekdays",
        "hour",
        "minute",
        "amount",
        "unit",
        "isActive",
        "sortOrder",
        "startDate",
        "timeZoneIdentifier"
    ]

    var csvRow: [String] {
        [
            identifier,
            medicationIdentifier,
            label ?? "",
            cadence,
            String(interval),
            weekdays.map(String.init).joined(separator: "|"),
            String(hour),
            String(minute),
            amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
            unit ?? "",
            String(isActive),
            String(sortOrder),
            startDate?.iso8601ExportString ?? "",
            timeZoneIdentifier ?? ""
        ]
    }
}

private struct MedicationIntakeExport: Sendable, Codable {
    let id: UUID?
    let identifier: String
    let medicationID: UUID?
    let medicationIdentifier: String
    let entryID: UUID?
    let entryIdentifier: String?
    let scheduleID: UUID?
    let scheduleIdentifier: String?
    let origin: String
    let timestamp: Date
    let scheduledDate: Date?
    let amount: Decimal?
    let unit: String?
    let notes: String?

    static func make(from intake: MedicationIntake, identifier: String, medicationIdentifier: String, scheduleIdentifier: String?, entryIdentifier: String?) -> MedicationIntakeExport {
        MedicationIntakeExport(
            id: intake.id,
            identifier: identifier,
            medicationID: intake.medication?.id,
            medicationIdentifier: medicationIdentifier,
            entryID: intake.entry?.id,
            entryIdentifier: entryIdentifier,
            scheduleID: intake.schedule?.id,
            scheduleIdentifier: scheduleIdentifier,
            origin: intake.originValue.rawValue,
            timestamp: intake.timestampValue,
            scheduledDate: intake.scheduledDate,
            amount: intake.amountValue,
            unit: intake.unit,
            notes: intake.notes
        )
    }

    static let csvHeaders = [
        "id",
        "medicationID",
        "entryID",
        "scheduleID",
        "origin",
        "timestamp",
        "scheduledDate",
        "amount",
        "unit",
        "notes"
    ]

    var csvRow: [String] {
        [
            identifier,
            medicationIdentifier,
            entryIdentifier ?? "",
            scheduleIdentifier ?? "",
            origin,
            timestamp.iso8601ExportString,
            scheduledDate?.iso8601ExportString ?? "",
            amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
            unit ?? "",
            notes ?? ""
        ]
    }
}
