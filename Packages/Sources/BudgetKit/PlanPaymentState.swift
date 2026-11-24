import Foundation
import TallyCore

/// The user-visible fields of a plan payment transaction that a write sets.
public struct PlanPaymentContent: Codable, Hashable, Sendable {
    public var name: String
    public var amountMinor: Int64
    public var type: TransactionType
    public var category: CategoryID
    public var dayKey: String
    public var createdAt: Date
    public var note: String
    public var source: TransactionSource
    public var rawSourceText: String?
    public var memberID: String
    public var memberName: String
    public var needsReview: Bool
    public var isDeleted: Bool

    public init(
        name: String,
        amountMinor: Int64,
        type: TransactionType = .expense,
        category: CategoryID,
        dayKey: String,
        createdAt: Date,
        note: String = "",
        source: TransactionSource = .manual,
        rawSourceText: String? = nil,
        memberID: String,
        memberName: String = "",
        needsReview: Bool = false,
        isDeleted: Bool
    ) {
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
        self.isDeleted = isDeleted
    }

    public init(_ record: TransactionRecord) {
        self.init(
            name: record.name,
            amountMinor: record.amountMinor,
            type: record.type,
            category: record.category,
            dayKey: record.dayKey,
            createdAt: record.createdAt,
            note: record.note,
            source: record.source,
            rawSourceText: record.rawSourceText,
            memberID: record.memberID,
            memberName: record.memberName,
            needsReview: record.needsReview,
            isDeleted: record.isDeleted
        )
    }
}

/// The latest explicit user operation on a plan payment (edit, delete, restore, or deleting the
/// plan together with its payments). Merged last-writer-wins on `at`.
public struct PlanPaymentUserWrite: Codable, Hashable, Sendable {
    public var at: Date
    public var content: PlanPaymentContent

    public init(at: Date, content: PlanPaymentContent) {
        self.at = at
        self.content = content
    }
}

/// The payment as the plan's schedule wants it (booked, or withdrawn when `content.isDeleted`),
/// derived from the plan revision whose `updatedAt` is `planRevision`. Merged by plan revision
/// first, so a write derived from an older plan never beats one derived from a newer plan.
public struct PlanPaymentScheduleWrite: Codable, Hashable, Sendable {
    public var planRevision: Date
    public var content: PlanPaymentContent

    public init(planRevision: Date, content: PlanPaymentContent) {
        self.planRevision = planRevision
        self.content = content
    }

    public var isBooked: Bool { !content.isDeleted }
}

/// Sync state of a scheduled plan payment, carried on `TransactionRecord.paymentState`.
///
/// The two components merge independently, each by a total order, so the merge of whole states
/// is a join: commutative, associative and idempotent. The visible transaction fields are derived
/// from the state (`TransactionRecord.applying(_:)`):
/// - a user write, if any, decides (automatic booking, re-dating and withdrawal never override an
///   explicit user operation, whatever the timestamps);
/// - otherwise the schedule write decides.
///
/// Orders:
/// - user: `at`, then deletion over non-deletion, then the larger name, then canonical encoding;
/// - schedule: `planRevision`, then booked over withdrawn (a payment that one device on a given
///   plan revision found due stays booked: "due on any device's day"), then canonical encoding.
public struct PlanPaymentState: Codable, Hashable, Sendable {
    public var user: PlanPaymentUserWrite?
    public var schedule: PlanPaymentScheduleWrite?

    public init(user: PlanPaymentUserWrite? = nil, schedule: PlanPaymentScheduleWrite? = nil) {
        self.user = user
        self.schedule = schedule
    }

    public func joined(with other: PlanPaymentState) -> PlanPaymentState {
        PlanPaymentState(
            user: Self.join(user, other.user, by: Self.userPrecedes),
            schedule: Self.join(schedule, other.schedule, by: Self.schedulePrecedes)
        )
    }

    /// Visible content: the user write if present, otherwise the schedule write.
    public var visibleContent: PlanPaymentContent? { user?.content ?? schedule?.content }

    /// Timestamp of the state: the later of the user write and the schedule revision.
    public var stamp: Date? {
        switch (user?.at, schedule?.planRevision) {
        case let (u?, s?): return max(u, s)
        case let (u?, nil): return u
        case let (nil, s?): return s
        case (nil, nil): return nil
        }
    }

    // MARK: Orders

    static func userPrecedes(_ a: PlanPaymentUserWrite, _ b: PlanPaymentUserWrite) -> Bool {
        if a.at != b.at { return a.at < b.at }
        if a.content.isDeleted != b.content.isDeleted { return !a.content.isDeleted }
        if a.content.name != b.content.name { return a.content.name < b.content.name }
        return canonicalPrecedes(a.content, b.content)
    }

    static func schedulePrecedes(_ a: PlanPaymentScheduleWrite, _ b: PlanPaymentScheduleWrite) -> Bool {
        if a.planRevision != b.planRevision { return a.planRevision < b.planRevision }
        if a.isBooked != b.isBooked { return !a.isBooked }
        return canonicalPrecedes(a.content, b.content)
    }

    private static func join<T: Equatable>(_ a: T?, _ b: T?, by precedes: (T, T) -> Bool) -> T? {
        guard let a else { return b }
        guard let b else { return a }
        if a == b { return a }
        return precedes(a, b) ? b : a
    }

    /// Strict total order on encodable values via their sorted-key JSON encoding.
    static func canonicalPrecedes<T: Encodable>(_ a: T, _ b: T) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let lhs = try? encoder.encode(a), let rhs = try? encoder.encode(b) else { return false }
        return lhs.lexicographicallyPrecedes(rhs)
    }
}

extension TransactionRecord {
    /// The payment state used for merging: the stored one, or, for a payment written without one
    /// (an older app version, a hand-built record), its visible fields as a user write at
    /// `updatedAt`.
    public var effectivePaymentState: PlanPaymentState {
        paymentState ?? PlanPaymentState(user: PlanPaymentUserWrite(at: updatedAt, content: PlanPaymentContent(self)))
    }

    /// This record with `state` attached and the visible fields and `updatedAt` derived from it.
    public func applying(_ state: PlanPaymentState) -> TransactionRecord {
        var record = self
        record.paymentState = state
        if let content = state.visibleContent {
            record.name = content.name
            record.amountMinor = content.amountMinor
            record.type = content.type
            record.category = content.category
            record.dayKey = content.dayKey
            record.createdAt = content.createdAt
            record.note = content.note
            record.source = content.source
            record.rawSourceText = content.rawSourceText
            record.memberID = content.memberID
            record.memberName = content.memberName
            record.needsReview = content.needsReview
            record.isDeleted = content.isDeleted
        }
        if let stamp = state.stamp { record.updatedAt = stamp }
        return record
    }

    /// Records an explicit user write of the current visible fields at `at`: for a plan payment it
    /// becomes the payment's latest user operation (see `PlanPaymentState`); for any other
    /// transaction only `updatedAt` changes.
    public func recordingUserWrite(at: Date) -> TransactionRecord {
        guard isPlanPayment else {
            var stamped = self
            stamped.updatedAt = at
            return stamped
        }
        var state = paymentState ?? PlanPaymentState()
        state.user = PlanPaymentUserWrite(at: at, content: PlanPaymentContent(self))
        return applying(state)
    }
}
