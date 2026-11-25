import BudgetKit
import Foundation
import Observation
import TallyCore

/// Caches live exchange rates locally in UserDefaults and refreshes them in the background.
@MainActor
@Observable
public final class ExchangeRateService {
    public static let shared = ExchangeRateService()

    public private(set) var table: ExchangeRateTable
    public private(set) var isRefreshing = false
    public private(set) var lastError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client: ExchangeRateClient
    @ObservationIgnored private let updatesSharedCurrent: Bool

    private static let cacheKey = "tally.fx.cachedRates"

    public init(
        defaults: UserDefaults = .standard,
        client: ExchangeRateClient = ExchangeRateClient(),
        updatesSharedCurrent: Bool = true
    ) {
        self.defaults = defaults
        self.client = client
        self.updatesSharedCurrent = updatesSharedCurrent

        if let data = defaults.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode(ExchangeRateTable.self, from: data),
           decoded.ratesPerSGD.count >= 10 {
            self.table = decoded
        } else {
            self.table = .fallback
        }

        if updatesSharedCurrent {
            ExchangeRateTable.current = self.table
        }
    }

    public func refreshIfStale(maxAge: TimeInterval = 12 * 3600, now: Date = Date()) async {
        guard !isRefreshing else { return }
        if let fetchedAt = table.fetchedAt, now.timeIntervalSince(fetchedAt) < maxAge {
            return
        }
        await refreshNow(now: now)
    }

    public func refreshNow(now: Date = Date()) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            let fetched = try await client.fetchLatest(now: now)
            table = fetched
            if updatesSharedCurrent {
                ExchangeRateTable.current = fetched
            }
            if let data = try? JSONEncoder().encode(fetched) {
                defaults.set(data, forKey: Self.cacheKey)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
