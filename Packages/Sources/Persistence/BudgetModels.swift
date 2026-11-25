import BudgetKit
import Foundation
import SwiftData
import TallyCore

@Model
public final class SDTransaction {
    @Attribute(.unique) public var recordID: String
    public var name: String
    public var amountMinor: Int64
    public var typeRaw: String
    public var categoryRaw: String
    public var dayKey: String
    public var createdAt: Date
    public var note: String
    public var sourceRaw: String
    public var rawSourceText: String?
    public var memberID: String
    public var memberName: String
    public var needsReview: Bool
    public var updatedAt: Date
    public var isDeleted: Bool
    // Added with installment plans. Optional so existing stores migrate lightweight.
    public var planID: String?
    public var planPaymentIndex: Int?
    // JSON-encoded `PlanPaymentState` of a plan payment. Optional so existing stores migrate
    // lightweight.
    public var paymentStateData: Data?
    // Added for foreign-currency transactions. Optional so existing stores migrate lightweight.
    public var originalAmountMinor: Int64?
    public var originalCurrencyCode: String?
    public var exchangeRate: Double?

    public init(from record: TransactionRecord) {
        self.recordID = record.id
        self.name = record.name
        self.amountMinor = record.amountMinor
        self.typeRaw = record.type.rawValue
        self.categoryRaw = record.category.rawValue
        self.dayKey = record.dayKey
        self.createdAt = record.createdAt
        self.note = record.note
        self.sourceRaw = record.source.rawValue
        self.rawSourceText = record.rawSourceText
        self.memberID = record.memberID
        self.memberName = record.memberName
        self.needsReview = record.needsReview
        self.updatedAt = record.updatedAt
        self.isDeleted = record.isDeleted
        self.planID = record.planID
        self.planPaymentIndex = record.planPaymentIndex
        self.paymentStateData = Self.encode(record.paymentState)
        self.originalAmountMinor = record.originalAmountMinor
        self.originalCurrencyCode = record.originalCurrencyCode
        self.exchangeRate = record.exchangeRate
    }

    public func apply(_ record: TransactionRecord) {
        name = record.name
        amountMinor = record.amountMinor
        typeRaw = record.type.rawValue
        categoryRaw = record.category.rawValue
        dayKey = record.dayKey
        createdAt = record.createdAt
        note = record.note
        sourceRaw = record.source.rawValue
        rawSourceText = record.rawSourceText
        memberID = record.memberID
        memberName = record.memberName
        needsReview = record.needsReview
        updatedAt = record.updatedAt
        isDeleted = record.isDeleted
        planID = record.planID
        planPaymentIndex = record.planPaymentIndex
        paymentStateData = Self.encode(record.paymentState)
        originalAmountMinor = record.originalAmountMinor
        originalCurrencyCode = record.originalCurrencyCode
        exchangeRate = record.exchangeRate
    }

    public var record: TransactionRecord {
        TransactionRecord(
            id: recordID,
            name: name,
            amountMinor: amountMinor,
            type: TransactionType(rawValue: typeRaw) ?? .expense,
            category: CategoryID(rawValue: categoryRaw) ?? .other,
            dayKey: dayKey,
            createdAt: createdAt,
            note: note,
            source: TransactionSource(rawValue: sourceRaw) ?? .manual,
            rawSourceText: rawSourceText,
            memberID: memberID,
            memberName: memberName,
            needsReview: needsReview,
            updatedAt: updatedAt,
            isDeleted: isDeleted,
            planID: planID,
            planPaymentIndex: planPaymentIndex,
            paymentState: paymentStateData.flatMap { try? JSONDecoder().decode(PlanPaymentState.self, from: $0) },
            originalAmountMinor: originalAmountMinor,
            originalCurrencyCode: originalCurrencyCode,
            exchangeRate: exchangeRate
        )
    }

    private static func encode(_ state: PlanPaymentState?) -> Data? {
        guard let state else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(state)
    }
}

@Model
public final class SDBudgetLimit {
    @Attribute(.unique) public var recordID: String
    public var monthKey: String
    public var categoryRaw: String
    public var limitMinor: Int64
    public var updatedAt: Date
    public var isDeleted: Bool

    public init(from record: BudgetLimitRecord) {
        self.recordID = record.id
        self.monthKey = record.monthKey
        self.categoryRaw = record.category.rawValue
        self.limitMinor = record.limitMinor
        self.updatedAt = record.updatedAt
        self.isDeleted = record.isDeleted
    }

    public func apply(_ record: BudgetLimitRecord) {
        monthKey = record.monthKey
        categoryRaw = record.category.rawValue
        limitMinor = record.limitMinor
        updatedAt = record.updatedAt
        isDeleted = record.isDeleted
    }

    public var record: BudgetLimitRecord {
        BudgetLimitRecord(
            monthKey: monthKey,
            category: CategoryID(rawValue: categoryRaw) ?? .other,
            limitMinor: limitMinor,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }
}

@Model
public final class SDSavingsGoal {
    @Attribute(.unique) public var recordID: String
    public var name: String
    public var iconRaw: String
    public var targetMinor: Int64
    public var savedMinor: Int64
    public var updatedAt: Date
    public var isDeleted: Bool

    public init(from record: SavingsGoalRecord) {
        self.recordID = record.id
        self.name = record.name
        self.iconRaw = record.icon.rawValue
        self.targetMinor = record.targetMinor
        self.savedMinor = record.savedMinor
        self.updatedAt = record.updatedAt
        self.isDeleted = record.isDeleted
    }

    public func apply(_ record: SavingsGoalRecord) {
        name = record.name
        iconRaw = record.icon.rawValue
        targetMinor = record.targetMinor
        savedMinor = record.savedMinor
        updatedAt = record.updatedAt
        isDeleted = record.isDeleted
    }

    public var record: SavingsGoalRecord {
        SavingsGoalRecord(
            id: recordID,
            name: name,
            icon: GoalIcon(rawValue: iconRaw) ?? .target,
            targetMinor: targetMinor,
            savedMinor: savedMinor,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }
}

@Model
public final class SDInstallmentPlan {
    @Attribute(.unique) public var recordID: String
    public var name: String
    public var kindRaw: String
    public var totalMinor: Int64
    public var months: Int
    public var firstPaymentDayKey: String
    public var categoryRaw: String
    public var memberID: String
    public var memberName: String
    public var note: String
    public var currencyRaw: String
    public var monthlyPaymentMinor: Int64?
    public var principalMinor: Int64?
    public var sourceTransactionID: String?
    public var lender: String?
    public var linkURL: String?
    public var settledDayKey: String?
    // Optional so existing stores migrate lightweight.
    public var deletionRemovesPayments: Bool?
    public var deletedDayKey: String?
    /// Optional so existing stores migrate lightweight; `nil` = no already-paid payments.
    public var alreadyPaidPaymentCount: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var isDeleted: Bool

    public init(from record: InstallmentPlanRecord) {
        self.recordID = record.id
        self.name = record.name
        self.kindRaw = record.kind.rawValue
        self.totalMinor = record.totalMinor
        self.months = record.months
        self.firstPaymentDayKey = record.firstPaymentDayKey
        self.categoryRaw = record.category.rawValue
        self.memberID = record.memberID
        self.memberName = record.memberName
        self.note = record.note
        self.currencyRaw = record.currency.rawValue
        self.monthlyPaymentMinor = record.monthlyPaymentMinor
        self.principalMinor = record.principalMinor
        self.sourceTransactionID = record.sourceTransactionID
        self.lender = record.lender
        self.linkURL = record.linkURL
        self.settledDayKey = record.settledDayKey
        self.deletionRemovesPayments = record.deletionRemovesPayments
        self.deletedDayKey = record.deletedDayKey
        self.alreadyPaidPaymentCount = record.alreadyPaidPaymentCount
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.isDeleted = record.isDeleted
    }

    public func apply(_ record: InstallmentPlanRecord) {
        name = record.name
        kindRaw = record.kind.rawValue
        totalMinor = record.totalMinor
        months = record.months
        firstPaymentDayKey = record.firstPaymentDayKey
        categoryRaw = record.category.rawValue
        memberID = record.memberID
        memberName = record.memberName
        note = record.note
        currencyRaw = record.currency.rawValue
        monthlyPaymentMinor = record.monthlyPaymentMinor
        principalMinor = record.principalMinor
        sourceTransactionID = record.sourceTransactionID
        lender = record.lender
        linkURL = record.linkURL
        settledDayKey = record.settledDayKey
        deletionRemovesPayments = record.deletionRemovesPayments
        deletedDayKey = record.deletedDayKey
        alreadyPaidPaymentCount = record.alreadyPaidPaymentCount
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        isDeleted = record.isDeleted
    }

    public var record: InstallmentPlanRecord {
        InstallmentPlanRecord(
            id: recordID,
            name: name,
            kind: InstallmentKind(rawValue: kindRaw) ?? .installment,
            totalMinor: totalMinor,
            months: months,
            firstPaymentDayKey: firstPaymentDayKey,
            category: CategoryID(rawValue: categoryRaw) ?? .other,
            memberID: memberID,
            memberName: memberName,
            note: note,
            currency: CurrencyCode(rawValue: currencyRaw) ?? .sgd,
            monthlyPaymentMinor: monthlyPaymentMinor,
            principalMinor: principalMinor,
            sourceTransactionID: sourceTransactionID,
            lender: lender,
            linkURL: linkURL,
            settledDayKey: settledDayKey,
            deletionRemovesPayments: deletionRemovesPayments,
            deletedDayKey: deletedDayKey,
            alreadyPaidPaymentCount: alreadyPaidPaymentCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }
}
