import Foundation
import TallyCore

/// Salary privacy: the single place that decides what "hide salary" masks.
///
/// Only the salary category (`CategoryID.salary`, income) is protected. Other income (freelance,
/// generic income, refunds) and all spending are never masked. Because a total that includes
/// salary would let it be worked out by subtraction from the visible non-salary income, every
/// *aggregate* that contains at least one salary transaction is masked too; the same aggregate
/// for a period or scope with no salary transaction shows normally.
///
/// UI code asks `isSalaryMasked(hidden:)` on the thing it is about to show (a transaction, a
/// category, a snapshot, a chart point) instead of re-deriving the rule.
public protocol SalaryBearing {
    /// `true` when this value is a salary amount, or an aggregate containing at least one.
    var includesSalary: Bool { get }
}

public extension SalaryBearing {
    /// `true` when the value must not be shown: salary hiding is on and the value includes salary.
    func isSalaryMasked(hidden: Bool) -> Bool { hidden && includesSalary }
}

extension TransactionRecord: SalaryBearing {
    /// A salary transaction: income in the salary category.
    public var includesSalary: Bool { type == .income && category == .salary }
}

extension CategoryID: SalaryBearing {
    /// Per-category figures: only the salary category's figure is protected.
    public var includesSalary: Bool { self == .salary }
}

extension CategorySpend: SalaryBearing {
    public var includesSalary: Bool { category.includesSalary }
}

public enum SalaryPrivacy {
    /// `true` when `transactions` contain at least one salary transaction.
    public static func containsSalary<S: Sequence>(_ transactions: S) -> Bool where S.Element == TransactionRecord {
        transactions.contains { $0.includesSalary }
    }

    /// `true` when an aggregate built from `transactions` (a total, average, net, rate, comparison…)
    /// must be masked: hiding is on and at least one of them is salary.
    public static func masksAggregate<S: Sequence>(of transactions: S, hidden: Bool) -> Bool where S.Element == TransactionRecord {
        hidden && containsSalary(transactions)
    }

    /// The transactions that may be shown or handed to the assistant: everything except salary
    /// transactions while hiding is on.
    public static func visibleTransactions(_ transactions: [TransactionRecord], hidden: Bool) -> [TransactionRecord] {
        hidden ? transactions.filter { !$0.includesSalary } : transactions
    }

    /// Whether a tool result about a transaction may echo its amount. Judged by the *stored*
    /// transaction (before any mutation) and by the category it ends up in, so neither editing a
    /// salary row into another category nor moving a row into salary leaks the figure.
    public static func masksToolEcho(stored: TransactionRecord?, resulting: TransactionRecord, hidden: Bool) -> Bool {
        guard hidden else { return false }
        return (stored?.includesSalary ?? false) || resulting.includesSalary
    }
}
