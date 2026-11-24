import Foundation
import TallyCore

public enum TransactionType: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case expense
    case income

    public var id: String { rawValue }

    public func title(in language: AppLanguage) -> String {
        switch self {
        case .expense: return L10n.text(language, en: "Expense", vi: "Chi tiêu", zh: "支出")
        case .income: return L10n.text(language, en: "Income", vi: "Thu nhập", zh: "收入")
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
        case (.housing, .chinese): return "住房"
        case (.food, .english): return "Food & drink"
        case (.food, .vietnamese): return "Ăn uống"
        case (.food, .chinese): return "餐饮"
        case (.transport, .english): return "Transport"
        case (.transport, .vietnamese): return "Di chuyển"
        case (.transport, .chinese): return "交通"
        case (.shopping, .english): return "Shopping"
        case (.shopping, .vietnamese): return "Mua sắm"
        case (.shopping, .chinese): return "购物"
        case (.bills, .english): return "Bills & utilities"
        case (.bills, .vietnamese): return "Hóa đơn & tiện ích"
        case (.bills, .chinese): return "账单与水电"
        case (.health, .english): return "Health"
        case (.health, .vietnamese): return "Sức khỏe"
        case (.health, .chinese): return "医疗健康"
        case (.entertainment, .english): return "Entertainment"
        case (.entertainment, .vietnamese): return "Giải trí"
        case (.entertainment, .chinese): return "娱乐"
        case (.other, .english): return "Other"
        case (.other, .vietnamese): return "Khác"
        case (.other, .chinese): return "其他"
        case (.salary, .english): return "Salary"
        case (.salary, .vietnamese): return "Lương"
        case (.salary, .chinese): return "工资"
        case (.freelance, .english): return "Freelance"
        case (.freelance, .vietnamese): return "Thu nhập thêm"
        case (.freelance, .chinese): return "兼职副业"
        case (.income, .english): return "Other income"
        case (.income, .vietnamese): return "Thu nhập khác"
        case (.income, .chinese): return "其他收入"
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

    public var cuteEmoji: String {
        switch self {
        case .housing: return "🏡"
        case .food: return "🍱"
        case .transport: return "🛵"
        case .shopping: return "🛍️"
        case .bills: return "💡"
        case .health: return "💊"
        case .entertainment: return "🎬"
        case .other: return "🧸"
        case .salary: return "💰"
        case .freelance: return "✨"
        case .income: return "🎁"
        }
    }

    /// Warm, cozy pastel-inspired hex colors for categories (chosen to contrast cleanly with each emoji).
    public var accentHex: UInt32 {
        switch self {
        case .housing: return 0xE68A6E
        case .food: return 0xF0944D
        case .transport: return 0x5B9EC9
        case .shopping: return 0xD97CA6
        case .bills: return 0x6482B8
        case .health: return 0xE06E7B
        case .entertainment: return 0x9C7FD1
        case .other: return 0xA88874
        case .salary: return 0x459E6E
        case .freelance: return 0x4EA699
        case .income: return 0x56A868
        }
    }

    /// Quick tap-to-fill merchant/description chips tailored to each category.
    public func quickDescriptions(in language: AppLanguage) -> [String] {
        switch (self, language.resolved) {
        case (.food, .english):
            return ["Coffee", "Groceries", "Lunch", "Dinner", "Breakfast", "Hawker", "Drinks"]
        case (.food, .vietnamese):
            return ["Cà phê", "Đi chợ", "Ăn trưa", "Ăn tối", "Ăn sáng", "Đồ uống", "Ăn vặt"]
        case (.food, .chinese):
            return ["咖啡", "买菜", "午餐", "晚餐", "早餐", "饮料", "零食"]
        case (.transport, .english):
            return ["MRT / Bus", "Grab", "Taxi", "Parking", "Petrol"]
        case (.transport, .vietnamese):
            return ["MRT / Xe buýt", "Grab", "Taxi", "Gửi xe", "Đổ xăng"]
        case (.transport, .chinese):
            return ["地铁/公交", "打车", "出租车", "停车费", "加油"]
        case (.shopping, .english):
            return ["Groceries", "Household", "Clothes", "Online order", "Gifts"]
        case (.shopping, .vietnamese):
            return ["Siêu thị", "Đồ gia dụng", "Quần áo", "Mua online", "Quà tặng"]
        case (.shopping, .chinese):
            return ["超市", "日用品", "衣服", "网购", "礼物"]
        case (.housing, .english):
            return ["Rent", "Furniture", "Home supplies", "Maintenance"]
        case (.housing, .vietnamese):
            return ["Tiền nhà", "Nội thất", "Đồ dùng nhà", "Bảo trì"]
        case (.housing, .chinese):
            return ["房租", "家具", "家居用品", "维修"]
        case (.bills, .english):
            return ["Electricity", "Internet", "Mobile bill", "Water", "Subscription"]
        case (.bills, .vietnamese):
            return ["Tiền điện", "Internet", "Cước di động", "Tiền nước", "Đăng ký tháng"]
        case (.bills, .chinese):
            return ["电费", "宽带", "话费", "水费", "订阅服务"]
        case (.health, .english):
            return ["Pharmacy", "Clinic", "Gym", "Dental", "Supplements"]
        case (.health, .vietnamese):
            return ["Nhà thuốc", "Khám bệnh", "Gym", "Nha khoa", "Vitamin"]
        case (.health, .chinese):
            return ["药店", "看病", "健身", "牙科", "保健品"]
        case (.entertainment, .english):
            return ["Movies", "Streaming", "Games", "Weekend outing", "Books"]
        case (.entertainment, .vietnamese):
            return ["Xem phim", "Giải trí", "Game", "Đi chơi cuối tuần", "Sách"]
        case (.entertainment, .chinese):
            return ["电影", "影音会员", "游戏", "周末出游", "书籍"]
        case (.other, .english):
            return ["Coffee", "Groceries", "Personal", "Family", "Gift"]
        case (.other, .vietnamese):
            return ["Cà phê", "Đi chợ", "Cá nhân", "Gia đình", "Quà tặng"]
        case (.other, .chinese):
            return ["咖啡", "日用", "个人", "家庭", "礼物"]
        case (.salary, .english):
            return ["Monthly salary", "Bonus", "Allowance"]
        case (.salary, .vietnamese):
            return ["Lương tháng", "Thưởng", "Phụ cấp"]
        case (.salary, .chinese):
            return ["月薪", "奖金", "补贴"]
        case (.freelance, .english):
            return ["Freelance", "Side project", "Consulting"]
        case (.freelance, .vietnamese):
            return ["Freelance", "Dự án ngoài", "Tư vấn"]
        case (.freelance, .chinese):
            return ["自由职业", "副业项目", "咨询费"]
        case (.income, .english):
            return ["PayNow transfer", "Refund", "Cashback", "Dividend"]
        case (.income, .vietnamese):
            return ["Chuyển khoản", "Hoàn tiền", "Hoàn thẻ", "Cổ tức"]
        case (.income, .chinese):
            return ["转账", "退款", "返现", "分红"]
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
        case (.manual, .chinese): return "手动记账"
        case (.applePay, .english): return "Apple Pay"
        case (.applePay, .vietnamese): return "Apple Pay"
        case (.applePay, .chinese): return "Apple Pay"
        case (.bankEmail, .english): return "Bank email"
        case (.bankEmail, .vietnamese): return "Email ngân hàng"
        case (.bankEmail, .chinese): return "银行邮件"
        case (.bankNotification, .english): return "Bank alert"
        case (.bankNotification, .vietnamese): return "Thông báo NH"
        case (.bankNotification, .chinese): return "银行通知"
        case (.shortcut, .english): return "Shortcut"
        case (.shortcut, .vietnamese): return "Phím tắt"
        case (.shortcut, .chinese): return "快捷指令"
        case (.aiQuickAdd, .english): return "AI quick add"
        case (.aiQuickAdd, .vietnamese): return "AI nhập nhanh"
        case (.aiQuickAdd, .chinese): return "AI 快速记账"
        case (.imported, .english): return "Imported"
        case (.imported, .vietnamese): return "Đã nhập"
        case (.imported, .chinese): return "已导入"
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

    public var cuteEmoji: String {
        switch self {
        case .target: return "🎯"
        case .shield: return "🛡️"
        case .plane: return "✈️"
        case .laptop: return "💻"
        case .house: return "🏡"
        case .heart: return "💕"
        }
    }

    public var accentHex: UInt32 {
        switch self {
        case .target: return 0xE67360
        case .shield: return 0x459E6E
        case .plane: return 0x5B9EC9
        case .laptop: return 0x9C7FD1
        case .house: return 0xF0944D
        case .heart: return 0xD97CA6
        }
    }

    public func title(in language: AppLanguage) -> String {
        switch (self, language.resolved) {
        case (.target, .english): return "Target"
        case (.target, .vietnamese): return "Mục tiêu"
        case (.target, .chinese): return "目标"
        case (.shield, .english): return "Emergency"
        case (.shield, .vietnamese): return "Dự phòng"
        case (.shield, .chinese): return "应急金"
        case (.plane, .english): return "Travel"
        case (.plane, .vietnamese): return "Du lịch"
        case (.plane, .chinese): return "旅行"
        case (.laptop, .english): return "Tech"
        case (.laptop, .vietnamese): return "Công nghệ"
        case (.laptop, .chinese): return "数码"
        case (.house, .english): return "Home"
        case (.house, .vietnamese): return "Nhà cửa"
        case (.house, .chinese): return "家居"
        case (.heart, .english): return "Family"
        case (.heart, .vietnamese): return "Gia đình"
        case (.heart, .chinese): return "家庭"
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
    /// Installment/loan plan this transaction belongs to. On a scheduled payment it is the
    /// owning plan; on a tombstoned original expense that was converted into a plan it marks the
    /// conversion (see `isConvertedPlanSource`). `nil` for ordinary transactions and for
    /// payloads written before plans existed.
    public var planID: String?
    /// 0-based schedule index for a plan payment (`nil` otherwise).
    public var planPaymentIndex: Int?
    /// Merge state of a scheduled plan payment: the latest explicit user operation and the
    /// automatic schedule state, kept apart so merging is a join (see `PlanPaymentState`). The
    /// visible fields above are derived from it. `nil` for ordinary transactions and payloads
    /// written before plans existed.
    public var paymentState: PlanPaymentState?

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
        isDeleted: Bool = false,
        planID: String? = nil,
        planPaymentIndex: Int? = nil,
        paymentState: PlanPaymentState? = nil
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
        self.planID = planID
        self.planPaymentIndex = planPaymentIndex
        self.paymentState = paymentState
    }

    public var monthKey: String { DateKey.monthKey(fromDayKey: dayKey) }

    /// `true` for a scheduled installment/loan payment (live or tombstoned).
    public var isPlanPayment: Bool {
        guard let planID else { return false }
        return planPaymentIndex != nil || id.hasPrefix(InstallmentPlanRecord.paymentIDPrefix(planID: planID))
    }

    /// `true` for a plan payment whose visible state comes from an explicit user operation (or
    /// that has no schedule state at all). Automatic schedule writes never override it.
    public var hasUserPaymentWrite: Bool {
        isPlanPayment && effectivePaymentState.user != nil
    }

    /// `true` for a plan payment the user explicitly deleted (also by deleting its plan with
    /// payments). It is never booked again; only a later explicit user operation revives it.
    /// Withdrawals by the schedule are not user deletions and stay revivable.
    public var isUserDeletedPlanPayment: Bool {
        isDeleted && hasUserPaymentWrite
    }

    /// `true` for a tombstoned expense that was converted into an installment plan. Deduplication
    /// treats it as "already captured" so the same bank alert cannot resurrect the full amount.
    public var isConvertedPlanSource: Bool {
        isDeleted && planID != nil && !isPlanPayment
    }
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
