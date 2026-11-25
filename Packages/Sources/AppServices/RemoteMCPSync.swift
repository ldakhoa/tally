import BudgetKit
import Foundation
import MCPKit
import Observation
import TallyCore

/// Keeps the always-on Cloud MCP Cloudflare Worker (`tools/mcp-server`) bidirectionally synced
/// with `BudgetStore`: pushes local/iCloud edits automatically (2s debounce) and pulls any
/// transactions, budgets, goals, or plans added/edited by external AI assistants, forwarding
/// those into iCloud via `notifyCloud: true`.
@MainActor
@Observable
public final class RemoteMCPSync {
    public private(set) var isSyncing = false
    public private(set) var lastSynced: Date?
    public private(set) var lastError: String?
    public private(set) var lastMCPCallAt: Date?
    public private(set) var lastMCPTool: String?
    public private(set) var vaultRevision: Int = 0
    public private(set) var pairingCode: String?
    public private(set) var pairingCodeExpiresAt: Date?
    public private(set) var isRequestingPairingCode = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let transport: any RemoteMCPHTTPTransport
    @ObservationIgnored private let credentialsProvider: @Sendable () -> KeychainStore.CloudMCPCredentials?
    @ObservationIgnored private weak var observedStore: BudgetStore?
    @ObservationIgnored private var observerID: UUID?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var isApplyingRemoteChanges = false
    @ObservationIgnored private var needsResync = false

    public init(
        defaults: UserDefaults = .standard,
        transport: any RemoteMCPHTTPTransport = URLSessionRemoteMCPTransport(),
        credentialsProvider: @escaping @Sendable () -> KeychainStore.CloudMCPCredentials? = {
            KeychainStore.readCloudMCPCredentials()
        }
    ) {
        self.defaults = defaults
        self.transport = transport
        self.credentialsProvider = credentialsProvider
    }

    public func attach(settings: AppSettings, store: BudgetStore) {
        if let observedStore, let observerID {
            observedStore.removeMutationObserver(observerID)
        }
        observedStore = store
        observerID = store.addMutationObserver { [weak self, weak settings, weak store] in
            guard let self, let settings, let store else { return }
            self.scheduleSync(settings: settings, store: store)
        }
    }

    public func syncIfConfigured(settings: AppSettings, store: BudgetStore) {
        guard settings.isCloudMCPConfigured, !isSyncing else { return }
        Task {
            await syncNow(settings: settings, store: store)
        }
    }

    public func scheduleSync(settings: AppSettings, store: BudgetStore, delay: Duration = .seconds(2)) {
        guard !isApplyingRemoteChanges, settings.isCloudMCPConfigured else { return }
        if isSyncing {
            needsResync = true
            return
        }
        debounceTask?.cancel()
        debounceTask = Task { [weak self, weak settings, weak store] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let settings, let store else { return }
            await self.syncNow(settings: settings, store: store)
        }
    }

    @discardableResult
    public func syncNow(
        settings: AppSettings,
        store: BudgetStore,
        exchangeRates: ExchangeRateTable? = nil
    ) async -> Bool {
        guard settings.isCloudMCPConfigured else { return false }
        guard !isSyncing else {
            needsResync = true
            return false
        }
        guard let creds = credentialsProvider(),
              let baseURL = MCPSetupLink.normalizeWorkerURL(
                  settings.cloudMCPURL.isEmpty ? creds.url : settings.cloudMCPURL
              )
        else {
            lastError = RemoteMCPError.missingSecret.localizedMessage(in: settings.language)
            return false
        }

        isSyncing = true
        needsResync = false
        lastError = nil
        defer { isSyncing = false }

        let revKey = Self.revisionKey(for: baseURL)
        let sinceRevision = defaults.integer(forKey: revKey)
        let activeRates = exchangeRates ?? ExchangeRateService.shared.table
        let offsetMinutes = TimeZone.current.secondsFromGMT() / 60

        let payload = RemoteMCPSyncPayload(
            currency: settings.currency,
            language: settings.language.resolved.rawValue,
            timeZoneOffsetMinutes: offsetMinutes,
            currentMember: settings.currentMember,
            members: store.knownMembers(settings: settings),
            partnerDisplayName: settings.partnerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
            salaryHidden: settings.hideSalary,
            allowsChanges: settings.mcpAllowsChanges,
            mcpEnabled: settings.cloudMCPEnabled,
            mcpToken: creds.accessToken,
            exchangeRates: RemoteMCPExchangeRatesPayload(activeRates),
            transactions: store.transactions,
            budgets: store.budgets,
            goals: store.goals,
            plans: store.plans,
            sinceRevision: sinceRevision
        )

        let client = RemoteMCPSyncClient(baseURL: baseURL, syncSecret: creds.syncSecret, transport: transport)
        do {
            let result = try await client.sync(payload)
            isApplyingRemoteChanges = true
            defer { isApplyingRemoteChanges = false }

            if !result.remoteChanges.plans.isEmpty {
                store.applyRemotePlans(result.remoteChanges.plans, notifyCloud: true)
            }
            if !result.remoteChanges.transactions.isEmpty {
                store.applyRemoteTransactions(result.remoteChanges.transactions, notifyCloud: true)
            }
            if !result.remoteChanges.budgets.isEmpty {
                store.applyRemoteBudgets(result.remoteChanges.budgets, notifyCloud: true)
            }
            if !result.remoteChanges.goals.isEmpty {
                store.applyRemoteGoals(result.remoteChanges.goals, notifyCloud: true)
            }

            defaults.set(result.vaultRevision, forKey: revKey)
            vaultRevision = result.vaultRevision
            lastSynced = Date()
            lastMCPCallAt = result.stats.lastMCPCallAt
            lastMCPTool = result.stats.lastMCPTool
            lastError = nil

            if needsResync {
                needsResync = false
                scheduleSync(settings: settings, store: store, delay: .milliseconds(300))
            }
            return true
        } catch let err as RemoteMCPError {
            lastError = err.localizedMessage(in: settings.language)
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func pushConfig(settings: AppSettings) async -> Bool {
        guard settings.isCloudMCPConfigured,
              let creds = credentialsProvider(),
              let baseURL = MCPSetupLink.normalizeWorkerURL(
                  settings.cloudMCPURL.isEmpty ? creds.url : settings.cloudMCPURL
              )
        else { return false }

        let client = RemoteMCPSyncClient(baseURL: baseURL, syncSecret: creds.syncSecret, transport: transport)
        let patch = RemoteMCPConfigPatch(
            mcpEnabled: settings.cloudMCPEnabled,
            allowsChanges: settings.mcpAllowsChanges,
            salaryHidden: settings.hideSalary,
            mcpToken: creds.accessToken,
            currency: settings.currency,
            timeZoneOffsetMinutes: TimeZone.current.secondsFromGMT() / 60
        )
        do {
            try await client.updateConfig(patch)
            lastError = nil
            return true
        } catch let err as RemoteMCPError {
            lastError = err.localizedMessage(in: settings.language)
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func connectAndSync(
        url rawURL: String,
        syncSecret: String,
        accessToken: String,
        settings: AppSettings,
        store: BudgetStore
    ) async -> Result<Void, Error> {
        let lang = settings.language
        guard let baseURL = MCPSetupLink.normalizeWorkerURL(rawURL) else {
            return .failure(NSError(
                domain: "TallyCloudMCP",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: RemoteMCPError.invalidURL.localizedMessage(in: lang)]
            ))
        }
        let trimmedSync = syncSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSync.isEmpty, !trimmedToken.isEmpty else {
            return .failure(NSError(
                domain: "TallyCloudMCP",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: RemoteMCPError.missingSecret.localizedMessage(in: lang)]
            ))
        }

        let client = RemoteMCPSyncClient(baseURL: baseURL, syncSecret: trimmedSync, transport: transport)
        do {
            _ = try await client.health()
            guard settings.saveCloudMCP(
                url: baseURL.absoluteString,
                syncSecret: trimmedSync,
                accessToken: trimmedToken,
                enable: true
            ) else {
                return .failure(NSError(
                    domain: "TallyCloudMCP",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: L10n.text(
                        lang,
                        en: "Could not save Cloud MCP credentials to Keychain.",
                        vi: "Không thể lưu thông tin Cloud MCP vào Keychain.",
                        zh: "无法将 Cloud MCP 凭据保存到钥匙串。"
                    )]
                ))
            }
            defaults.set(0, forKey: Self.revisionKey(for: baseURL))
            _ = await syncNow(settings: settings, store: store)
            return .success(())
        } catch let err as RemoteMCPError {
            return .failure(NSError(
                domain: "TallyCloudMCP",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: err.localizedMessage(in: lang)]
            ))
        } catch {
            return .failure(error)
        }
    }

    public func requestPairingCode(settings: AppSettings) async {
        guard settings.isCloudMCPConfigured,
              !isRequestingPairingCode,
              let creds = credentialsProvider(),
              let baseURL = MCPSetupLink.normalizeWorkerURL(
                  settings.cloudMCPURL.isEmpty ? creds.url : settings.cloudMCPURL
              )
        else { return }

        isRequestingPairingCode = true
        defer { isRequestingPairingCode = false }

        let client = RemoteMCPSyncClient(baseURL: baseURL, syncSecret: creds.syncSecret, transport: transport)
        do {
            let result = try await client.requestPairingCode()
            pairingCode = result.code
            pairingCodeExpiresAt = result.expiresAt
            lastError = nil
        } catch let err as RemoteMCPError {
            lastError = err.localizedMessage(in: settings.language)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func clearPairingCode() {
        pairingCode = nil
        pairingCodeExpiresAt = nil
    }

    public func resetStateOnDisconnect() {
        debounceTask?.cancel()
        debounceTask = nil
        lastSynced = nil
        lastError = nil
        lastMCPCallAt = nil
        lastMCPTool = nil
        vaultRevision = 0
        pairingCode = nil
        pairingCodeExpiresAt = nil
    }

    private static func revisionKey(for baseURL: URL) -> String {
        "tally.mcp.lastVaultRevision.\(baseURL.absoluteString)"
    }
}
