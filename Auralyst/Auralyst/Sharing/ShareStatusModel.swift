import CloudKit
import Observation

@MainActor
@Observable
final class ShareStatusModel {
    var isLoading = false
    var errorMessage: String?
    var shareInfo: ShareInfo?

    private let shareController: any ShareControlling

    init(shareController: (any ShareControlling)? = nil) {
        self.shareController = shareController ?? ShareController.shared()
    }

    func loadShare(for journal: Journal) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let share = try await shareController.currentShare(for: journal) {
                shareInfo = ShareInfo(share: share)
            } else {
                shareInfo = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopSharing(journal: Journal) async throws {
        try await shareController.stopSharing(journal: journal)
        shareInfo = nil
    }
}

struct ShareInfo {
    struct Participant: Identifiable {
        enum Kind: String {
            case owner
            case privateUser
            case unknown
        }

        enum Acceptance: String {
            case unknown
            case pending
            case accepted
            case removed
        }

        let id: CKRecord.ID
        let displayName: String
        let kind: Kind
        let acceptance: Acceptance
    }

    let title: String
    let participants: [Participant]

    init(share: CKShare) {
        title = share[CKShare.SystemFieldKey.title] as? String ?? "Shared Journal"
        participants = share.participants.map { participant in
            let kind: Participant.Kind
            switch participant.role {
            case .owner:
                kind = .owner
            case .privateUser:
                kind = .privateUser
            default:
                kind = .unknown
            }

            let acceptance: Participant.Acceptance
            switch participant.acceptanceStatus {
            case .pending:
                acceptance = .pending
            case .accepted:
                acceptance = .accepted
            case .removed:
                acceptance = .removed
            default:
                acceptance = .unknown
            }

            let name = participant.userIdentity.lookupInfo?.emailAddress ?? participant.userIdentity.nameComponents?.formatted() ?? "Unknown"

            return Participant(
                id: participant.userIdentity.userRecordID ?? CKRecord.ID(recordName: UUID().uuidString),
                displayName: name,
                kind: kind,
                acceptance: acceptance
            )
        }
    }
}
