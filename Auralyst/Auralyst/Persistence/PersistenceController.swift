import CloudKit
import CoreData
import os.log

// PersistenceController wires Core Data to CloudKit with private + shared stores.
final class PersistenceController {
    static let shared = PersistenceController()
    static let preview = PersistenceController(inMemory: true)

    static let transactionAuthor = "app"

    let container: NSPersistentCloudKitContainer

    private let historyQueue = DispatchQueue(label: "com.yourteam.auralyst.history")
    private var historyToken: NSPersistentHistoryToken?
    private let isInMemory: Bool

    private init(inMemory: Bool = false) {
        self.isInMemory = inMemory
        let modelName = "Auralyst"
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd"),
              let baseModel = NSManagedObjectModel(contentsOf: modelURL),
              let model = baseModel.mutableCopy() as? NSManagedObjectModel else {
            fatalError("Failed to load managed object model \(modelName)")
        }

        for entity in model.entities {
            for attribute in entity.attributesByName.values {
                attribute.isOptional = true
            }

            for relationship in entity.relationshipsByName.values {
                relationship.minCount = 0
            }
        }

        for configuration in model.configurations {
            if (model.entities(forConfigurationName: configuration) ?? []).isEmpty {
                model.setEntities(model.entities, forConfigurationName: configuration)
            }
        }

        container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)

        let defaultDirectory = NSPersistentContainer.defaultDirectoryURL()
        let privateStoreURL = defaultDirectory.appending(path: "Auralyst.sqlite")
        let sharedStoreURL = defaultDirectory.appending(path: "Auralyst-shared.sqlite")

        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitConfig.containerIdentifier)
        privateOptions.databaseScope = .private

        let privateStoreDescription = NSPersistentStoreDescription(url: privateStoreURL)
        privateStoreDescription.configuration = "Default"
        privateStoreDescription.cloudKitContainerOptions = privateOptions
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitConfig.containerIdentifier)
        sharedOptions.databaseScope = .shared

        let sharedStoreDescription = NSPersistentStoreDescription(url: sharedStoreURL)
        sharedStoreDescription.configuration = "Shared"
        sharedStoreDescription.cloudKitContainerOptions = sharedOptions
        sharedStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if inMemory {
            privateStoreDescription.url = URL(filePath: "/dev/null")
            sharedStoreDescription.url = URL(filePath: "/dev/null")
        }

        container.persistentStoreDescriptions = [privateStoreDescription, sharedStoreDescription]

        container.loadPersistentStores { description, error in
            if let error {
                os_log("Failed to load store: %{public}@", log: .default, type: .fault, error.localizedDescription)
                fatalError("Unresolved Core Data error \(error)")
            }

            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.transactionAuthor = Self.transactionAuthor

        historyToken = Self.loadHistoryToken()

        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            if let userInfo = notification.userInfo {
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: [self.container.viewContext])
            }
            self.processPersistentHistory()
        }

        if isInMemory == false {
            processPersistentHistory()
        }

        #if DEBUG
        if ProcessInfo.processInfo.environment["GENERATE_CLOUDKIT_SCHEMA"] == "1" {
            do {
                try container.initializeCloudKitSchema(options: [.printSchema])
            } catch {
                os_log("CloudKit schema init error: %{public}@", log: .default, type: .debug, error.localizedDescription)
            }
        }
        #endif
    }

    // MARK: Background Contexts

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        configureBackground(context)
        return context
    }

    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            self.configureBackground(context)
            block(context)
        }
    }

    private func configureBackground(_ context: NSManagedObjectContext) {
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        context.transactionAuthor = Self.transactionAuthor
    }

    // MARK: Persistent History

    private func processPersistentHistory() {
        historyQueue.async { [weak self] in
            guard let self else { return }
            let taskContext = self.container.newBackgroundContext()
            taskContext.performAndWait {
                let historyRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: self.historyToken)
                historyRequest.fetchRequest = NSPersistentHistoryTransaction.fetchRequest

                do {
                    guard let result = try taskContext.execute(historyRequest) as? NSPersistentHistoryResult,
                          let transactions = result.result as? [NSPersistentHistoryTransaction],
                          transactions.isEmpty == false else {
                        return
                    }

                    let remoteTransactions = transactions.filter { $0.author != Self.transactionAuthor }
                    self.merge(transactions: remoteTransactions)

                    if let lastToken = transactions.last?.token {
                        self.historyToken = lastToken
                        if self.isInMemory == false {
                            Self.storeHistoryToken(lastToken)
                        }
                    }
                } catch {
                    os_log("History fetch failed: %{public}@", log: .default, type: .error, error.localizedDescription)
                }
            }
        }
    }

    private func merge(transactions: [NSPersistentHistoryTransaction]) {
        guard transactions.isEmpty == false else { return }
        let viewContext = container.viewContext
        viewContext.perform {
            transactions.forEach { transaction in
                let notification = transaction.objectIDNotification()
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: notification.userInfo ?? [:], into: [viewContext])
            }
        }
    }

    private static func historyTokenURL() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let folderURL = baseURL.appending(path: "Auralyst", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: folderURL.path) == false {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        return folderURL.appending(path: "history-token.data")
    }

    private static func loadHistoryToken() -> NSPersistentHistoryToken? {
        let url = historyTokenURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    private static func storeHistoryToken(_ token: NSPersistentHistoryToken) {
        let url = historyTokenURL()
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            try? data.write(to: url)
        }
    }
}

enum CloudKitConfig {
    static let containerIdentifier = "iCloud.Auralyst"
}
