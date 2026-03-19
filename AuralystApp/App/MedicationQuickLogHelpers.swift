import ComposableArchitecture
import Foundation
@preconcurrency import SQLiteData
import SwiftUI

extension Notification.Name {
    static let medicationsDidChange = Notification.Name(
        "com.auralyst.medicationsDidChange"
    )
    static let medicationIntakesDidChange = Notification.Name(
        "com.auralyst.medicationIntakesDidChange"
    )
}

extension Double {
    var cleanAmount: String {
        if floor(self) == self { return String(Int(self)) }
        return String(self)
    }
}

#Preview {
    withPreviewDataStore {
        let journal = DependencyValues._current
            .databaseClient.createJournal()
        List {
            MedicationQuickLogSection(
                store: Store(
                    initialState: MedicationQuickLogFeature.State(
                        journalID: journal.id
                    )
                ) {
                    MedicationQuickLogFeature()
                },
                manageAction: {},
                loggingError: nil,
                presentAsNeeded: { _, _ in }
            )
        }
    }
}
