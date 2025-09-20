import CloudKit
import CoreData
import Testing
import UIKit

@testable import Auralyst

@MainActor
struct ShareControllerTests {
    @Test func shareControllerRespondsToFailureSelector() async {
        let selector = #selector(UICloudSharingControllerDelegate.cloudSharingController(_:failedToSaveShareWithError:))
        #expect(ShareController.shared().responds(to: selector))
    }
}

@MainActor
struct ShareStatusModelTests {
    @Test func loadSharePopulatesShareInfo() async throws {
        let context = PersistenceController.preview.container.viewContext
        context.reset()

        let journal = Journal(context: context)
        journal.id = UUID()
        journal.createdAt = Date()
        try context.save()

        let record = CKRecord(recordType: "Journal")
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = "Shared Journal"

        let stub = ShareControllerStub(currentShareResult: .success(share))
        let model = ShareStatusModel(shareController: stub)

        await model.loadShare(for: journal)

        #expect(model.isLoading == false)
        #expect(model.errorMessage == nil)
        #expect(model.shareInfo?.title == "Shared Journal")
        #expect(stub.stopSharingCallCount == 0)
    }

    @Test func loadShareHandlesError() async throws {
        let context = PersistenceController.preview.container.viewContext
        context.reset()

        let journal = Journal(context: context)
        journal.id = UUID()
        journal.createdAt = Date()
        try context.save()

        let stub = ShareControllerStub(currentShareResult: .failure(StubError.sample))
        let model = ShareStatusModel(shareController: stub)

        await model.loadShare(for: journal)

        #expect(model.shareInfo == nil)
        #expect(model.errorMessage == StubError.sample.localizedDescription)
    }

    @Test func stopSharingClearsShareInfo() async throws {
        let context = PersistenceController.preview.container.viewContext
        context.reset()

        let journal = Journal(context: context)
        journal.id = UUID()
        journal.createdAt = Date()
        try context.save()

        let record = CKRecord(recordType: "Journal")
        let share = CKShare(rootRecord: record)
        let stub = ShareControllerStub(currentShareResult: .success(share))
        let model = ShareStatusModel(shareController: stub)
        model.shareInfo = ShareInfo(share: share)

        try await model.stopSharing(journal: journal)

        #expect(stub.stopSharingCallCount == 1)
        #expect(model.shareInfo == nil)
    }
}

@MainActor
private final class ShareControllerStub: ShareControlling {
    var currentShareResult: Result<CKShare?, Error>
    var stopSharingResult: Result<Void, Error>
    private(set) var stopSharingCallCount = 0

    init(currentShareResult: Result<CKShare?, Error>, stopSharingResult: Result<Void, Error> = .success(())) {
        self.currentShareResult = currentShareResult
        self.stopSharingResult = stopSharingResult
    }

    func currentShare(for journal: Journal) async throws -> CKShare? {
        switch currentShareResult {
        case .success(let share):
            return share
        case .failure(let error):
            throw error
        }
    }

    func stopSharing(journal: Journal) async throws {
        stopSharingCallCount += 1
        switch stopSharingResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

private enum StubError: Error {
    case sample
}
