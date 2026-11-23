import Foundation
import TallyCore

/// Export/import codec compatible with the Tally Web JSON backup format (`version: 1`).
public struct TallyBackupDocument: Codable, Hashable, Sendable {
    public struct BackupTransaction: Codable, Hashable, Sendable {
        public var id: String
        public var date: String
        public var name: String
        public var category: String
        public var type: String
        public var amount: Int64
        public var note: String?
        public var source: String?
        public var memberID: String?
        public var memberName: String?
    }

    public struct BackupGoal: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var icon: String
        public var target: Int64
        public var saved: Int64
    }

    public var version: Int
    public var currency: String
    public var transactions: [BackupTransaction]
    public var budgets: [String: Int64]
    public var goals: [BackupGoal]

    public init(
        version: Int = 1,
        currency: String,
        transactions: [BackupTransaction],
        budgets: [String: Int64],
        goals: [BackupGoal]
    ) {
        self.version = version
        self.currency = currency
        self.transactions = transactions
        self.budgets = budgets
        self.goals = goals
    }
}

public enum WebBackupCodec {
    public enum BackupError: Error, LocalizedError {
        case invalidFormat
        case unsupportedCurrency

        public var errorDescription: String? {
            switch self {
            case .invalidFormat: return "This file is not a valid Tally backup."
            case .unsupportedCurrency: return "Unsupported currency in backup file."
            }
        }
    }

    public static func encode(
        currency: CurrencyCode,
        transactions: [TransactionRecord],
        budgets: [BudgetLimitRecord],
        goals: [SavingsGoalRecord]
    ) throws -> Data {
        let activeTx = transactions.filter { !$0.isDeleted }.map { tx in
            TallyBackupDocument.BackupTransaction(
                id: tx.id,
                date: tx.dayKey,
                name: tx.name,
                category: tx.category.rawValue,
                type: tx.type.rawValue,
                amount: tx.amountMinor,
                note: tx.note.isEmpty ? nil : tx.note,
                source: tx.source == .manual ? nil : tx.source.rawValue,
                memberID: tx.memberID,
                memberName: tx.memberName.isEmpty ? nil : tx.memberName
            )
        }
        var budgetMap: [String: Int64] = [:]
        for b in budgets where !b.isDeleted {
            budgetMap[b.id] = b.limitMinor
        }
        let activeGoals = goals.filter { !$0.isDeleted }.map { g in
            TallyBackupDocument.BackupGoal(
                id: g.id,
                name: g.name,
                icon: g.icon.rawValue,
                target: g.targetMinor,
                saved: g.savedMinor
            )
        }
        let doc = TallyBackupDocument(
            version: 1,
            currency: currency.rawValue,
            transactions: activeTx,
            budgets: budgetMap,
            goals: activeGoals
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(doc)
    }

    public static func decode(_ data: Data) throws -> (
        currency: CurrencyCode,
        transactions: [TransactionRecord],
        budgets: [BudgetLimitRecord],
        goals: [SavingsGoalRecord]
    ) {
        let doc: TallyBackupDocument
        do {
            doc = try JSONDecoder().decode(TallyBackupDocument.self, from: data)
        } catch {
            throw BackupError.invalidFormat
        }
        guard doc.version == 1 else { throw BackupError.invalidFormat }
        guard let currency = CurrencyCode(rawValue: doc.currency) else { throw BackupError.unsupportedCurrency }

        let now = Date()
        let transactions: [TransactionRecord] = doc.transactions.compactMap { item in
            guard let type = TransactionType(rawValue: item.type),
                  let category = CategoryID(rawValue: item.category),
                  DateKey.date(fromDayKey: item.date) != nil,
                  item.amount > 0
            else { return nil }
            let source = item.source.flatMap(TransactionSource.init(rawValue:)) ?? .imported
            return TransactionRecord(
                id: item.id,
                name: item.name,
                amountMinor: item.amount,
                type: type,
                category: category,
                dayKey: item.date,
                createdAt: DateKey.date(fromDayKey: item.date) ?? now,
                note: item.note ?? "",
                source: source,
                memberID: item.memberID ?? HouseholdMember.defaultMeID,
                memberName: item.memberName ?? "",
                needsReview: false,
                updatedAt: now
            )
        }

        let budgets: [BudgetLimitRecord] = doc.budgets.compactMap { key, limit in
            let parts = key.split(separator: "/")
            guard parts.count == 2,
                  let category = CategoryID(rawValue: String(parts[1])),
                  limit > 0
            else { return nil }
            return BudgetLimitRecord(monthKey: String(parts[0]), category: category, limitMinor: limit, updatedAt: now)
        }

        let goals: [SavingsGoalRecord] = doc.goals.compactMap { item in
            guard item.target > 0, item.saved >= 0 else { return nil }
            let icon = GoalIcon(rawValue: item.icon) ?? .target
            return SavingsGoalRecord(
                id: item.id,
                name: item.name,
                icon: icon,
                targetMinor: item.target,
                savedMinor: item.saved,
                updatedAt: now
            )
        }

        return (currency, transactions, budgets, goals)
    }
}

public enum SampleBudgetData {
    public static func make(
        monthKey: String = DateKey.monthKey(from: Date()),
        currency: CurrencyCode = .sgd,
        language: AppLanguage = .english,
        myName: String = "Khoa",
        partnerName: String = "Wife"
    ) -> (transactions: [TransactionRecord], budgets: [BudgetLimitRecord], goals: [SavingsGoalRecord]) {
        let scale: Double = currency == .vnd ? 18_500.0 : 1.0
        func amt(_ sgd: Double) -> Int64 {
            let value = currency == .vnd ? (sgd * scale).rounded() : sgd
            return currency.toStorageMinor(max(1, value))
        }
        let isVI = language.resolved == .vietnamese
        let me = HouseholdMember.defaultMeID
        let partner = HouseholdMember.defaultPartnerID
        let todayDay = min(28, DateKey.dayOfMonth(fromDayKey: DateKey.dayKey(from: Date())))

        let rows: [(Int, String, String, CategoryID, TransactionType, Double, String, String, TransactionSource)] = [
            (todayDay, "Ya Kun Kaya Toast", "Ya Kun Kaya Toast", .food, .expense, 7.80, me, myName, .applePay),
            (max(1, todayDay - 1), "Đi siêu thị FairPrice", "FairPrice groceries", .food, .expense, 94.50, partner, partnerName, .bankEmail),
            (max(1, todayDay - 2), "SimplyGo MRT & Bus", "SimplyGo MRT & Bus", .transport, .expense, 28.40, me, myName, .applePay),
            (max(1, todayDay - 3), "SP Group Điện & Nước", "SP Group utilities", .bills, .expense, 168.00, partner, partnerName, .bankEmail),
            (max(1, todayDay - 4), "Ăn tối cùng bạn bè", "Dinner with friends", .food, .expense, 86.20, me, myName, .applePay),
            (max(1, todayDay - 5), "Đồ gia dụng Shopee SG", "Shopee household items", .shopping, .expense, 112.00, partner, partnerName, .bankNotification),
            (3, "Tiền thuê nhà", "Monthly rent", .housing, .expense, 2_800.00, me, myName, .bankEmail),
            (2, "Lương tháng", "Monthly salary", .salary, .income, 6_500.00, me, myName, .bankEmail),
            (2, "Lương tháng (Vợ)", "Salary (Partner)", .salary, .income, 4_200.00, partner, partnerName, .manual),
        ]

        let transactions = rows.enumerated().map { idx, r in
            let day = String(format: "%@-%02d", monthKey, min(DateKey.daysInMonth(monthKey), r.0))
            return TransactionRecord(
                id: "sample-tx-\(idx)",
                name: isVI ? r.1 : r.2,
                amountMinor: amt(r.5),
                type: r.4,
                category: r.3,
                dayKey: day,
                createdAt: DateKey.date(fromDayKey: day) ?? Date(),
                source: r.8,
                memberID: r.6,
                memberName: r.7,
                needsReview: idx == 0
            )
        }

        let budgets: [BudgetLimitRecord] = [
            BudgetLimitRecord(monthKey: monthKey, category: .housing, limitMinor: amt(2_800)),
            BudgetLimitRecord(monthKey: monthKey, category: .food, limitMinor: amt(1_200)),
            BudgetLimitRecord(monthKey: monthKey, category: .transport, limitMinor: amt(300)),
            BudgetLimitRecord(monthKey: monthKey, category: .shopping, limitMinor: amt(500)),
            BudgetLimitRecord(monthKey: monthKey, category: .bills, limitMinor: amt(300)),
        ]

        let goals: [SavingsGoalRecord] = [
            SavingsGoalRecord(id: "sample-goal-1", name: isVI ? "Quỹ dự phòng" : "Emergency fund", icon: .shield, targetMinor: amt(20_000), savedMinor: amt(13_500)),
            SavingsGoalRecord(id: "sample-goal-2", name: isVI ? "Du lịch Nhật Bản" : "Japan trip", icon: .plane, targetMinor: amt(5_000), savedMinor: amt(2_100)),
            SavingsGoalRecord(id: "sample-goal-3", name: isVI ? "Quỹ gia đình" : "Family fund", icon: .heart, targetMinor: amt(10_000), savedMinor: amt(4_500)),
        ]

        return (transactions, budgets, goals)
    }
}
