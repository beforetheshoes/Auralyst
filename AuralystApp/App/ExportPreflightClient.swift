import Dependencies
import Foundation
@preconcurrency import SQLiteData

struct ExportPreflightClient {
    var check: @Sendable (SQLiteJournal) async throws -> ExportPreflightReport
    var autoFix: @Sendable (SQLiteJournal) async throws -> ExportPreflightReport
}

private enum ExportPreflightClientKey: DependencyKey {
    static let liveValue = ExportPreflightClient(
        check: { journal in
            try await Task.detached {
                try ExportPreflightChecker.check(journal: journal)
            }.value
        },
        autoFix: { journal in
            try await Task.detached {
                try ExportPreflightChecker.autoFix(journal: journal)
            }.value
        }
    )

    static let testValue = ExportPreflightClient(
        check: { _ in ExportPreflightReport(issues: []) },
        autoFix: { _ in ExportPreflightReport(issues: []) }
    )
}

extension DependencyValues {
    var exportPreflightClient: ExportPreflightClient {
        get { self[ExportPreflightClientKey.self] }
        set { self[ExportPreflightClientKey.self] = newValue }
    }
}
