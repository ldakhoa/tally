import AppServices
import AssistantUI
import BudgetsUI
import BudgetKit
import CloudKit
import DesignSystem
import GoalsUI
import OverviewUI
import Persistence
import SettingsUI
import SharedUI
import SwiftData
import SwiftUI
import TallyCore
import TransactionsUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@main
struct TallyApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(TallyAppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(TallyMacAppDelegate.self) private var macAppDelegate
    #endif

    @State private var settings = AppSettings()
    @State private var store = BudgetStore()
    @State private var cloudSync = CloudSync()
    @State private var emailInbox = EmailInboxSync()
    @State private var assistant = AssistantService()
    @State private var router = TabRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabs(router: router)
                .appTint()
                .environment(settings)
                .environment(store)
                .environment(cloudSync)
                .environment(emailInbox)
                .environment(assistant)
                #if os(macOS)
                .frame(minWidth: 780, minHeight: 580)
                #endif
                .task {
                    settings.refreshKeychain()
                    cloudSync.start(settings: settings, store: store)
                    store.reconcileMemberIdentities(settings: settings, notifyCloud: true)
                    store.deduplicateExistingTransactions(notifyCloud: true)
                    emailInbox.syncIfConfigured(settings: settings, store: store)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.reload()
                        settings.refreshKeychain()
                        cloudSync.appBecameActive()
                        emailInbox.syncIfConfigured(settings: settings, store: store)
                    }
                }
                .onOpenURL { url in
                    Task { await handleDeepLink(url) }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 780)
        #endif
        .modelContainer(AppStore.container)
        .commands {
            TallyCommands(router: router, settings: settings, store: store, cloudSync: cloudSync)
            #if os(macOS)
            SidebarCommands()
            #endif
        }
    }

    /// Fallback URL scheme for Apple Shortcuts or Share Sheets:
    /// `tally://log?text=TK+1903+-125000+VND+tai+Highlands&source=bankEmail`
    /// or `tally://log?amount=18.50&merchant=FairPrice&source=applePay`
    private func handleDeepLink(_ url: URL) async {
        guard url.scheme?.lowercased() == "tally" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name.lowercased(), $0) }
        })

        let source = query["source"].flatMap(TransactionSource.init(rawValue:)) ?? .shortcut

        if let amountStr = query["amount"], let amount = Double(amountStr), amount > 0 {
            let merchant = query["merchant"] ?? query["name"] ?? "Transaction"
            let type = query["type"].flatMap(TransactionType.init(rawValue:)) ?? .expense
            let category = query["category"].flatMap(CategoryID.init(rawValue:))
                ?? LocalTransactionParser.inferCategory(text: merchant, type: type)
            BudgetStore.ingestFromShortcut(
                name: merchant,
                amountMajor: amount,
                type: type,
                category: category,
                note: query["note"] ?? query["card"] ?? "",
                source: source
            )
            return
        }

        if let rawText = query["text"], !rawText.isEmpty {
            let client = settings.autoParseWithAI ? settings.makeAIClient() : nil
            if let parsed = await AITransactionParser.parse(
                text: rawText,
                source: source,
                defaultCurrency: settings.currency,
                language: settings.language,
                client: client
            ) {
                let resolved = AITransactionParser.resolvedAmountAndNote(
                    for: parsed,
                    targetCurrency: settings.currency,
                    language: settings.language
                )
                BudgetStore.ingestFromShortcut(
                    name: parsed.name,
                    amountMajor: settings.currency.toMajor(max(1, resolved.amountMinor)),
                    type: parsed.type,
                    category: parsed.category,
                    dayKey: parsed.dayKey,
                    note: resolved.note,
                    source: source,
                    rawSourceText: rawText
                )
            }
        }
    }
}

#if os(iOS)
final class TallyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = TallySceneDelegate.self
        return config
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        CloudSync.acceptShareWhenReady(cloudKitShareMetadata)
    }
}

final class TallySceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        CloudSync.acceptShareWhenReady(cloudKitShareMetadata)
    }
}
#elseif os(macOS)
final class TallyMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        CloudSync.acceptShareWhenReady(metadata)
    }
}
#endif
