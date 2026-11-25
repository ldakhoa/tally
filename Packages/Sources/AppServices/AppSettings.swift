import BudgetKit
import ClaudeKit
import DesignSystem
import Foundation
import MCPKit
import Observation
import SyncKit
import TallyCore
import ThemeTokens

/// App-wide settings stored in UserDefaults + Keychain (for the Claude API key).
@MainActor
@Observable
public final class AppSettings {
    public enum ConnectionStatus: Equatable {
        case unchecked
        case checking
        case connected(String)
        case failed(String)
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    public var isShowingSettings = false
    public var isShowingAskTally = false
    public var isShowingQuickAdd = false

    public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    public var currency: CurrencyCode {
        didSet {
            defaults.set(currency.rawValue, forKey: Keys.currency)
            if displayCurrency == currency {
                displayCurrency = nil
            }
        }
    }

    /// Optional per-device display currency (never synced to iCloud). `nil` means display in
    /// the household's canonical `currency`.
    public var displayCurrency: CurrencyCode? {
        didSet {
            let normalized = (displayCurrency == currency) ? nil : displayCurrency
            if normalized != displayCurrency {
                displayCurrency = normalized
                return
            }
            if let normalized {
                defaults.set(normalized.rawValue, forKey: Keys.displayCurrency)
            } else {
                defaults.removeObject(forKey: Keys.displayCurrency)
            }
        }
    }

    public var effectiveDisplayCurrency: CurrencyCode {
        displayCurrency ?? currency
    }

    public var isConvertingDisplay: Bool {
        displayCurrency != nil && displayCurrency != currency
    }

    public private(set) var householdCurrencyUpdatedAt: Date? {
        didSet {
            if let householdCurrencyUpdatedAt {
                defaults.set(householdCurrencyUpdatedAt, forKey: Keys.householdCurrencyUpdatedAt)
            } else {
                defaults.removeObject(forKey: Keys.householdCurrencyUpdatedAt)
            }
        }
    }

    /// Returns the synced household currency record only once explicitly chosen or received, so a
    /// fresh unmodified device never overwrites a household's currency via CloudKit LWW.
    public var householdSettingsRecord: HouseholdSettingsRecord? {
        householdCurrencyUpdatedAt.map { HouseholdSettingsRecord(currency: currency, updatedAt: $0) }
    }

    @ObservationIgnored public var onHouseholdCurrencyChanged: ((HouseholdSettingsRecord) -> Void)?

    public var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            ThemeRuntime.shared.update(theme: theme, appearance: appearance)
        }
    }

    public var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            ThemeRuntime.shared.update(theme: theme, appearance: appearance)
        }
    }

    public var aiProvider: AIProvider {
        didSet { defaults.set(aiProvider.rawValue, forKey: Keys.aiProvider) }
    }

    public var modelID: String {
        didSet {
            defaults.set(modelID, forKey: Keys.modelID)
            connectionStatus = .unchecked
        }
    }

    public var autoParseWithAI: Bool {
        didSet { defaults.set(autoParseWithAI, forKey: Keys.autoParseWithAI) }
    }

    public var flagAutoCapturedForReview: Bool {
        didSet { defaults.set(flagAutoCapturedForReview, forKey: Keys.flagAutoCaptured) }
    }

    public var syncsWithICloud: Bool {
        didSet { defaults.set(syncsWithICloud, forKey: Keys.syncsWithICloud) }
    }

    /// Salary privacy (per device): owns the hidden state and the optional Face ID requirement.
    /// Change it through the gate (`hide()`, `reveal`, `toggle`, `setRequiresAuthentication`).
    public let salaryGate: SalaryVisibilityGate

    /// The effective state every screen and the assistant read: `true` while salary and the
    /// figures that include it are masked (see `BudgetKit.SalaryPrivacy`).
    public var hideSalary: Bool { salaryGate.isHidden }

    /// `true` when revealing salary needs owner authentication.
    public var requiresAuthToShowSalary: Bool { salaryGate.requiresAuthentication }

    /// The eye control: hides salary, or reveals it (after Face ID / passcode when required).
    public func toggleSalaryVisibility() async {
        await salaryGate.toggle(reason: SalaryAuthPrompt.reveal(in: language))
    }

    public var soundEffectsEnabled: Bool {
        didSet {
            defaults.set(soundEffectsEnabled, forKey: Keys.soundEffectsEnabled)
            CozySounds.setEnabled(soundEffectsEnabled)
        }
    }

    /// This device's household profile so transactions tag who logged them (e.g. Me vs Wife).
    public var myMemberID: String {
        didSet { defaults.set(myMemberID, forKey: Keys.myMemberID) }
    }

    public var myDisplayName: String {
        didSet { defaults.set(myDisplayName, forKey: Keys.myDisplayName) }
    }

    public var partnerDisplayName: String {
        didSet { defaults.set(partnerDisplayName, forKey: Keys.partnerDisplayName) }
    }

    /// CloudKit role: `.privateOwner` or `.sharedParticipant(zoneName:ownerName:)`.
    public var cloudZoneRole: CloudZoneRole {
        didSet {
            if let data = try? JSONEncoder().encode(cloudZoneRole) {
                defaults.set(data, forKey: Keys.cloudZoneRole)
            }
        }
    }

    public var emailInboxURL: String {
        didSet { defaults.set(emailInboxURL, forKey: Keys.emailInboxURL) }
    }

    /// The local MCP server (Mac only) that lets assistants such as Claude Code or Codex read
    /// this household's data. Off until the user turns it on.
    public var mcpServerEnabled: Bool {
        didSet { defaults.set(mcpServerEnabled, forKey: Keys.mcpServerEnabled) }
    }

    /// `true` when MCP clients may also add, change and delete records. Off by default.
    public var mcpAllowsChanges: Bool {
        didSet { defaults.set(mcpAllowsChanges, forKey: Keys.mcpAllowsChanges) }
    }

    /// Loopback TCP port of the MCP server.
    public var mcpPort: Int {
        didSet { defaults.set(mcpPort, forKey: Keys.mcpPort) }
    }

    public static let defaultMCPPort = 47_821
    public static let mcpPortRange = 1_024...65_535

    /// Always-on remote Cloud MCP server (`tools/mcp-server` on Cloudflare Workers).
    public var cloudMCPEnabled: Bool {
        didSet { defaults.set(cloudMCPEnabled, forKey: Keys.cloudMCPEnabled) }
    }

    public var cloudMCPURL: String {
        didSet { defaults.set(cloudMCPURL, forKey: Keys.cloudMCPURL) }
    }

    public var mcpRepoPath: String {
        didSet { defaults.set(mcpRepoPath, forKey: Keys.mcpRepoPath) }
    }

    public private(set) var hasCloudMCPCredentials = false
    @ObservationIgnored var testHasCloudMCPCredentialsOverride: Bool?
    public var isCloudMCPConfigured: Bool {
        !cloudMCPURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (testHasCloudMCPCredentialsOverride ?? hasCloudMCPCredentials)
    }

    public private(set) var hasEmailInboxSecret = false
    public var isEmailInboxConfigured: Bool {
        !emailInboxURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasEmailInboxSecret
    }

    public private(set) var shortcutICloudLinks: [String: String]
    public private(set) var completedShortcutGuides: Set<String>

    public private(set) var hasAPIKey = false
    public private(set) var apiKeyIsShared = false
    public private(set) var apiKeyHint: String?
    public private(set) var workspaceID = ""
    public private(set) var connectionStatus: ConnectionStatus = .unchecked

    public var model: ClaudeModel { ClaudeModel.resolve(id: modelID) }
    public var appleIntelligenceStatus: AppleIntelligenceStatus { AppleIntelligenceStatus.current() }
    public var isAppleIntelligenceAvailable: Bool { appleIntelligenceStatus.isAvailable }

    public var isAIReady: Bool {
        switch aiProvider {
        case .appleIntelligence: return isAppleIntelligenceAvailable
        case .claude: return hasAPIKey
        case .auto: return isAppleIntelligenceAvailable || hasAPIKey
        }
    }

    public func resolvedBackend(for purpose: AIRequestPurpose = .assistantChat) -> ResolvedAIBackend? {
        switch aiProvider {
        case .appleIntelligence:
            return isAppleIntelligenceAvailable ? .appleIntelligence : nil
        case .claude:
            return hasAPIKey ? .claude : nil
        case .auto:
            switch purpose {
            case .parsing, .siri:
                if isAppleIntelligenceAvailable { return .appleIntelligence }
                if hasAPIKey { return .claude }
                return nil
            case .assistantChat:
                if hasAPIKey { return .claude }
                if isAppleIntelligenceAvailable { return .appleIntelligence }
                return nil
            }
        }
    }

    public func activeProviderSummary(in lang: AppLanguage) -> String {
        switch aiProvider {
        case .appleIntelligence:
            return isAppleIntelligenceAvailable
                ? L10n.text(lang, en: "Apple Intelligence (On-Device)", vi: "Apple Intelligence (Trên máy)", zh: "Apple 智能（本地）")
                : appleIntelligenceStatus.headline(in: lang)
        case .claude:
            return hasAPIKey
                ? model.name
                : L10n.text(lang, en: "Claude · Not set up", vi: "Claude · Chưa thiết lập", zh: "Claude · 未配置")
        case .auto:
            if isAppleIntelligenceAvailable && hasAPIKey {
                return L10n.text(lang, en: "Auto · Apple + Claude", vi: "Tự động · Apple + Claude", zh: "自动 · Apple + Claude")
            } else if isAppleIntelligenceAvailable {
                return L10n.text(lang, en: "Auto · Apple Intelligence", vi: "Tự động · Apple Intelligence", zh: "自动 · Apple 智能")
            } else if hasAPIKey {
                return L10n.text(lang, en: "Auto · \(model.name)", vi: "Tự động · \(model.name)", zh: "自动 · \(model.name)")
            } else {
                return L10n.text(lang, en: "Not set up", vi: "Chưa thiết lập", zh: "未配置")
            }
        }
    }

    public var currentMember: HouseholdMember {
        let name = myDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = L10n.text(language, en: "Me", vi: "Mình", zh: "我")
        return HouseholdMember(id: myMemberID, name: name.isEmpty ? fallback : name)
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedLang = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
        let storedCurr = defaults.string(forKey: Keys.currency).flatMap(CurrencyCode.init(rawValue:)) ?? .sgd
        let rawDisplayCurr = defaults.string(forKey: Keys.displayCurrency).flatMap(CurrencyCode.init(rawValue:))
        let storedDisplayCurr = (rawDisplayCurr == storedCurr) ? nil : rawDisplayCurr
        let storedCurrencyUpdatedAt = defaults.object(forKey: Keys.householdCurrencyUpdatedAt) as? Date
        let storedTheme = AppTheme(storedName: defaults.string(forKey: Keys.theme))
        let storedAppearance = AppAppearance(storedName: defaults.string(forKey: Keys.appearance))
        let storedProvider = defaults.string(forKey: Keys.aiProvider).flatMap(AIProvider.init(rawValue:)) ?? .auto
        let storedModel = defaults.string(forKey: Keys.modelID) ?? ClaudeModel.default.id
        let storedAutoAI = defaults.object(forKey: Keys.autoParseWithAI) as? Bool ?? true
        let storedFlagReview = defaults.object(forKey: Keys.flagAutoCaptured) as? Bool ?? true
        let storedSync = defaults.object(forKey: Keys.syncsWithICloud) as? Bool ?? true
        let storedSounds = defaults.object(forKey: Keys.soundEffectsEnabled) as? Bool ?? true
        let storedMemberID = defaults.string(forKey: Keys.myMemberID) ?? UUID().uuidString
        let storedName = defaults.string(forKey: Keys.myDisplayName) ?? ""
        let storedPartner = defaults.string(forKey: Keys.partnerDisplayName) ?? ""
        let storedRole: CloudZoneRole = {
            guard let data = defaults.data(forKey: Keys.cloudZoneRole),
                  let role = try? JSONDecoder().decode(CloudZoneRole.self, from: data)
            else { return .privateOwner }
            return role
        }()

        if defaults.string(forKey: Keys.myMemberID) == nil {
            defaults.set(storedMemberID, forKey: Keys.myMemberID)
        }

        self.language = storedLang
        self.currency = storedCurr
        self.displayCurrency = storedDisplayCurr
        self.householdCurrencyUpdatedAt = storedCurrencyUpdatedAt
        self.theme = storedTheme
        self.appearance = storedAppearance
        self.aiProvider = storedProvider
        self.modelID = storedModel
        self.autoParseWithAI = storedAutoAI
        self.flagAutoCapturedForReview = storedFlagReview
        self.syncsWithICloud = storedSync
        self.soundEffectsEnabled = storedSounds
        self.salaryGate = SalaryVisibilityGate(defaults: defaults)
        self.myMemberID = storedMemberID
        self.myDisplayName = storedName
        self.partnerDisplayName = storedPartner
        self.cloudZoneRole = storedRole
        self.emailInboxURL = defaults.string(forKey: Keys.emailInboxURL) ?? ""
        self.mcpServerEnabled = defaults.bool(forKey: Keys.mcpServerEnabled)
        self.mcpAllowsChanges = defaults.bool(forKey: Keys.mcpAllowsChanges)
        let storedPort = defaults.integer(forKey: Keys.mcpPort)
        self.mcpPort = Self.mcpPortRange.contains(storedPort) ? storedPort : Self.defaultMCPPort
        self.cloudMCPEnabled = defaults.object(forKey: Keys.cloudMCPEnabled) as? Bool ?? true
        self.cloudMCPURL = defaults.string(forKey: Keys.cloudMCPURL) ?? ""
        self.mcpRepoPath = defaults.string(forKey: Keys.mcpRepoPath) ?? ""
        self.shortcutICloudLinks = defaults.dictionary(forKey: Keys.shortcutICloudLinks) as? [String: String] ?? [:]
        self.completedShortcutGuides = Set(defaults.stringArray(forKey: Keys.completedShortcutGuides) ?? [])

        CozySounds.setEnabled(storedSounds)
        ThemeRuntime.shared.update(theme: storedTheme, appearance: storedAppearance)
        refreshKeychain()
    }

    public func refreshKeychain() {
        hasEmailInboxSecret = KeychainStore.hasEmailInboxSecret()
        if let cloudCreds = KeychainStore.readCloudMCPCredentials() {
            hasCloudMCPCredentials = true
            let normalized = MCPSetupLink.normalizeWorkerURL(cloudCreds.url)?.absoluteString ?? cloudCreds.url
            if !normalized.isEmpty && cloudMCPURL != normalized {
                cloudMCPURL = normalized
            }
            if defaults.object(forKey: Keys.cloudMCPEnabled) == nil {
                cloudMCPEnabled = true
            }
        } else {
            hasCloudMCPCredentials = false
        }
        if let saved = KeychainStore.saved() {
            hasAPIKey = true
            apiKeyIsShared = saved.kind == .shared
            apiKeyHint = saved.details.hint
            workspaceID = saved.details.workspaceID ?? ""
        } else {
            hasAPIKey = false
            apiKeyIsShared = false
            apiKeyHint = nil
            workspaceID = defaults.string(forKey: Keys.workspaceID) ?? ""
        }
    }

    @discardableResult
    public func setAPIKey(_ rawKey: String) -> Bool {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        connectionStatus = .unchecked
        if trimmed.isEmpty {
            KeychainStore.deleteAPIKey()
            refreshKeychain()
            return true
        }
        let ok = KeychainStore.saveAPIKey(trimmed, workspaceID: workspaceID)
        refreshKeychain()
        return ok
    }

    @discardableResult
    public func setWorkspaceID(_ rawID: String) -> Bool {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmed, forKey: Keys.workspaceID)
        workspaceID = trimmed
        connectionStatus = .unchecked
        if hasAPIKey {
            let ok = KeychainStore.setWorkspaceID(trimmed)
            refreshKeychain()
            return ok
        }
        return true
    }

    public func makeClaudeClient() -> (any AIClient)? {
        guard let creds = KeychainStore.readAPIKeyForRequest() else { return nil }
        return ClaudeClient(
            apiKey: creds.key,
            workspaceID: creds.workspaceID ?? (workspaceID.isEmpty ? nil : workspaceID),
            model: model
        )
    }

    public func makeAIClient(for purpose: AIRequestPurpose = .parsing) -> (any AIClient)? {
        guard let backend = resolvedBackend(for: purpose) else { return nil }
        switch backend {
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                return AppleFoundationModelsClient()
            }
            #endif
            return nil
        case .claude:
            return makeClaudeClient()
        }
    }

    public func checkConnection() {
        checkTask?.cancel()
        guard let client = makeClaudeClient() else {
            connectionStatus = .failed(ClaudeError.missingAPIKey.localizedMessage(in: language))
            return
        }
        connectionStatus = .checking
        let lang = language
        checkTask = Task {
            do {
                let outcome = try await ConnectionCheck.run(client)
                switch outcome {
                case .connected(let answeredModel):
                    let text = L10n.text(
                        lang,
                        en: "Connected\(answeredModel.map { " (\($0))" } ?? "").",
                        vi: "Đã kết nối\(answeredModel.map { " (\($0))" } ?? "").",
                        zh: "已连接\(answeredModel.map { "（\($0)）" } ?? "")。"
                    )
                    self.connectionStatus = .connected(text)
                case .failed(let message):
                    self.connectionStatus = .failed(message)
                }
            } catch is CancellationError {
                return
            } catch {
                self.connectionStatus = .failed(error.localizedDescription)
            }
        }
    }

    @discardableResult
    public func saveEmailInbox(url: String, secret: String) -> Bool {
        emailInboxURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSecret.isEmpty {
            let ok = KeychainStore.saveEmailInboxSecret(trimmedSecret)
            refreshKeychain()
            return ok
        }
        refreshKeychain()
        return hasEmailInboxSecret
    }

    public func disconnectEmailInbox() {
        emailInboxURL = ""
        KeychainStore.deleteEmailInboxSecret()
        refreshKeychain()
    }

    @discardableResult
    public func saveCloudMCP(url: String, syncSecret: String, accessToken: String, enable: Bool = true) -> Bool {
        let normalized = MCPSetupLink.normalizeWorkerURL(url)?.absoluteString
            ?? url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSync = syncSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !trimmedSync.isEmpty, !trimmedToken.isEmpty else { return false }
        cloudMCPURL = normalized
        cloudMCPEnabled = enable
        let ok = KeychainStore.saveCloudMCPCredentials(
            KeychainStore.CloudMCPCredentials(url: normalized, syncSecret: trimmedSync, accessToken: trimmedToken)
        )
        refreshKeychain()
        return ok
    }

    public func disconnectCloudMCP() {
        cloudMCPURL = ""
        cloudMCPEnabled = false
        KeychainStore.deleteCloudMCPCredentials()
        refreshKeychain()
    }

    // MARK: - Apple Shortcuts (1-Tap iCloud Links & Setup Progress)

    public func shortcutICloudURL(for template: ShortcutTemplateID) -> URL? {
        guard let raw = shortcutICloudLinks[template.rawValue] else { return nil }
        return ShortcutICloudLink.normalizedURL(from: raw)
    }

    public func shortcutICloudLinkString(for template: ShortcutTemplateID) -> String {
        shortcutICloudURL(for: template)?.absoluteString ?? ""
    }

    @discardableResult
    public func setShortcutICloudLink(_ raw: String, for template: ShortcutTemplateID) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = shortcutICloudLinks
        if trimmed.isEmpty {
            updated.removeValue(forKey: template.rawValue)
            shortcutICloudLinks = updated
            defaults.set(updated, forKey: Keys.shortcutICloudLinks)
            return true
        }
        guard let normalized = ShortcutICloudLink.normalizedURL(from: trimmed) else {
            return false
        }
        updated[template.rawValue] = normalized.absoluteString
        shortcutICloudLinks = updated
        defaults.set(updated, forKey: Keys.shortcutICloudLinks)
        return true
    }

    public func isShortcutGuideCompleted(_ guide: ShortcutGuideKind) -> Bool {
        completedShortcutGuides.contains(guide.rawValue)
    }

    public func setShortcutGuideCompleted(_ completed: Bool, for guide: ShortcutGuideKind) {
        var updated = completedShortcutGuides
        if completed {
            updated.insert(guide.rawValue)
        } else {
            updated.remove(guide.rawValue)
        }
        completedShortcutGuides = updated
        defaults.set(Array(updated).sorted(), forKey: Keys.completedShortcutGuides)
    }

    // MARK: - Household & Display Currency

    public func setHouseholdCurrency(_ newCurrency: CurrencyCode, updatedAt: Date = Date(), notifyCloud: Bool = true) {
        let stamp = householdCurrencyUpdatedAt.map { updatedAt > $0 ? updatedAt : $0.addingTimeInterval(0.001) } ?? updatedAt
        currency = newCurrency
        householdCurrencyUpdatedAt = stamp
        if displayCurrency == newCurrency {
            displayCurrency = nil
        }
        if notifyCloud {
            onHouseholdCurrencyChanged?(HouseholdSettingsRecord(currency: newCurrency, updatedAt: stamp))
        }
    }

    public func applyRemoteHouseholdSettings(_ incoming: HouseholdSettingsRecord) {
        let merged = SyncMerge.mergeHouseholdSettings(local: householdSettingsRecord, remote: incoming)
        guard merged != householdSettingsRecord else { return }
        currency = merged.currency
        householdCurrencyUpdatedAt = merged.updatedAt
        if displayCurrency == merged.currency {
            displayCurrency = nil
        }
    }

    public func displayMinor(_ ledgerMinor: Int64, rates: ExchangeRateTable? = nil) -> Int64 {
        guard isConvertingDisplay, let display = displayCurrency else { return ledgerMinor }
        let activeRates = rates ?? ExchangeRateService.shared.table
        return activeRates.convertMinor(ledgerMinor, from: currency, to: display)
    }

    public func displayMajor(_ ledgerMinor: Int64, rates: ExchangeRateTable? = nil) -> Double {
        let target = effectiveDisplayCurrency
        return target.toMajor(displayMinor(ledgerMinor, rates: rates))
    }

    public func formatMoney(
        minor ledgerMinor: Int64,
        compact: Bool = false,
        signed: Bool = false,
        rates: ExchangeRateTable? = nil
    ) -> String {
        let target = effectiveDisplayCurrency
        let shownMinor = displayMinor(ledgerMinor, rates: rates)
        return MoneyFormat.format(
            minor: shownMinor,
            currency: target,
            language: language,
            compact: compact,
            signed: signed
        )
    }

    public func displayDailyTotals(
        _ totals: [String: DailyCalendarTotal],
        rates: ExchangeRateTable? = nil
    ) -> [String: DailyCalendarTotal] {
        guard isConvertingDisplay, let display = displayCurrency else { return totals }
        let activeRates = rates ?? ExchangeRateService.shared.table
        return totals.mapValues { total in
            DailyCalendarTotal(
                dayKey: total.dayKey,
                spendingMinor: activeRates.convertMinor(total.spendingMinor, from: currency, to: display),
                incomeMinor: activeRates.convertMinor(total.incomeMinor, from: currency, to: display),
                count: total.count,
                includesSalary: total.includesSalary
            )
        }
    }

    private enum Keys {
        static let language = "tally.language"
        static let currency = "tally.currency"
        static let displayCurrency = "tally.displayCurrency"
        static let householdCurrencyUpdatedAt = "tally.currency.updatedAt"
        static let theme = "tally.theme"
        static let appearance = "tally.appearance"
        static let aiProvider = "tally.ai.provider"
        static let modelID = "tally.claude.model"
        static let workspaceID = "tally.claude.workspace"
        static let autoParseWithAI = "tally.ai.autoParse"
        static let flagAutoCaptured = "tally.capture.flagReview"
        static let syncsWithICloud = "tally.icloud.enabled"
        static let soundEffectsEnabled = "tally.soundEffects"
        static let myMemberID = "tally.member.id"
        static let myDisplayName = "tally.member.name"
        static let partnerDisplayName = "tally.partner.name"
        static let cloudZoneRole = "tally.icloud.zoneRole"
        static let emailInboxURL = "tally.emailInbox.url"
        static let mcpServerEnabled = "tally.mcp.enabled"
        static let mcpAllowsChanges = "tally.mcp.allowsChanges"
        static let mcpPort = "tally.mcp.port"
        static let cloudMCPEnabled = "tally.mcp.cloudEnabled"
        static let cloudMCPURL = "tally.mcp.cloudURL"
        static let mcpRepoPath = "tally.mcp.repoPath"
        static let shortcutICloudLinks = "tally.shortcuts.icloudLinks"
        static let completedShortcutGuides = "tally.shortcuts.completedGuides"
    }
}
