# Auralyst — Technical Implementation Spec



**One-liner:** Auralyst keeps the log, spots the patterns, and nudges when it matters.

- **Platforms:** iOS (primary), macOS (optional), watchOS (optional)
- **UI:** SwiftUI
- **Persistence & Sync:** Core Data + CloudKit (`NSPersistentCloudKitContainer`)
- **Collaboration:** CloudKit zone sharing (read/write) between iCloud users
- **Offline:** Full offline capability; eventual cloud sync
- **Privacy:** iCloud (Apple ID auth), on-device Core Data store



---



## 0. Branding & Visual System

**Name:** Auralyst
**Tone:** Calm, capable, quietly helpful (assistant vibe, not AI-forward)

**Palette**

- Ink (text): `#0F172A` (slate-900)
- Primary (actions/line): `#2563EB` (blue-600)
- Primary (dark mode line): `#60A5FA` (blue-400)
- Accent (cue/insight): `#F59E0B` (amber-500) / dark `#FBBF24`
- Surface light: `#F8FAFC` (slate-50)
- Surface dark: `#0B1220`

**Typography**

- UI: SF Pro (system); Display: **Manrope** _or_ **Inter** (TBD)
- Weight usage: 600/700 for headings; 400/500 for body

**Icon**

- “Quiet Trendline”: rising line with two round nodes (owner + collaborator).  
- SVGs provided (glyph, light/dark tiles, favicon). Keep line thin; grid subtle.

**Microcopy**

- Empty state: “Start with today. Auralyst will trace the line.”
- Insight toast: “Noticed 3 mornings this week with level ≥7. Tag wake time?”
- Share CTA: “Invite a partner to add notes. You stay in control.”



---



## 1. Why Core Data + CloudKit (not SwiftData)

**We choose Core Data + CloudKit** because we need **multi-user sharing across iCloud accounts** with read/write collaboration.

- **SwiftData (iOS 17+)**: great for single-user iCloud sync (same Apple ID), but **no first-class support for collaborative sharing** (CKShare/zone sharing) across different iCloud accounts. Also lacks the mature tooling for multi-store setups (private + shared).
- **Core Data + `NSPersistentCloudKitContainer`**:
  - Proven, production-ready CloudKit mirroring.
  - Supports **two stores**: user’s **private** DB and **shared** DB (records shared with the user).
  - Built-in **CloudKit zone sharing** (read/write participants), using `CKShare`.
  - **Offline-first** by design with local persistence; background mirroring to iCloud.
  - **Notifications & history** for merging remote changes safely.

Result: secure, Apple-native, no separate auth or servers, and collaborators see updates with low latency (eventual consistency).



---



## 2. Data Model (Core Data)

Create a Core Data model `Auralyst.xcdatamodeld` with these entities:

### `Journal` (the shareable root)

- `id: UUID` (indexed, unique)
- `createdAt: Date`
- Relationships:
  - `entries: [SymptomEntry]` (to-many, cascade)
  - `collabNotes: [CollaboratorNote]` (to-many, cascade)

> **Why a root?** Sharing the `Journal` shares its **entire object graph** (entries + notes) via CloudKit zone sharing. It gives one “thing” to share/manage.

### `SymptomEntry`

- `id: UUID`
- `timestamp: Date` (default: now)
- Severity fields (choose one of two patterns):
  - **Single overall severity:** `severity: Int16 (1–10)`
  - **Per-symptom severities:** `headache: Int16`, `nausea: Int16`, `anxiety: Int16` (nullable if unused)
- `medication: String?` (free text, or normalize later)
- `note: String?`
- Rel:
  - `journal: Journal` (to-one, required)

### `CollaboratorNote`

- `id: UUID`
- `timestamp: Date` (default: now)
- `text: String`
- `authorName: String?` (optional display)
- `entryRef: SymptomEntry?` (optional: note tied to a specific entry)
- Rel:
  - `journal: Journal` (to-one, required)

> Keep the collaborator’s notes **distinct** so they never overwrite the owner’s log; show them in a parallel lane.



---



## 3. Core Data + CloudKit Stack

### 3.1 Entitlements & Capabilities

- Enable **iCloud** with **CloudKit** in all targets (iOS/macOS/watchOS).
- Use **the same CloudKit container** (e.g., `iCloud.com.yourteam.auralyst`).
- Background modes: **Remote notifications** (for push-driven sync).

### 3.2 Persistent Container

- Use **`NSPersistentCloudKitContainer`**.
- Configure **two store descriptions**:
  - Private store → `databaseScope = .private`
  - Shared store → `databaseScope = .shared`
- Enable:
  - `NSPersistentHistoryTrackingKey = true`
  - `NSPersistentStoreRemoteChangeNotificationPostOptionKey = true`

**Example (`Persistence.swift`):**

```swift
import CoreData
import CloudKit

final class Persistence {
    static let shared = Persistence()

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore!
    private(set) var sharedStore: NSPersistentStore!

    private init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Auralyst")

        // URLs
        let storeDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let privateURL = storeDir.appendingPathComponent("Auralyst-Private.sqlite")
        let sharedURL  = storeDir.appendingPathComponent("Auralyst-Shared.sqlite")

        // Private store
        let privateDesc = NSPersistentStoreDescription(url: privateURL)
        privateDesc.configuration = "Default" // if you use configurations
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.yourteam.auralyst")
        privateOptions.databaseScope = .private
        privateDesc.cloudKitContainerOptions = privateOptions

        // Shared store
        let sharedDesc = NSPersistentStoreDescription(url: sharedURL)
        sharedDesc.configuration = "Default"
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.yourteam.auralyst")
        sharedOptions.databaseScope = .shared
        sharedDesc.cloudKitContainerOptions = sharedOptions

        container.persistentStoreDescriptions = [privateDesc, sharedDesc]

        container.loadPersistentStores { [weak self] desc, error in
            guard let self = self else { return }
            if let error = error { fatalError("Persistent store load failed: \(error)") }
            if desc.cloudKitContainerOptions?.databaseScope == .private { self.privateStore = self.container.persistentStoreCoordinator.persistentStore(for: desc.url!) }
            if desc.cloudKitContainerOptions?.databaseScope == .shared  { self.sharedStore  = self.container.persistentStoreCoordinator.persistentStore(for: desc.url!) }
            self.container.viewContext.automaticallyMergesChangesFromParent = true
            self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }

        // Optional (dev only): create CK schema
        // try? container.initializeCloudKitSchema(options: [])
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }
}
```



### **3.3 Filtering by Store (Private vs Shared)**

When fetching, you can target a specific store using affectedStores.

```
func fetchJournals(in store: NSPersistentStore?, context: NSManagedObjectContext) throws -> [Journal] {
    let req: NSFetchRequest<Journal> = Journal.fetchRequest()
    if let store = store {
        req.affectedStores = [store]
    }
    return try context.fetch(req)
}
```

- Owner device: show the **private** journal (and any inbound **shared** journals if they’ve joined others’ shares).
- Collaborator device: typically show the **shared** journal.



### **3.4 Remote Change Handling**

Listen for NSPersistentStoreRemoteChange and merge.

```
extension Persistence {
    func startObservingRemoteChanges() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
            // Optionally process history here if you need granular handling
            self.container.viewContext.perform {
                self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                // Minimal merge if using automaticallyMergesChangesFromParent
            }
        }
    }
}
```

> For advanced flows, process NSPersistentHistoryTransaction entries to drive UI badges/cues.



------



## **4. Sharing (CloudKit Zone Sharing)**



### **4.1 Initiate Share (Owner)**

- Create or locate the owner’s Journal (1 per user).
- Use NSPersistentCloudKitContainer.share(_:to:) to produce a CKShare.
- Present UICloudSharingController so the user can invite (Messages/Email/AirDrop).
- Set permission to **allow read/write**.



```
import UIKit
import CloudKit
import CoreData

final class ShareController: NSObject, UICloudSharingControllerDelegate {

    let container = Persistence.shared.container

    func presentShare(for journal: Journal, from presenter: UIViewController) {
        let context = container.viewContext
        container.share([journal], to: nil) { share, ccContainer, error in
            if let error = error { print("Share error: \(error)"); return }

            guard let share = share, let ckContainer = ccContainer else { return }
            // Optional: set title
            share[CKShare.SystemFieldKey.title] = "Auralyst Journal" as CKRecordValue

            let sharingVC = UICloudSharingController(share: share, container: ckContainer)
            sharingVC.modalPresentationStyle = .formSheet
            sharingVC.delegate = self
            DispatchQueue.main.async { presenter.present(sharingVC, animated: true) }
        }
    }

    // UICloudSharingControllerDelegate
    func itemTitle(for csc: UICloudSharingController) -> String? { "Auralyst Journal" }
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Failed to save share: \(error)")
    }
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { print("Share saved") }
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { print("Stopped sharing") }
}
```



### **4.2 Accept Share (Collaborator)**

- Implement application(_:userDidAcceptCloudKitShareWith:) in App Delegate.
- Call container.acceptShareInvitations(from:into:) to persist into the **shared** store.



```
import UIKit
import CloudKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        let persistence = Persistence.shared
        // Persist into the shared store
        persistence.container.acceptShareInvitations(from: [metadata], into: persistence.sharedStore) { _, error in
            if let error = error { print("Accept share error: \(error)") }
            else { print("Share accepted into shared store") }
        }
    }
}
```

**Info.plist**

- Ensure **CloudKit** entitlements enabled.
- Add CKSharingSupported (Boolean) in Info.plist (for best compatibility when using UICloudSharingController).
- Deep link handling is automatic via CloudKit share URLs.



### **4.3 Permissions**

- Use UICloudSharingController to set **Allow Editing** (read/write) for invitees.
- Owner can manage participants or stop sharing via the same controller.



### **4.4 Data Flow**

- Owner logs entries → mirrored to **private** DB.
- Owner shares Journal → a **share zone** is created; all related objects included.
- Collaborator accepts → objects appear in **shared** DB on collaborator device.
- Collaborator adds CollaboratorNote (or comments on entries) → writes to share zone → owner receives via remote change.



> Sync is **eventual**; not guaranteed real-time. Typically fast.



------



## **5. SwiftUI App Structure**



### **5.1 App Entry**

- Inject container.viewContext into environment.
- Start observing remote changes.



```
@main
struct AuralystApp: App {
    let persistence = Persistence.shared

    init() { persistence.startObservingRemoteChanges() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}
```



### **5.2 Views (iOS)**

- **Home/List:** Today + Recent Entries (@FetchRequest on SymptomEntry, grouped by day).
- **Add Entry:** Fast form: severity (1–10), meds (picker/text), note (TextEditor), save.
- **Detail:** Full entry detail; show CollaboratorNote items (if any).
- **Trends:** Swift Charts: line of daily max/avg severity; filters (7/30/90 days).
- **Share:** Button that calls ShareController.presentShare.



**Example Add Entry Save**

```
func addEntry(severity: Int, medication: String?, note: String?) {
    let ctx = Persistence.shared.container.viewContext
    ctx.perform {
        // Ensure a Journal exists (create once, store its objectID)
        let journal = fetchOrCreateJournal(in: ctx)
        let entry = SymptomEntry(context: ctx)
        entry.id = UUID()
        entry.timestamp = Date()
        entry.severity = Int16(severity)
        entry.medication = medication
        entry.note = note
        entry.journal = journal
        try? ctx.save()
    }
}
```

**Collaborator Note**

```
func addCollaboratorNote(text: String, for entry: SymptomEntry?) {
    let ctx = Persistence.shared.container.viewContext
    ctx.perform {
        guard let journal = entry?.journal ?? fetchSharedJournal(in: ctx) else { return }
        let note = CollaboratorNote(context: ctx)
        note.id = UUID()
        note.timestamp = Date()
        note.text = text
        note.entryRef = entry
        note.journal = journal
        try? ctx.save()
    }
}
```



### **5.3 macOS & watchOS**

- **macOS:** Use NavigationSplitView. Same Core Data stack; identical model.
- **watchOS:** Minimal Add Entry (severity picker + dictation note). Use same CloudKit container; sync when network is available.



------



## **6. Insights & Trends**

- Build **Charts** (Swift Charts) for:
  - Rolling **7-day** average severity
  - **Hourly heatmap** (if you later record time-of-day or triggers)
  - **Medication effect** (severity before/after taking)
- Keep insights **quiet**: only surface amber cues when thresholds/trends are meaningful.



------



## **7. Privacy & Security**

- Data is stored locally in Core Data, mirrored to the user’s iCloud container.
- Sharing uses CloudKit **zone sharing** with explicit invitations.
- No third-party servers; no extra logins.
- Offer in-app export (CSV/Markdown) for clinical visits if desired.



------



## **8. Testing Plan**

- **Two iCloud accounts**, two devices:
  1. Owner creates entries → verify iCloud sync across their devices.
  2. Owner shares Journal → collaborator accepts link.
  3. Collaborator sees entries in shared store → adds a CollaboratorNote.
  4. Owner device receives remote change → note appears; conflict-free.
- **Offline tests:** add/edit offline; changes sync on reconnection.
- **Revocation:** stop sharing; verify shared data is removed on collaborator’s device.



------



## **9. Edge Cases & Notes**

- **Conflicts:** Rare with separate CollaboratorNote; default merge policy suffices. For simultaneous edits to the same field, last writer wins.
- **Backups:** CloudKit + local Core Data store; consider local export for reassurance.
- **Migrations:** Use light-weight migrations; keep schema simple.
- **Accessibility:** Maintain ≥ 4.5:1 contrast; Dynamic Type; VoiceOver labels for icons.



------



## **10. Roadmap (Later)**

- Trigger tagging (sleep, hydration, caffeine, weather).
- HealthKit opt-in (headache occurrences if applicable).
- Insight rules (transparent; explainable, not AI-forward).
- Optional Apple Intelligence summaries when confident.
