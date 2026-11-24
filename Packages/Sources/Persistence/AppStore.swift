import Foundation
import SwiftData

public enum AppStore {
    public static let schema = Schema([
        SDTransaction.self,
        SDBudgetLimit.self,
        SDSavingsGoal.self,
        SDInstallmentPlan.self,
    ])

    /// Shared ModelContainer for both the app UI and background App Intents (Apple Shortcuts).
    /// CloudKit mirroring is explicitly `.none` here because Tally runs its own `CKSyncEngine`
    /// supporting CloudKit Zone Sharing (`CKShare`) between husband and wife across separate Apple IDs.
    public static let container: ModelContainer = {
        let config = ModelConfiguration(
            "Tally",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fallback to in-memory so the app never crashes on launch if store migration fails.
            let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [mem])
        }
    }()
}
