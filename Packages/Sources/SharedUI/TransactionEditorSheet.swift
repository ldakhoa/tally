import AppServices
import BudgetKit
import DesignSystem
import SwiftUI
import TallyCore

public struct TransactionEditorSheet: View {
    public let existing: TransactionRecord?
    public let prefill: ParsedTransactionDraft?
    public let sourceOverride: TransactionSource?
    public let rawSourceText: String?

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var type: TransactionType = .expense
    @State private var category: CategoryID = .food
    @State private var dayKey: String = DateKey.dayKey(from: Date())
    @State private var showingDatePicker = false
    @State private var note: String = ""
    @State private var selectedMemberID: String = ""
    @State private var selectedMemberName: String = ""
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    public init(
        existing: TransactionRecord? = nil,
        prefill: ParsedTransactionDraft? = nil,
        sourceOverride: TransactionSource? = nil,
        rawSourceText: String? = nil
    ) {
        self.existing = existing
        self.prefill = prefill
        self.sourceOverride = sourceOverride
        self.rawSourceText = rawSourceText
    }

    public var body: some View {
        let lang = settings.language
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Expense / Income segmented chips
                    HStack(spacing: 8) {
                        ForEach(TransactionType.allCases) { option in
                            let selected = type == option
                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
                                    type = option
                                    if !option.categories.contains(category) {
                                        category = option.categories.first ?? .other
                                    }
                                }
                            } label: {
                                Text(option.title(in: lang))
                                    .font(.appControl)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                                    .background(selected ? Color.ink : Color.softFill, in: Capsule())
                            }
                            .buttonStyle(.themedPlain)
                        }
                    }

                    // Amount field
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(L10n.text(lang, en: "Amount (\(settings.currency.rawValue))", vi: "Số tiền (\(settings.currency.rawValue))"))
                        HStack(spacing: 8) {
                            Text(settings.currency.narrowSymbol)
                                .font(.appTitle)
                                .foregroundStyle(Color.textSecondary)
                            TextField(settings.currency.isZeroDecimal ? "65000" : "18.50", text: $amountText)
                                .font(.appMetricHero)
                                #if os(iOS)
                                .keyboardType(settings.currency.isZeroDecimal ? .numberPad : .decimalPad)
                                #endif
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
                    }

                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(L10n.text(lang, en: "Description / Merchant", vi: "Tên giao dịch / Cửa hàng"))
                        TextField(L10n.text(lang, en: "e.g. Highlands Coffee, Groceries", vi: "VD: Phở Hòa, Đi chợ, Grab"), text: $name)
                            .tallyField()
                    }

                    // Category grid
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(L10n.text(lang, en: "Category", vi: "Danh mục"))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 8)], spacing: 8) {
                            ForEach(type.categories) { item in
                                let selected = category == item
                                Button {
                                    category = item
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: item.symbol)
                                            .font(.caption)
                                            .foregroundStyle(selected ? Color.onInk : item.color)
                                        Text(item.title(in: lang))
                                            .font(.appCaption.weight(.medium))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                    .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                                    .background(selected ? Color.ink : Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                            .strokeBorder(selected ? Color.clear : Color.hairline, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.themedPlain)
                            }
                        }
                    }

                    // Date & Who paid
                    Card {
                        Button {
                            showingDatePicker = true
                        } label: {
                            HStack(spacing: 10) {
                                Text(L10n.text(lang, en: "Date", vi: "Ngày"))
                                    .font(.appBody)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                    Text(DateKey.formatFullDay(dayKey, language: lang))
                                        .font(.appControl)
                                        .foregroundStyle(Color.textPrimary)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.softFill, in: Capsule())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.themedPlain)

                        let members = store.knownMembers(settings: settings)
                        if members.count > 1 || !settings.partnerDisplayName.isEmpty {
                            Divider().overlay(Color.hairline)
                            HStack {
                                Text(L10n.text(lang, en: "Logged by", vi: "Người chi / ghi"))
                                    .font(.appBody)
                                Spacer()
                                Picker("", selection: $selectedMemberID) {
                                    ForEach(memberOptions) { m in
                                        Text(m.name).tag(m.id)
                                    }
                                }
                                .labelsHidden()
                                .onChange(of: selectedMemberID) { _, newID in
                                    if let found = memberOptions.first(where: { $0.id == newID }) {
                                        selectedMemberName = found.name
                                    }
                                }
                            }
                        }
                    }

                    // Note
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(L10n.text(lang, en: "Note (optional)", vi: "Ghi chú (tuỳ chọn)"))
                        TextField(L10n.text(lang, en: "Card, split note, receipt details…", vi: "Thẻ, ghi chú chia tiền…"), text: $note)
                            .tallyField()
                    }

                    if let raw = existing?.rawSourceText ?? rawSourceText, !raw.isEmpty {
                        Card(L10n.text(lang, en: "Original alert text", vi: "Nội dung thông báo gốc"), symbol: "text.quote") {
                            Text(raw)
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                                .textSelection(.enabled)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.appSecondary)
                            .foregroundStyle(Color.negative)
                    }

                    Button(L10n.text(lang, en: "Save transaction", vi: "Lưu giao dịch"), action: save)
                        .blockButton(prominent: true)

                    if existing != nil {
                        Button(L10n.text(lang, en: "Delete transaction", vi: "Xoá giao dịch"), role: .destructive) {
                            confirmingDelete = true
                        }
                        .blockButton(prominent: false, tint: .negative)
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(
                existing == nil
                    ? L10n.text(lang, en: "New transaction", vi: "Giao dịch mới")
                    : L10n.text(lang, en: "Edit transaction", vi: "Sửa giao dịch")
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ")) { dismiss() }
                }
            }
            .confirmationDialog(
                L10n.text(lang, en: "Delete this transaction?", vi: "Xoá giao dịch này?"),
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.text(lang, en: "Delete", vi: "Xoá"), role: .destructive) {
                    if let id = existing?.id { store.deleteTransaction(id: id) }
                    dismiss()
                }
            }
            .onAppear(perform: populate)
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    HorizonSingleDateCalendarView(
                        selectedDayKey: $dayKey,
                        language: lang,
                        highlightedDayKeys: store.transactionDayKeys
                    ) { _ in
                        showingDatePicker = false
                    }
                    .pageBackground()
                    .navigationTitle(L10n.text(lang, en: "Select date", vi: "Chọn ngày"))
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text(lang, en: "Done", vi: "Xong")) {
                                showingDatePicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
    }

    private var memberOptions: [HouseholdMember] {
        var list = store.knownMembers(settings: settings)
        let partner = settings.partnerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partner.isEmpty && !list.contains(where: { $0.name == partner }) {
            list.append(HouseholdMember(id: HouseholdMember.defaultPartnerID, name: partner))
        }
        return list
    }

    private func populate() {
        if let existing {
            name = existing.name
            let major = settings.currency.toMajor(existing.amountMinor)
            amountText = settings.currency.isZeroDecimal ? "\(Int64(major.rounded()))" : String(format: "%.2f", major)
            type = existing.type
            category = existing.category
            dayKey = existing.dayKey
            note = existing.note
            selectedMemberID = existing.memberID
            selectedMemberName = existing.memberName
        } else if let prefill {
            name = prefill.name
            amountText = settings.currency.isZeroDecimal ? "\(Int64(prefill.amountMajor.rounded()))" : String(format: "%.2f", prefill.amountMajor)
            type = prefill.type
            category = prefill.category
            dayKey = prefill.dayKey
            note = prefill.note
            selectedMemberID = settings.currentMember.id
            selectedMemberName = settings.currentMember.name
        } else {
            selectedMemberID = settings.currentMember.id
            selectedMemberName = settings.currentMember.name
            dayKey = store.selectedPeriod.defaultNewTransactionDayKey()
        }
    }

    private func save() {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            errorMessage = L10n.text(settings.language, en: "Please enter a name.", vi: "Vui lòng nhập tên giao dịch.")
            return
        }
        let normalized = amountText
            .replacingOccurrences(of: ",", with: settings.currency.isZeroDecimal ? "" : ".")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let major = Double(normalized), major > 0 else {
            errorMessage = L10n.text(settings.language, en: "Enter a valid amount greater than 0.", vi: "Vui lòng nhập số tiền lớn hơn 0.")
            return
        }

        let record = TransactionRecord(
            id: existing?.id ?? UUID().uuidString,
            name: cleanedName,
            amountMinor: settings.currency.toStorageMinor(major),
            type: type,
            category: category,
            dayKey: dayKey,
            createdAt: existing?.createdAt ?? Date(),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            source: existing?.source ?? sourceOverride ?? .manual,
            rawSourceText: existing?.rawSourceText ?? rawSourceText,
            memberID: selectedMemberID.isEmpty ? settings.currentMember.id : selectedMemberID,
            memberName: selectedMemberName.isEmpty ? settings.currentMember.name : selectedMemberName,
            needsReview: false,
            updatedAt: Date(),
            isDeleted: false
        )
        store.saveTransaction(record)
        store.ensureVisible(dayKey: record.dayKey)
        dismiss()
    }
}
