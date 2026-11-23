import ClaudeKit
import DesignSystem
import Foundation
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
    public var isShowingSmartCapture = false

    public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    public var currency: CurrencyCode {
        didSet { defaults.set(currency.rawValue, forKey: Keys.currency) }
    }

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

    public private(set) var hasEmailInboxSecret = false
    public var isEmailInboxConfigured: Bool {
        !emailInboxURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasEmailInboxSecret
    }

    public private(set) var hasAPIKey = false
    public private(set) var apiKeyIsShared = false
    public private(set) var apiKeyHint: String?
    public private(set) var workspaceID = ""
    public private(set) var connectionStatus: ConnectionStatus = .unchecked

    public var model: ClaudeModel { ClaudeModel.resolve(id: modelID) }
    public var isAIReady: Bool { hasAPIKey }

    public var currentMember: HouseholdMember {
        let name = myDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = L10n.text(language, en: "Me", vi: "Mình")
        return HouseholdMember(id: myMemberID, name: name.isEmpty ? fallback : name)
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedLang = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
        let storedCurr = defaults.string(forKey: Keys.currency).flatMap(CurrencyCode.init(rawValue:)) ?? .sgd
        let storedTheme = AppTheme(storedName: defaults.string(forKey: Keys.theme))
        let storedAppearance = AppAppearance(storedName: defaults.string(forKey: Keys.appearance))
        let storedModel = defaults.string(forKey: Keys.modelID) ?? ClaudeModel.default.id
        let storedAutoAI = defaults.object(forKey: Keys.autoParseWithAI) as? Bool ?? true
        let storedFlagReview = defaults.object(forKey: Keys.flagAutoCaptured) as? Bool ?? true
        let storedSync = defaults.object(forKey: Keys.syncsWithICloud) as? Bool ?? true
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
        self.theme = storedTheme
        self.appearance = storedAppearance
        self.modelID = storedModel
        self.autoParseWithAI = storedAutoAI
        self.flagAutoCapturedForReview = storedFlagReview
        self.syncsWithICloud = storedSync
        self.myMemberID = storedMemberID
        self.myDisplayName = storedName
        self.partnerDisplayName = storedPartner
        self.cloudZoneRole = storedRole
        self.emailInboxURL = defaults.string(forKey: Keys.emailInboxURL) ?? ""

        ThemeRuntime.shared.update(theme: storedTheme, appearance: storedAppearance)
        refreshKeychain()
    }

    public func refreshKeychain() {
        hasEmailInboxSecret = KeychainStore.hasEmailInboxSecret()
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

    public func makeAIClient() -> (any AIClient)? {
        guard let creds = KeychainStore.readAPIKeyForRequest() else { return nil }
        return ClaudeClient(
            apiKey: creds.key,
            workspaceID: creds.workspaceID ?? (workspaceID.isEmpty ? nil : workspaceID),
            model: model
        )
    }

    public func checkConnection() {
        checkTask?.cancel()
        guard let client = makeAIClient() else {
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
                        vi: "Đã kết nối\(answeredModel.map { " (\($0))" } ?? "")."
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

    private enum Keys {
        static let language = "tally.language"
        static let currency = "tally.currency"
        static let theme = "tally.theme"
        static let appearance = "tally.appearance"
        static let modelID = "tally.claude.model"
        static let workspaceID = "tally.claude.workspace"
        static let autoParseWithAI = "tally.ai.autoParse"
        static let flagAutoCaptured = "tally.capture.flagReview"
        static let syncsWithICloud = "tally.icloud.enabled"
        static let myMemberID = "tally.member.id"
        static let myDisplayName = "tally.member.name"
        static let partnerDisplayName = "tally.partner.name"
        static let cloudZoneRole = "tally.icloud.zoneRole"
        static let emailInboxURL = "tally.emailInbox.url"
    }
}
