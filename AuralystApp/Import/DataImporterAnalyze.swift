import Foundation

// MARK: - Analysis

extension DataImporter {
    static func analyze(
        _ payload: ImportPayload
    ) -> ImportAnalysis {
        let scheduleIDs = Set(payload.schedules.map { $0.id })
        let entryIDs = Set(payload.entries.map { $0.id })
        let medicationIDs = Set(payload.medications.map { $0.id })

        let fixableIssues = findFixableIssues(
            payload: payload,
            scheduleIDs: scheduleIDs,
            entryIDs: entryIDs
        )
        let blockingIssues = findBlockingIssues(
            payload: payload,
            medicationIDs: medicationIDs
        )

        return ImportAnalysis(
            fixableIssues: fixableIssues,
            blockingIssues: blockingIssues
        )
    }

    private static func findFixableIssues(
        payload: ImportPayload,
        scheduleIDs: Set<UUID>,
        entryIDs: Set<UUID>
    ) -> [ImportIssue] {
        let missingScheduleIntakes = payload.intakes.filter {
            guard let sid = $0.scheduleID else { return false }
            return !scheduleIDs.contains(sid)
        }
        let realMissing = missingScheduleIntakes.filter {
            guard let sid = $0.scheduleID else { return false }
            return sid != $0.medicationID
        }
        let missingIntakeEntryRefs = payload.intakes.filter {
            guard let eid = $0.entryID else { return false }
            return !entryIDs.contains(eid)
        }
        let missingNoteEntryRefs = payload.collaboratorNotes.filter {
            guard let eid = $0.entryID else { return false }
            return !entryIDs.contains(eid)
        }

        var issues: [ImportIssue] = []
        if !realMissing.isEmpty {
            issues.append(ImportIssue(
                kind: .missingScheduleReferences,
                count: realMissing.count,
                examples: realMissing.prefix(3).map {
                    "\($0.id.uuidString) -> \($0.scheduleID?.uuidString ?? "nil")"
                },
                isFixable: true
            ))
        }
        if !missingIntakeEntryRefs.isEmpty {
            issues.append(ImportIssue(
                kind: .missingIntakeEntryReferences,
                count: missingIntakeEntryRefs.count,
                examples: missingIntakeEntryRefs.prefix(3).map {
                    "\($0.id.uuidString) -> \($0.entryID?.uuidString ?? "nil")"
                },
                isFixable: true
            ))
        }
        if !missingNoteEntryRefs.isEmpty {
            issues.append(ImportIssue(
                kind: .missingNoteEntryReferences,
                count: missingNoteEntryRefs.count,
                examples: missingNoteEntryRefs.prefix(3).map {
                    "\($0.id.uuidString) -> \($0.entryID?.uuidString ?? "nil")"
                },
                isFixable: true
            ))
        }
        return issues
    }

    private static func findBlockingIssues(
        payload: ImportPayload,
        medicationIDs: Set<UUID>
    ) -> [ImportIssue] {
        let journalID = payload.journal.id
        let entryMismatches = payload.entries.filter {
            $0.journalID != journalID
        }
        let medMismatches = payload.medications.filter {
            $0.journalID != journalID
        }
        let noteMismatches = payload.collaboratorNotes.filter {
            $0.journalID != journalID
        }
        let mismatchCount = entryMismatches.count
            + medMismatches.count + noteMismatches.count

        let missingMedSchedules = payload.schedules.filter {
            !medicationIDs.contains($0.medicationID)
        }
        let missingMedIntakes = payload.intakes.filter {
            !medicationIDs.contains($0.medicationID)
        }

        var issues: [ImportIssue] = []
        if mismatchCount > 0 {
            let examples =
                entryMismatches.prefix(1).map { $0.id.uuidString }
                + medMismatches.prefix(1).map { $0.id.uuidString }
                + noteMismatches.prefix(1).map { $0.id.uuidString }
            issues.append(ImportIssue(
                kind: .journalMismatch,
                count: mismatchCount,
                examples: examples,
                isFixable: false
            ))
        }
        if !missingMedSchedules.isEmpty
            || !missingMedIntakes.isEmpty {
            let schedExamples = missingMedSchedules.prefix(2).map {
                "\($0.id.uuidString) -> \($0.medicationID.uuidString)"
            }
            let intakeExamples = missingMedIntakes.prefix(2).map {
                "\($0.id.uuidString) -> \($0.medicationID.uuidString)"
            }
            issues.append(ImportIssue(
                kind: .missingMedicationReferences,
                count: missingMedSchedules.count
                    + missingMedIntakes.count,
                examples: schedExamples + intakeExamples,
                isFixable: false
            ))
        }
        return issues
    }
}

// MARK: - Validation

extension DataImporter {
    static func validate(_ payload: ImportPayload) throws {
        try validateJournalRefs(payload)
        try validateMedicationRefs(payload)
        try validateScheduleRefs(payload)
        try validateEntryRefs(payload)
    }

    private static func validateJournalRefs(
        _ payload: ImportPayload
    ) throws {
        let journalID = payload.journal.id
        if payload.entries.contains(where: {
            $0.journalID != journalID
        }) {
            throw ImportError.invalidPayload(
                "One or more symptom entries reference a different journal."
            )
        }
        if payload.medications.contains(where: {
            $0.journalID != journalID
        }) {
            throw ImportError.invalidPayload(
                "One or more medications reference a different journal."
            )
        }
        if payload.collaboratorNotes.contains(where: {
            $0.journalID != journalID
        }) {
            throw ImportError.invalidPayload(
                "One or more collaborator notes reference a different journal."
            )
        }
    }

    private static func validateMedicationRefs(
        _ payload: ImportPayload
    ) throws {
        let medicationIDs = Set(payload.medications.map { $0.id })
        if payload.schedules.contains(where: {
            !medicationIDs.contains($0.medicationID)
        }) {
            throw ImportError.invalidPayload(
                "One or more schedules reference missing medications."
            )
        }
        if payload.intakes.contains(where: {
            !medicationIDs.contains($0.medicationID)
        }) {
            throw ImportError.invalidPayload(
                "One or more intakes reference missing medications."
            )
        }
    }

    private static func validateScheduleRefs(
        _ payload: ImportPayload
    ) throws {
        let scheduleIDs = Set(payload.schedules.map { $0.id })
        if payload.intakes.contains(where: { intake in
            guard let sid = intake.scheduleID else { return false }
            return !scheduleIDs.contains(sid)
        }) {
            throw ImportError.invalidPayload(
                "One or more intakes reference missing schedules."
            )
        }
    }

    private static func validateEntryRefs(
        _ payload: ImportPayload
    ) throws {
        let entryIDs = Set(payload.entries.map { $0.id })
        if payload.collaboratorNotes.contains(where: { note in
            guard let eid = note.entryID else { return false }
            return !entryIDs.contains(eid)
        }) {
            throw ImportError.invalidPayload(
                "One or more collaborator notes reference missing symptom entries."
            )
        }
        if payload.intakes.contains(where: { intake in
            guard let eid = intake.entryID else { return false }
            return !entryIDs.contains(eid)
        }) {
            throw ImportError.invalidPayload(
                "One or more intakes reference missing symptom entries."
            )
        }
    }
}
