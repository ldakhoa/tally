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
}
