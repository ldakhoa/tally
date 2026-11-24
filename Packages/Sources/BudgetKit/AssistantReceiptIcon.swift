import Foundation

/// Which hand-drawn icon a chat receipt shows. Receipts persist only the legacy emoji, so the
/// icon is derived from it; that also covers receipts already saved in chat history.
public enum AssistantReceiptIcon: Hashable, Sendable {
    case category(CategoryID)
    case goal(GoalIcon)
    case plan
    case settled
    case unsettled
    case deleted
    /// No matching cozy icon; show the stored emoji as a last resort.
    case emoji(String)
}

extension AssistantActionReceipt {
    public var icon: AssistantReceiptIcon {
        switch kind {
        case .planCreated, .planConverted, .planUpdated: return .plan
        case .planSettled: return .settled
        case .planUnsettled: return .unsettled
        case .planDeleted, .transactionDeleted, .budgetDeleted, .goalDeleted: return .deleted
        case .transactionAdded, .transactionUpdated, .budgetSet:
            if let category = CategoryID.allCases.first(where: { $0.cuteEmoji == emoji }) { return .category(category) }
        case .goalCreated, .goalUpdated:
            if let goal = GoalIcon.allCases.first(where: { $0.cuteEmoji == emoji }) { return .goal(goal) }
        }
        return .emoji(emoji)
    }
}
