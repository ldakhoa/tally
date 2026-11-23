import Foundation
import TallyCore

public struct BankEmailAlert: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var subject: String
    public var sender: String
    public var body: String
    public var member: String
    public var receivedAt: String

    public init(id: String, subject: String, sender: String, body: String, member: String = "", receivedAt: String = "") {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.body = body
        self.member = member
        self.receivedAt = receivedAt
    }

    public var combinedText: String {
        let parts = [subject, body].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.joined(separator: "\n")
    }
}

public enum EmailInboxError: Error, Equatable, Sendable {
    case invalidURL
    case missingSecret
    case unauthorized
    case serverError(Int)
    case network(String)

    public func localizedMessage(in language: AppLanguage) -> String {
        switch self {
        case .invalidURL:
            return L10n.text(language, en: "Enter a valid HTTPS Worker URL.", vi: "Nhập địa chỉ HTTPS hợp lệ của Worker.", zh: "请输入有效的 HTTPS Worker 地址。")
        case .missingSecret:
            return L10n.text(language, en: "Enter your Inbox Secret token.", vi: "Nhập mã bí mật Inbox Secret.", zh: "请输入您的 Inbox Secret 密钥。")
        case .unauthorized:
            return L10n.text(language, en: "Inbox Secret was rejected (401). Check your secret.", vi: "Mã bí mật bị từ chối (401). Kiểm tra lại INBOX_SECRET.", zh: "密钥被拒绝（401），请检查您的 Inbox Secret。")
        case .serverError(let code):
            return L10n.text(language, en: "Email Inbox returned HTTP \(code).", vi: "Email Inbox trả về lỗi HTTP \(code).", zh: "邮件收件箱返回 HTTP \(code) 错误。")
        case .network(let detail):
            return L10n.text(language, en: "Connection failed: \(detail)", vi: "Lỗi kết nối: \(detail)", zh: "连接失败：\(detail)")
        }
    }
}

public protocol InboxHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionInboxTransport: InboxHTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 20) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EmailInboxError.network("Invalid HTTP response")
        }
        return (data, http.statusCode)
    }
}

/// Pure Foundation client for Tally's Cloudflare Email Inbox Worker (`tools/email-inbox`).
public struct EmailInboxClient: Sendable {
    public let baseURL: URL
    private let secret: String
    private let transport: any InboxHTTPTransport

    public init(baseURL: URL, secret: String, transport: any InboxHTTPTransport = URLSessionInboxTransport()) {
        self.baseURL = baseURL
        self.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
    }

    public static func normalizeURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmailInboxError.invalidURL }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              url.host?.isEmpty == false
        else { throw EmailInboxError.invalidURL }
        return url
    }

    public func fetchInbox() async throws -> [BankEmailAlert] {
        guard !secret.isEmpty else { throw EmailInboxError.missingSecret }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/inbox"))
        req.httpMethod = "GET"
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")

        let (data, status) = try await perform(req)
        try checkStatus(status)
        struct Envelope: Decodable { let items: [BankEmailAlert] }
        do {
            return try JSONDecoder().decode(Envelope.self, from: data).items
        } catch {
            throw EmailInboxError.network("Could not decode inbox items.")
        }
    }

    public func ack(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        guard !secret.isEmpty else { throw EmailInboxError.missingSecret }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/ack"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["ids": ids])

        let (_, status) = try await perform(req)
        try checkStatus(status)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            return try await transport.send(request)
        } catch let err as EmailInboxError {
            throw err
        } catch {
            throw EmailInboxError.network(error.localizedDescription)
        }
    }

    private func checkStatus(_ status: Int) throws {
        if (200..<300).contains(status) { return }
        if status == 401 || status == 403 { throw EmailInboxError.unauthorized }
        throw EmailInboxError.serverError(status)
    }
}
