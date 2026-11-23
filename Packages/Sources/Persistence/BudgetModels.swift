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
            isDeleted: isDeleted
        )
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
