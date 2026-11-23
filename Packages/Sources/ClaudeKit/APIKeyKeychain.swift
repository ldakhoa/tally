import Foundation
import Security

public enum APIKeyKeychain {
    public enum Kind: String, Hashable, Sendable {
        case shared
        case local
    }

    public static func kinds() -> [Kind] {
        [.shared, .local]
    }

    public static func query(_ kind: Kind, service: String, account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if kind == .shared {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        return query
    }

    public static func addAttributes(_ kind: Kind) -> [String: Any] {
        switch kind {
        case .shared:
            return [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        case .local:
            return [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        }
    }

    public static func isUnavailable(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecNotAvailable
    }
}

public struct APIKeyDetails: Codable, Hashable, Sendable {
    public var hint: String?
    public var workspaceID: String?

    public init(hint: String? = nil, workspaceID: String? = nil) {
        self.hint = hint
        self.workspaceID = workspaceID
    }

    public static func hint(for key: String) -> String {
        let prefix = key.hasPrefix("sk-ant-") ? "sk-ant-" : ""
        return prefix + "…" + String(key.suffix(4))
    }

    public var encoded: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    public static func decode(_ data: Data?) -> APIKeyDetails {
        guard let data, !data.isEmpty else { return APIKeyDetails() }
        if data.first == UInt8(ascii: "{"), let details = try? JSONDecoder().decode(APIKeyDetails.self, from: data) {
            return details
        }
        let text = String(decoding: data, as: UTF8.self)
        return APIKeyDetails(hint: text.isEmpty ? nil : text)
    }
}

public enum ConnectionCheck {
    public enum Outcome: Equatable, Sendable {
        case connected(model: String?)
        case failed(String)
    }

    public static let request = ClaudeRequest(
        messages: [.user("Reply with the single word: ready")],
        maxTokens: 128,
        effort: .low
    )

    public static func run(_ client: any AIClient) async throws -> Outcome {
        do {
            let completion = try await client.complete(request)
            return .connected(model: completion.model)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            if let error = error as? LocalizedError, let description = error.errorDescription {
                return .failed(description)
            }
            return .failed(error.localizedDescription)
        }
    }
}
