import Foundation
import Dependencies
import SQLiteData

struct JournalShareResolver {
    var sharedJournalIDs: @Sendable (_ ids: [UUID]) throws -> Set<UUID>
}

extension JournalShareResolver {
    static let noop = JournalShareResolver { _ in [] }
}

private enum JournalShareResolverKey: DependencyKey {
    static let liveValue: JournalShareResolver = .live
    static let testValue: JournalShareResolver = .noop
    static let previewValue: JournalShareResolver = .noop
}

extension DependencyValues {
    var journalShareResolver: JournalShareResolver {
        get { self[JournalShareResolverKey.self] }
        set { self[JournalShareResolverKey.self] = newValue }
    }
}

private extension JournalShareResolver {
    static var live: JournalShareResolver {
        JournalShareResolver { ids in
            guard !ids.isEmpty else { return [] }
            @Dependency(\.defaultDatabase) var database
            return try database.read { db in
                var shared = Set<UUID>()
                for id in ids {
                    let isShared = try SQLiteJournal
                        .metadata(for: id)
                        .select(\.isShared)
                        .fetchOne(db) ?? false
                    if isShared {
                        shared.insert(id)
                    }
                }
                return shared
            }
        }
    }
}
