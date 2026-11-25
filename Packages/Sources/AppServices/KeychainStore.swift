import ClaudeKit
import Foundation
import Security

/// Stores the Anthropic API key securely in the Keychain (iCloud Keychain synchronizable on
/// signed devices, local Keychain fallback on unsigned builds). Never logged or synced in CloudKit.
public enum KeychainStore {
    private static let service = "com.ldakhoa.tally.anthropic"
    private static let account = "api-key"

    public struct Saved: Equatable, Sendable {
        public var kind: APIKeyKeychain.Kind
        public var details: APIKeyDetails
    }

    private static func query(_ kind: APIKeyKeychain.Kind) -> [String: Any] {
        APIKeyKeychain.query(kind, service: service, account: account)
    }

    public static func saved() -> Saved? {
        for kind in APIKeyKeychain.kinds() {
            if let attrs = attributes(kind) {
                return Saved(kind: kind, details: APIKeyDetails.decode(attrs[kSecAttrGeneric as String] as? Data))
            }
        }
        return nil
    }

    private static func attributes(_ kind: APIKeyKeychain.Kind) -> [String: Any]? {
        var q = query(kind)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? [String: Any] ?? [:]
    }

    public static func readAPIKeyForRequest() -> (key: String, workspaceID: String?)? {
        for kind in APIKeyKeychain.kinds() {
            var q = query(kind)
            q[kSecReturnData as String] = true
            q[kSecReturnAttributes as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
                  let found = item as? [String: Any],
                  let data = found[kSecValueData as String] as? Data,
                  let key = String(data: data, encoding: .utf8),
                  !key.isEmpty
            else { continue }
            let details = APIKeyDetails.decode(found[kSecAttrGeneric as String] as? Data)
            return (key, details.workspaceID)
        }
        return nil
    }

    @discardableResult
    public static func saveAPIKey(_ key: String, workspaceID: String) -> Bool {
        deleteAPIKey()
        let details = APIKeyDetails(hint: APIKeyDetails.hint(for: key), workspaceID: workspaceID)
        for kind in APIKeyKeychain.kinds() {
            var q = query(kind)
            q[kSecValueData as String] = Data(key.utf8)
            q[kSecAttrGeneric as String] = details.encoded
            for (k, v) in APIKeyKeychain.addAttributes(kind) { q[k] = v }
            let status = SecItemAdd(q as CFDictionary, nil)
            if status == errSecSuccess { return true }
            guard kind == .shared, APIKeyKeychain.isUnavailable(status) else { return false }
        }
        return false
    }

    @discardableResult
    public static func setWorkspaceID(_ id: String) -> Bool {
        guard var saved = saved() else { return false }
        saved.details.workspaceID = id
        let update = [kSecAttrGeneric as String: saved.details.encoded]
        return SecItemUpdate(query(saved.kind) as CFDictionary, update as CFDictionary) == errSecSuccess
    }

    public static func deleteAPIKey() {
        for kind in APIKeyKeychain.kinds() {
            SecItemDelete(query(kind) as CFDictionary)
        }
    }

    // MARK: - Cloud Bank Email Inbox Secret (Keychain only, never in UserDefaults or CloudKit)

    private static let inboxService = "com.ldakhoa.tally.email-inbox"
    private static let inboxAccount = "inbox-secret"

    public static func hasEmailInboxSecret() -> Bool {
        for kind in APIKeyKeychain.kinds() {
            var q = APIKeyKeychain.query(kind, service: inboxService, account: inboxAccount)
            q[kSecReturnAttributes as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess { return true }
        }
        return false
    }

    public static func readEmailInboxSecret() -> String? {
        for kind in APIKeyKeychain.kinds() {
            var q = APIKeyKeychain.query(kind, service: inboxService, account: inboxAccount)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data,
               let secret = String(data: data, encoding: .utf8),
               !secret.isEmpty {
                return secret
            }
        }
        return nil
    }

    @discardableResult
    public static func saveEmailInboxSecret(_ secret: String) -> Bool {
        deleteEmailInboxSecret()
        for kind in APIKeyKeychain.kinds() {
            var q = APIKeyKeychain.query(kind, service: inboxService, account: inboxAccount)
            q[kSecValueData as String] = Data(secret.utf8)
            for (k, v) in APIKeyKeychain.addAttributes(kind) { q[k] = v }
            let status = SecItemAdd(q as CFDictionary, nil)
            if status == errSecSuccess { return true }
            guard kind == .shared, APIKeyKeychain.isUnavailable(status) else { return false }
        }
        return false
    }

    public static func deleteEmailInboxSecret() {
        for kind in APIKeyKeychain.kinds() {
            SecItemDelete(APIKeyKeychain.query(kind, service: inboxService, account: inboxAccount) as CFDictionary)
        }
    }

    // MARK: - MCP access token (this device only: never iCloud Keychain, UserDefaults or CloudKit)

    private static let mcpService = "com.ldakhoa.tally.mcp"
    private static let mcpAccount = "access-token"

    private static var mcpQuery: [String: Any] {
        APIKeyKeychain.query(.local, service: mcpService, account: mcpAccount)
    }

    /// The bearer token MCP clients on this Mac must present, or `nil` before one was created.
    public static func readMCPToken() -> String? {
        var q = mcpQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    /// Replaces the token with a new random one (clients holding the old one stop working).
    /// Returns `nil` when the Keychain refused to store it.
    public static func regenerateMCPToken() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        SecItemDelete(mcpQuery as CFDictionary)
        var q = mcpQuery
        q[kSecValueData as String] = Data(token.utf8)
        for (k, v) in APIKeyKeychain.addAttributes(.local) { q[k] = v }
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess ? token : nil
    }

    public static func mcpTokenCreatingIfNeeded() -> String? {
        readMCPToken() ?? regenerateMCPToken()
    }

    // MARK: - Cloud MCP Credentials (synced across user's devices via iCloud Keychain)

    public struct CloudMCPCredentials: Codable, Equatable, Sendable {
        public var url: String
        public var syncSecret: String
        public var accessToken: String

        public init(url: String, syncSecret: String, accessToken: String) {
            self.url = url
            self.syncSecret = syncSecret
            self.accessToken = accessToken
        }
    }

    private static let cloudMCPService = "com.ldakhoa.tally.mcp-cloud"
    private static let cloudMCPAccount = "credentials"

    public static func hasCloudMCPCredentials() -> Bool {
        readCloudMCPCredentials() != nil
    }

    public static func readCloudMCPCredentials() -> CloudMCPCredentials? {
        for kind in APIKeyKeychain.kinds() {
            var q = APIKeyKeychain.query(kind, service: cloudMCPService, account: cloudMCPAccount)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let decoded = try? JSONDecoder().decode(CloudMCPCredentials.self, from: data),
                  !decoded.url.isEmpty,
                  !decoded.syncSecret.isEmpty,
                  !decoded.accessToken.isEmpty
            else { continue }
            return decoded
        }
        return nil
    }

    @discardableResult
    public static func saveCloudMCPCredentials(_ credentials: CloudMCPCredentials) -> Bool {
        guard let encoded = try? JSONEncoder().encode(credentials) else { return false }
        deleteCloudMCPCredentials()
        for kind in APIKeyKeychain.kinds() {
            var q = APIKeyKeychain.query(kind, service: cloudMCPService, account: cloudMCPAccount)
            q[kSecValueData as String] = encoded
            q[kSecAttrGeneric as String] = Data(credentials.url.utf8)
            for (k, v) in APIKeyKeychain.addAttributes(kind) { q[k] = v }
            let status = SecItemAdd(q as CFDictionary, nil)
            if status == errSecSuccess { return true }
            guard kind == .shared, APIKeyKeychain.isUnavailable(status) else { return false }
        }
        return false
    }

    public static func regenerateCloudMCPAccessToken() -> CloudMCPCredentials? {
        guard var current = readCloudMCPCredentials() else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        current.accessToken = bytes.map { String(format: "%02x", $0) }.joined()
        return saveCloudMCPCredentials(current) ? current : nil
    }

    public static func deleteCloudMCPCredentials() {
        for kind in APIKeyKeychain.kinds() {
            SecItemDelete(APIKeyKeychain.query(kind, service: cloudMCPService, account: cloudMCPAccount) as CFDictionary)
        }
    }
}
