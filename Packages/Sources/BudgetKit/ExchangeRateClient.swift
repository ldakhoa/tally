import Foundation
import TallyCore

public enum ExchangeRateError: Error, Equatable, Sendable {
    case network(String)
    case serverError(Int)
    case invalidResponse
}

public protocol FXHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionFXTransport: FXHTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 8) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExchangeRateError.network("Invalid HTTP response")
        }
        return (data, http.statusCode)
    }
}

/// Pure Foundation client that fetches live FX rates anchored at SGD from free, no-key public endpoints.
public struct ExchangeRateClient: Sendable {
    public static let primaryCurrencyAPIURL = URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/sgd.min.json")!
    public static let mirrorCurrencyAPIURL = URL(string: "https://latest.currency-api.pages.dev/v1/currencies/sgd.min.json")!
    public static let fallbackOpenERAPIURL = URL(string: "https://open.er-api.com/v6/latest/SGD")!

    private let transport: any FXHTTPTransport

    public init(transport: any FXHTTPTransport = URLSessionFXTransport()) {
        self.transport = transport
    }

    public func fetchLatest(now: Date = Date()) async throws -> ExchangeRateTable {
        let candidates: [(URL, (Data, Date) -> ExchangeRateTable?)] = [
            (Self.primaryCurrencyAPIURL, Self.parseCurrencyAPIJSON),
            (Self.mirrorCurrencyAPIURL, Self.parseCurrencyAPIJSON),
            (Self.fallbackOpenERAPIURL, Self.parseOpenERAPIJSON),
        ]

        var lastError: Error = ExchangeRateError.invalidResponse
        for (url, parser) in candidates {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, status) = try await transport.send(request)
                guard (200..<300).contains(status) else {
                    lastError = ExchangeRateError.serverError(status)
                    continue
                }
                if let table = parser(data, now) {
                    return table
                }
                lastError = ExchangeRateError.invalidResponse
            } catch let err as ExchangeRateError {
                lastError = err
            } catch {
                lastError = ExchangeRateError.network(error.localizedDescription)
            }
        }
        throw lastError
    }

    static func parseCurrencyAPIJSON(_ data: Data, now: Date) -> ExchangeRateTable? {
        struct Payload: Decodable {
            let date: String?
            let sgd: [String: Double]
        }
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        return validatedTable(rawRates: decoded.sgd, rateDate: decoded.date, now: now)
    }

    static func parseOpenERAPIJSON(_ data: Data, now: Date) -> ExchangeRateTable? {
        struct Payload: Decodable {
            let result: String?
            let base_code: String?
            let time_last_update_unix: TimeInterval?
            let rates: [String: Double]
        }
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: data),
              decoded.result?.lowercased() == "success",
              (decoded.base_code ?? "SGD").uppercased() == "SGD"
        else {
            return nil
        }
        let dateKey: String? = decoded.time_last_update_unix.map { ts in
            DateKey.dayKey(from: Date(timeIntervalSince1970: ts))
        }
        return validatedTable(rawRates: decoded.rates, rateDate: dateKey, now: now)
    }

    private static func validatedTable(rawRates: [String: Double], rateDate: String?, now: Date) -> ExchangeRateTable? {
        var normalized: [String: Double] = ["SGD": 1.0]
        for (key, value) in rawRates {
            guard value > 0, value.isFinite,
                  let code = CurrencyCode.normalizeCode(key)
            else { continue }
            normalized[code] = value
        }
        normalized["SGD"] = 1.0
        guard normalized.count >= 20 else { return nil }
        let cleanedDate: String? = {
            guard let raw = rateDate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  DateKey.date(fromDayKey: raw) != nil
            else { return nil }
            return raw
        }()
        return ExchangeRateTable(ratesPerSGD: normalized, rateDate: cleanedDate, fetchedAt: now)
    }
}
