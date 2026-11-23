import Foundation
import TallyCore

public enum TransactionType: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case expense
    case income

    public var id: String { rawValue }

    public func title(in language: AppLanguage) -> String {
        switch self {
        case .expense: return L10n.text(language, en: "Expense", vi: "Chi tiêu")
        case .income: return L10n.text(language, en: "Income", vi: "Thu nhập")
        }
    }

    public var categories: [CategoryID] {
        switch self {
        case .expense: return CategoryID.expenseCategories
        case .income: return CategoryID.incomeCategories
        }
    }
}

public enum CategoryID: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case housing
    case food
    case transport
    case shopping
    case bills
    case health
    case entertainment
    case other
    case salary
    case freelance
    case income

    public var id: String { rawValue }

    public static let expenseCategories: [CategoryID] = [
        .food, .housing, .transport, .shopping, .bills, .health, .entertainment, .other
    ]

    public static let incomeCategories: [CategoryID] = [
        .salary, .freelance, .income
    ]

    public var transactionType: TransactionType {
        Self.incomeCategories.contains(self) ? .income : .expense
    }

    public func title(in language: AppLanguage) -> String {
        switch (self, language.resolved) {
        case (.housing, .english): return "Housing"
        case (.housing, .vietnamese): return "Nhà ở"
        case (.food, .english): return "Food & drink"
        case (.food, .vietnamese): return "Ăn uống"
        case (.transport, .english): return "Transport"
        case (.transport, .vietnamese): return "Di chuyển"
        case (.shopping, .english): return "Shopping"
        case (.shopping, .vietnamese): return "Mua sắm"
        case (.bills, .english): return "Bills & utilities"
        case (.bills, .vietnamese): return "Hóa đơn & tiện ích"
        case (.health, .english): return "Health"
        case (.health, .vietnamese): return "Sức khỏe"
        case (.entertainment, .english): return "Entertainment"
        case (.entertainment, .vietnamese): return "Giải trí"
        case (.other, .english): return "Other"
        case (.other, .vietnamese): return "Khác"
        case (.salary, .english): return "Salary"
        case (.salary, .vietnamese): return "Lương"
        case (.freelance, .english): return "Freelance"
        case (.freelance, .vietnamese): return "Thu nhập thêm"
        case (.income, .english): return "Other income"
        case (.income, .vietnamese): return "Thu nhập khác"
        }
    }

    public var symbol: String {
        switch self {
        case .housing: return "house.fill"
        case .food: return "fork.knife"
        case .transport: return "tram.fill"
        case .shopping: return "bag.fill"
        case .bills: return "bolt.fill"
        case .health: return "heart.fill"
        case .entertainment: return "play.rectangle.fill"
        case .other: return "ellipsis.circle.fill"
        case .salary: return "arrow.down.left.circle.fill"
        case .freelance: return "sparkles"
        case .income: return "plus.circle.fill"
        }
    }

    /// Harmonious editorial hex colors (matching Tally Web's calm earth/botanical tones).
    public var accentHex: UInt32 {
        switch self {
        case .housing: return 0x345F49
        case .food: return 0x5B8A6B
        case .transport: return 0xC49438
        case .shopping: return 0x7D75A8
        case .bills: return 0x678C72
        case .health: return 0xC46E5A
        case .entertainment: return 0x5A889E
        case .other: return 0x859086
        case .salary: return 0x287A4B
        case .freelance: return 0x3B7D65
        case .income: return 0x2F7854
        }
    }
}

public enum TransactionSource: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case manual
    case applePay
    case bankEmail
    case bankNotification
    case shortcut
    case aiQuickAdd
    case imported

    public var id: String { rawValue }

    public var isAutomatic: Bool {
        switch self {
        case .applePay, .bankEmail, .bankNotification, .shortcut: return true
        case .manual, .aiQuickAdd, .imported: return false
        }
    }

    public func title(in language: AppLanguage) -> String {
        switch (self, language.resolved) {
        case (.manual, .english): return "Manual"
        case (.manual, .vietnamese): return "Nhập tay"
        case (.applePay, .english): return "Apple Pay"
        case (.applePay, .vietnamese): return "Apple Pay"
        case (.bankEmail, .english): return "Bank email"
        case (.bankEmail, .vietnamese): return "Email ngân hàng"
        case (.bankNotification, .english): return "Bank alert"
        case (.bankNotification, .vietnamese): return "Thông báo NH"
        case (.shortcut, .english): return "Shortcut"
        case (.shortcut, .vietnamese): return "Phím tắt"
        case (.aiQuickAdd, .english): return "AI quick add"
        case (.aiQuickAdd, .vietnamese): return "AI nhập nhanh"
        case (.imported, .english): return "Imported"
        case (.imported, .vietnamese): return "Đã nhập"
        }
    }

    public var symbol: String {
        switch self {
        case .manual: return "pencil"
        case .applePay: return "creditcard.fill"
        case .bankEmail: return "envelope.fill"
        case .bankNotification: return "bell.badge.fill"
        case .shortcut: return "bolt.horizontal.fill"
        case .aiQuickAdd: return "sparkles"
        case .imported: return "square.and.arrow.down"
        }
    }
}

public enum GoalIcon: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case target
    case shield
    case plane
    case laptop
    case house
    case heart

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .target: return "target"
        case .shield: return "checkmark.shield.fill"
        case .plane: return "airplane"
        case .laptop: return "laptopcomputer"
        case .house: return "house.fill"
        case .heart: return "heart.fill"
        }
    }

    public var accentHex: UInt32 {
        switch self {
        case .target: return 0x355E46
        case .shield: return 0x2F6E52
        case .plane: return 0xB3832E
        case .laptop: return 0x6F659B
        case .house: return 0x345F49
        case .heart: return 0xC46E5A
        }
    }

    public func title(in language: AppLanguage) -> String {
        switch (self, language.resolved) {
        case (.target, .english): return "Target"
        case (.target, .vietnamese): return "Mục tiêu"
        case (.shield, .english): return "Emergency"
        case (.shield, .vietnamese): return "Dự phòng"
        case (.plane, .english): return "Travel"
        case (.plane, .vietnamese): return "Du lịch"
        case (.laptop, .english): return "Tech"
        case (.laptop, .vietnamese): return "Công nghệ"
        case (.house, .english): return "Home"
        case (.house, .vietnamese): return "Nhà cửa"
        case (.heart, .english): return "Family"
        case (.heart, .vietnamese): return "Gia đình"
        }
    }
}

public struct TransactionRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var amountMinor: Int64
    public var type: TransactionType
    public var category: CategoryID
    /// `YYYY-MM-DD`
    public var dayKey: String
    public var createdAt: Date
    public var note: String
    public var source: TransactionSource
    public var rawSourceText: String?
    public var memberID: String
    public var memberName: String
    public var needsReview: Bool
    public var updatedAt: Date
    public var isDeleted: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        amountMinor: Int64,
        type: TransactionType,
        category: CategoryID,
        dayKey: String,
        createdAt: Date = Date(),
        note: String = "",
        source: TransactionSource = .manual,
        rawSourceText: String? = nil,
        memberID: String = HouseholdMember.defaultMeID,
        memberName: String = "",
        needsReview: Bool = false,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.amountMinor = amountMinor
        self.type = type
        self.category = category
        self.dayKey = dayKey
        self.createdAt = createdAt
        self.note = note
        self.source = source
        self.rawSourceText = rawSourceText
        self.memberID = memberID
        self.memberName = memberName
        self.needsReview = needsReview
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    public var monthKey: String { DateKey.monthKey(fromDayKey: dayKey) }
}

public struct BudgetLimitRecord: Codable, Identifiable, Hashable, Sendable {
    /// `"YYYY-MM/category"`
    public var id: String
    public var monthKey: String
    public var category: CategoryID
    public var limitMinor: Int64
    public var updatedAt: Date
    public var isDeleted: Bool

    public init(
        monthKey: String,
        category: CategoryID,
        limitMinor: Int64,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = "\(monthKey)/\(category.rawValue)"
        self.monthKey = monthKey
        self.category = category
        self.limitMinor = limitMinor
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

public struct SavingsGoalRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var icon: GoalIcon
    public var targetMinor: Int64
    public var savedMinor: Int64
    public var updatedAt: Date
    public var isDeleted: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        icon: GoalIcon = .target,
        targetMinor: Int64,
        savedMinor: Int64 = 0,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.targetMinor = targetMinor
        self.savedMinor = savedMinor
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    public var progress: Double {
        guard targetMinor > 0 else { return 0 }
        return min(1.0, max(0.0, Double(savedMinor) / Double(targetMinor)))
    }

    public var percent: Int {
        guard targetMinor > 0 else { return 0 }
        return Int((Double(savedMinor) * 100.0 / Double(targetMinor)).rounded(.down))
    }
}
