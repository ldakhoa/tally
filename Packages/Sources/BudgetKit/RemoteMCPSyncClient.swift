import Foundation
import TallyCore

// MARK: - Wire Payloads

public struct RemoteMCPExchangeRatesPayload: Codable, Equatable, Sendable {
    public var ratesPerSGD: [String: Double]
    public var rateDate: String?
    public var fetchedAt: Date?

    public init(ratesPerSGD: [String: Double], rateDate: String? = nil, fetchedAt: Date? = nil) {
        self.ratesPerSGD = ratesPerSGD
        self.rateDate = rateDate
        self.fetchedAt = fetchedAt
    }

    public init(_ table: ExchangeRateTable) {
        self.ratesPerSGD = table.ratesPerSGD
        self.rateDate = table.rateDate
        self.fetchedAt = table.fetchedAt
    }
}

public struct RemoteMCPSyncPayload: Codable, Equatable, Sendable {
    public var currency: CurrencyCode
    public var language: String
    public var timeZoneOffsetMinutes: Int
    public var currentMember: HouseholdMember
    public var members: [HouseholdMember]
    public var partnerDisplayName: String?
    public var salaryHidden: Bool
    public var allowsChanges: Bool
    public var mcpEnabled: Bool
    public var mcpToken: String
    public var exchangeRates: RemoteMCPExchangeRatesPayload?
    public var transactions: [TransactionRecord]
    public var budgets: [BudgetLimitRecord]
    public var goals: [SavingsGoalRecord]
    public var plans: [InstallmentPlanRecord]
    public var sinceRevision: Int

    public init(
        currency: CurrencyCode,
        language: String,
        timeZoneOffsetMinutes: Int,
        currentMember: HouseholdMember,
        members: [HouseholdMember],
        partnerDisplayName: String? = nil,
        salaryHidden: Bool,
        allowsChanges: Bool,
        mcpEnabled: Bool,
        mcpToken: String,
        exchangeRates: RemoteMCPExchangeRatesPayload? = nil,
        transactions: [TransactionRecord],
        budgets: [BudgetLimitRecord],
        goals: [SavingsGoalRecord],
        plans: [InstallmentPlanRecord],
        sinceRevision: Int
    ) {
        self.currency = currency
        self.language = language
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
        self.currentMember = currentMember
        self.members = members
        self.partnerDisplayName = partnerDisplayName
        self.salaryHidden = salaryHidden
        self.allowsChanges = allowsChanges
        self.mcpEnabled = mcpEnabled
        self.mcpToken = mcpToken
        self.exchangeRates = exchangeRates
        self.transactions = transactions
        self.budgets = budgets
        self.goals = goals
        self.plans = plans
        self.sinceRevision = sinceRevision
    }
}

public struct RemoteMCPRemoteChanges: Codable, Equatable, Sendable {
    public var transactions: [TransactionRecord]
    public var budgets: [BudgetLimitRecord]
    public var goals: [SavingsGoalRecord]
    public var plans: [InstallmentPlanRecord]

    public init(
        transactions: [TransactionRecord] = [],
        budgets: [BudgetLimitRecord] = [],
        goals: [SavingsGoalRecord] = [],
        plans: [InstallmentPlanRecord] = []
    ) {
        self.transactions = transactions
        self.budgets = budgets
        self.goals = goals
        self.plans = plans
    }

    public var isEmpty: Bool {
        transactions.isEmpty && budgets.isEmpty && goals.isEmpty && plans.isEmpty
    }
}

public struct RemoteMCPStats: Codable, Equatable, Sendable {
    public var transactionCount: Int
    public var budgetCount: Int
    public var goalCount: Int
    public var planCount: Int
    public var lastSyncedAt: Date?
    public var lastMCPCallAt: Date?
    public var lastMCPTool: String?

    public init(
        transactionCount: Int = 0,
        budgetCount: Int = 0,
        goalCount: Int = 0,
        planCount: Int = 0,
        lastSyncedAt: Date? = nil,
        lastMCPCallAt: Date? = nil,
        lastMCPTool: String? = nil
    ) {
        self.transactionCount = transactionCount
        self.budgetCount = budgetCount
        self.goalCount = goalCount
        self.planCount = planCount
        self.lastSyncedAt = lastSyncedAt
        self.lastMCPCallAt = lastMCPCallAt
        self.lastMCPTool = lastMCPTool
    }
}

public struct RemoteMCPSyncResult: Codable, Equatable, Sendable {
    public var ok: Bool
    public var vaultRevision: Int
    public var remoteChanges: RemoteMCPRemoteChanges
    public var stats: RemoteMCPStats

    public init(
        ok: Bool,
        vaultRevision: Int,
        remoteChanges: RemoteMCPRemoteChanges,
        stats: RemoteMCPStats
    ) {
        self.ok = ok
        self.vaultRevision = vaultRevision
        self.remoteChanges = remoteChanges
        self.stats = stats
    }
}

public struct RemoteMCPHealthResult: Codable, Equatable, Sendable {
    public var ok: Bool
    public var service: String
    public var mcpEnabled: Bool
    public var allowsChanges: Bool
    public var stats: RemoteMCPStats

    public init(
        ok: Bool,
        service: String,
        mcpEnabled: Bool,
        allowsChanges: Bool,
        stats: RemoteMCPStats
    ) {
        self.ok = ok
        self.service = service
        self.mcpEnabled = mcpEnabled
        self.allowsChanges = allowsChanges
        self.stats = stats
    }
}

public struct RemoteMCPConfigPatch: Codable, Equatable, Sendable {
    public var mcpEnabled: Bool?
    public var allowsChanges: Bool?
    public var salaryHidden: Bool?
    public var mcpToken: String?
    public var currency: CurrencyCode?
    public var timeZoneOffsetMinutes: Int?

    public init(
        mcpEnabled: Bool? = nil,
        allowsChanges: Bool? = nil,
        salaryHidden: Bool? = nil,
        mcpToken: String? = nil,
        currency: CurrencyCode? = nil,
        timeZoneOffsetMinutes: Int? = nil
    ) {
        self.mcpEnabled = mcpEnabled
        self.allowsChanges = allowsChanges
        self.salaryHidden = salaryHidden
        self.mcpToken = mcpToken
        self.currency = currency
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
    }
}

public struct RemoteMCPParingCode: Codable, Equatable, Sendable {
    public var code: String
    public var expiresAt: Date

    public init(code: String, expiresAt: Date) {
        self.code = code
        self.expiresAt = expiresAt
    }
}

public enum RemoteMCPError: Error, Equatable, Sendable {
    case invalidURL
    case missingSecret
    case unauthorized
    case serverError(Int)
    case network(String)

    public func localizedMessage(in language: AppLanguage) -> String {
        switch self {
        case .invalidURL:
            return L10n.text(language, en: "Enter a valid HTTPS Cloud MCP Worker URL.", vi: "Nhập địa chỉ HTTPS hợp lệ của Cloud MCP Worker.", zh: "请输入有效的 HTTPS Cloud MCP Worker 地址。")
        case .missingSecret:
            return L10n.text(language, en: "Missing Cloud MCP sync secret.", vi: "Thiếu mã đồng bộ Cloud MCP.", zh: "缺少 Cloud MCP 同步密钥。")
        case .unauthorized:
            return L10n.text(language, en: "Cloud MCP sync secret was rejected (401).", vi: "Mã đồng bộ bị từ chối (401).", zh: "同步密钥被拒绝（401）。")
        case .serverError(let code):
            return L10n.text(language, en: "Cloud MCP server returned HTTP \(code).", vi: "Máy chủ Cloud MCP trả về lỗi HTTP \(code).", zh: "Cloud MCP 服务器返回 HTTP \(code) 错误。")
        case .network(let detail):
            return L10n.text(language, en: "Connection failed: \(detail)", vi: "Lỗi kết nối: \(detail)", zh: "连接失败：\(detail)")
        }
    }
}

// MARK: - Transport & Client

public protocol RemoteMCPHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionRemoteMCPTransport: RemoteMCPHTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 25) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteMCPError.network("Invalid HTTP response")
        }
        return (data, http.statusCode)
    }
}

/// Pure Foundation client for Tally's Cloud MCP Cloudflare Worker (`tools/mcp-server`).
public struct RemoteMCPSyncClient: Sendable {
    public let baseURL: URL
    private let syncSecret: String
    private let transport: any RemoteMCPHTTPTransport

    public init(
        baseURL: URL,
        syncSecret: String,
        transport: any RemoteMCPHTTPTransport = URLSessionRemoteMCPTransport()
    ) {
        self.baseURL = baseURL
        self.syncSecret = syncSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
    }

    public func health() async throws -> RemoteMCPHealthResult {
        try await request(path: "v1/health", method: "GET", body: Optional<Int>.none)
    }

    public func sync(_ payload: RemoteMCPSyncPayload) async throws -> RemoteMCPSyncResult {
        try await request(path: "v1/sync", method: "POST", body: payload)
    }

    public func updateConfig(_ patch: RemoteMCPConfigPatch) async throws {
        struct Ack: Decodable { let ok: Bool }
        let _: Ack = try await request(path: "v1/config", method: "POST", body: patch)
    }

    public func requestPairingCode() async throws -> RemoteMCPParingCode {
        struct Empty: Encodable {}
        return try await request(path: "v1/pairing-code", method: "POST", body: Empty())
    }

    private func request<Body: Encodable, Output: Decodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Output {
        guard !syncSecret.isEmpty else { throw RemoteMCPError.missingSecret }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(syncSecret)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.makeEncoder().encode(body)
        }

        let (data, status): (Data, Int)
        do {
            (data, status) = try await transport.send(req)
        } catch let err as RemoteMCPError {
            throw err
        } catch {
            throw RemoteMCPError.network(error.localizedDescription)
        }

        if status == 401 || status == 403 {
            throw RemoteMCPError.unauthorized
        }
        guard (200..<300).contains(status) else {
            throw RemoteMCPError.serverError(status)
        }

        do {
            return try Self.makeDecoder().decode(Output.self, from: data)
        } catch {
            throw RemoteMCPError.network("Could not decode server response: \(error.localizedDescription)")
        }
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFrac.date(from: raw) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(raw)")
        }
        return decoder
    }
}
