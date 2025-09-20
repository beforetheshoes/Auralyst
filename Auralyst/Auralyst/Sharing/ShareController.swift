import CloudKit
import CoreData
import os
import UIKit

@MainActor
protocol ShareControlling: AnyObject {
    func currentShare(for journal: Journal) async throws -> CKShare?
    func stopSharing(journal: Journal) async throws
}

@MainActor
final class ShareController: NSObject, UICloudSharingControllerDelegate, ShareControlling {
    private static var cachedShared: ShareController?

    private let persistence: PersistenceController
    private let logger = Logger(subsystem: "com.yourteam.Auralyst", category: "Sharing")

    init(persistence: PersistenceController? = nil) {
        self.persistence = persistence ?? .shared
    }

    static func shared() -> ShareController {
        if let controller = cachedShared {
            return controller
        }

        let controller = ShareController()
        cachedShared = controller
        return controller
    }

    func sharingController(for journal: Journal) -> UIViewController {
        if #available(iOS 16.0, macCatalyst 16.0, *) {
            return makeActivitySharingController(for: journal)
        } else {
            return makeLegacySharingController(for: journal)
        }
    }

    @available(iOS 16.0, macCatalyst 16.0, *)
    private func makeActivitySharingController(for journal: Journal) -> UIViewController {
        let provider = NSItemProvider()
        provider.suggestedName = "Auralyst Journal"

        let container = CKContainer(identifier: CloudKitConfig.containerIdentifier)

        let journalID = journal.objectID

        provider.registerCKShare(container: container) { [weak self] in
            guard let self else { throw ShareError.missingJournal }
            let (share, _) = try await self.prepareShare(journalID: journalID)
            return share
        }

        let configuration = UIActivityItemsConfiguration(itemProviders: [provider])
        let controller = UIActivityViewController(activityItemsConfiguration: configuration)
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    @available(iOS, introduced: 10.0, deprecated: 17.0)
    private func makeLegacySharingController(for journal: Journal) -> UICloudSharingController {
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            preconditionFailure("Legacy sharing controller should not be used on modern platforms")
        }

        let journalID = journal.objectID

        let controller = UICloudSharingController { [weak self] _, completion in
            guard let self else {
                completion(nil, nil, ShareError.missingJournal)
                return
            }

            Task(priority: .userInitiated) {
                do {
                    let (share, container) = try await self.prepareShare(journalID: journalID)
                    completion(share, container, nil)
                } catch {
                    completion(nil, nil, error)
                }
            }
        }

        controller.delegate = self
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    @MainActor
    private func prepareShare(journalID: NSManagedObjectID) async throws -> (CKShare, CKContainer) {
        guard
            let journal = try? persistence.container.viewContext.existingObject(with: journalID) as? Journal
        else {
            throw ShareError.missingJournal
        }

        do {
            let existingShare = try await self.currentShare(for: journal)
            let (_, share, container) = try await self.persistence.container.share([journal], to: existingShare)
            share[CKShare.SystemFieldKey.title] = "Auralyst Journal"
            return (share, container)
        } catch {
            self.logger.error("CloudKit share failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        logger.log("Saved CloudKit share")
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        logger.log("Stopped sharing CloudKit journal")
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
        logger.error("CloudKit share failed to save: \(error.localizedDescription, privacy: .public)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        "Auralyst Journal"
    }

    func currentShare(for journal: Journal) async throws -> CKShare? {
        do {
            let shares = try persistence.container.fetchShares(matching: [journal.objectID])
            return shares[journal.objectID]
        } catch {
            let nsError = error as NSError
            if nsError.domain == CKErrorDomain,
               nsError.code == CKError.partialFailure.rawValue,
               let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
               partialErrors.values.allSatisfy({ ($0 as NSError).code == CKError.unknownItem.rawValue }) {
                return nil
            }
            throw error
        }
    }

    func stopSharing(journal: Journal) async throws {
        guard let share = try await currentShare(for: journal) else {
            return
        }

        let container = CKContainer(identifier: CloudKitConfig.containerIdentifier)
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [share.recordID])
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.privateCloudDatabase.add(operation)
        }
    }
}

extension ShareController {
    enum ShareError: Error {
        case missingJournal
    }
}
