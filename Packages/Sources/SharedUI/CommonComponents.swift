import AppServices
import BudgetKit
import DesignSystem
import SwiftUI
import TallyCore

public struct MonthSwitcher: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var showingPicker = false

    public init() {}

    public var body: some View {
        let lang = settings.language
        let title = store.selectedPeriod.formattedTitle(language: lang)

        HStack(spacing: 2) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { store.shiftPeriod(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appControl)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.themedPlain)
            .accessibilityLabel(L10n.text(lang, en: "Previous period", vi: "Kỳ trước"))

            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    Text(title)
                        .font(.appControl)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.themedPlain)
            .accessibilityLabel(L10n.text(lang, en: "Choose date or period: \(title)", vi: "Chọn ngày hoặc khoảng thời gian: \(title)"))

            Button {
                withAnimation(.snappy(duration: 0.2)) { store.shiftPeriod(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.appControl)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.themedPlain)
            .accessibilityLabel(L10n.text(lang, en: "Next period", vi: "Kỳ sau"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.cardBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .sheet(isPresented: $showingPicker) {
            PeriodPickerSheet(
                initialPeriod: store.selectedPeriod,
                highlightedDayKeys: store.transactionDayKeys
            ) { chosen in
                withAnimation(.snappy(duration: 0.2)) {
                    store.selectedPeriod = chosen
                }
            }
        }
    }
}

/// Responsive top header bar that keeps the full, untruncated `MonthSwitcher` alongside
/// trailing actions on one line when space allows, and wraps cleanly to two lines otherwise.
public struct PeriodHeaderBar<Actions: View>: View {
    public let actions: Actions

    public init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                MonthSwitcher()
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    actions
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 10) {
                MonthSwitcher()
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
    }
}

/// Airbnb HorizonCalendar-style sheet for picking a day, date range, or full month.
public struct PeriodPickerSheet: View {
    public let initialPeriod: DatePeriod
    public let highlightedDayKeys: Set<String>
    public let onApply: (DatePeriod) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var draftPeriod: DatePeriod

    public init(
        initialPeriod: DatePeriod,
        highlightedDayKeys: Set<String> = [],
        onApply: @escaping (DatePeriod) -> Void
    ) {
        self.initialPeriod = initialPeriod
        self.highlightedDayKeys = highlightedDayKeys
        self.onApply = onApply
        self._draftPeriod = State(initialValue: initialPeriod)
    }

    public var body: some View {
        let lang = settings.language
        NavigationStack {
            VStack(spacing: 0) {
                HorizonPeriodCalendarView(
                    selection: $draftPeriod,
                    language: lang,
                    highlightedDayKeys: highlightedDayKeys
                )

                Divider().overlay(Color.hairline)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draftPeriod.formattedTitle(language: lang))
                                .font(.appHeading)
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let subtitle = draftPeriod.formattedSubtitle(language: lang) {
                                Text(subtitle)
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                            } else {
                                Text(selectionHint(for: draftPeriod, language: lang))
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button(L10n.text(lang, en: "Apply", vi: "Áp dụng")) {
                            onApply(draftPeriod)
                            dismiss()
                        }
                        .pillButton(prominent: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.cardBackground)
            }
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Select dates", vi: "Chọn ngày"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func selectionHint(for period: DatePeriod, language: AppLanguage) -> String {
        switch period {
        case .day:
            return L10n.text(language, en: "Tap another day to select a range", vi: "Chạm ngày khác để chọn khoảng ngày")
        case .range(let start, let end):
            let days = DateKey.daysBetween(min(start, end), max(start, end)) + 1
            return L10n.text(language, en: "\(days) days selected", vi: "Đã chọn \(days) ngày")
        case .month:
            return L10n.text(language, en: "Full month", vi: "Cả tháng")
        }
    }
}

public struct MemberFilterBar: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    public init() {}

    public var body: some View {
        let members = store.knownMembers(settings: settings)
        if members.count > 1 {
            let options: [String] = ["__all__"] + members.map(\.id)
            let binding = Binding<String>(
                get: { store.selectedMemberID ?? "__all__" },
                set: { store.selectedMemberID = ($0 == "__all__") ? nil : $0 }
            )
            ChipPicker(
                L10n.text(settings.language, en: "Household member", vi: "Thành viên"),
                selection: binding,
                options: options,
                sideMargin: 0
            ) { id in
                if id == "__all__" {
                    return L10n.text(settings.language, en: "All", vi: "Cả nhà")
                }
                return members.first(where: { $0.id == id })?.name ?? id
            } symbol: { id in
                id == "__all__" ? "person.2.fill" : "person.fill"
            }
        }
    }
}

public struct CategoryBadge: View {
    public let category: CategoryID
    public var size: CGFloat

    public init(category: CategoryID, size: CGFloat = 36) {
        self.category = category
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(category.tintBackground)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(category.color)
            }
            .accessibilityHidden(true)
    }
}

public struct TransactionRow: View {
    public let transaction: TransactionRecord
    public var showDate: Bool
    public var onTap: (() -> Void)?

    @Environment(AppSettings.self) private var settings

    public init(transaction: TransactionRecord, showDate: Bool = true, onTap: (() -> Void)? = nil) {
        self.transaction = transaction
        self.showDate = showDate
        self.onTap = onTap
    }

    public var body: some View {
        let row = HStack(spacing: 12) {
            CategoryBadge(category: transaction.category, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(transaction.name)
                        .font(.appBodyMedium)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if transaction.needsReview {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 7, height: 7)
                    }
                }

                HStack(spacing: 6) {
                    Text(transaction.category.title(in: settings.language))
                    if showDate {
                        Text("·")
                        Text(DateKey.formatCompactDay(transaction.dayKey, language: settings.language))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if !transaction.memberName.isEmpty {
                        Text("·")
                        Text(transaction.memberName)
                    }
                    if transaction.source != .manual {
                        Image(systemName: transaction.source.symbol)
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(formattedAmount)
                .font(.appAmount)
                .foregroundStyle(transaction.type == .income ? Color.positive : Color.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { row }
                .buttonStyle(.themedPlain)
        } else {
            row
        }
    }

    private var formattedAmount: String {
        let signed = transaction.type == .income ? transaction.amountMinor : -transaction.amountMinor
        return MoneyFormat.format(
            minor: signed,
            currency: settings.currency,
            language: settings.language,
            signed: transaction.type == .income
        )
    }
}
