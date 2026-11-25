import SwiftUI
import TallyCore
#if os(iOS)
import UIKit
#endif

/// Tactile in-app calculator keypad docked at the bottom of the New / Edit Transaction sheet.
/// Matches Onsite's calm editorial aesthetic: elevated numeric keys, subtle operator keys,
/// long-press backspace to clear, and an ink capsule save action.
public struct AmountKeypadView: View {
    @Binding public var engine: AmountKeypadEngine
    public let currencyCode: String
    public let isZeroDecimal: Bool
    public let language: AppLanguage
    public let saveTitle: String
    public let isSaveEnabled: Bool
    public let onSave: () -> Void

    public var currency: CurrencyCode { CurrencyCode(rawValue: currencyCode) ?? .sgd }

    public init(
        engine: Binding<AmountKeypadEngine>,
        currency: CurrencyCode,
        language: AppLanguage,
        saveTitle: String,
        isSaveEnabled: Bool,
        onSave: @escaping () -> Void
    ) {
        self._engine = engine
        self.currencyCode = currency.rawValue
        self.isZeroDecimal = currency.isZeroDecimal
        self.language = language
        self.saveTitle = saveTitle
        self.isSaveEnabled = isSaveEnabled
        self.onSave = onSave
    }

    public init(
        engine: Binding<AmountKeypadEngine>,
        currencyCode: String,
        language: AppLanguage,
        saveTitle: String,
        isSaveEnabled: Bool,
        onSave: @escaping () -> Void
    ) {
        self._engine = engine
        let normalized = CurrencyCode.normalizeCode(currencyCode) ?? currencyCode.uppercased()
        self.currencyCode = normalized
        self.isZeroDecimal = CurrencyCode.isZeroDecimal(code: normalized)
        self.language = language
        self.saveTitle = saveTitle
        self.isSaveEnabled = isSaveEnabled
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Row 1: 1, 2, 3, Backspace (long press to clear)
            HStack(spacing: 8) {
                digitKey("1")
                digitKey("2")
                digitKey("3")
                backspaceKey
            }

            // Row 2: 4, 5, 6, +
            HStack(spacing: 8) {
                digitKey("4")
                digitKey("5")
                digitKey("6")
                operatorKey(.add)
            }

            // Row 3: 7, 8, 9, −
            HStack(spacing: 8) {
                digitKey("7")
                digitKey("8")
                digitKey("9")
                operatorKey(.subtract)
            }

            // Row 4: (. or 000), 0, ÷, ×
            HStack(spacing: 8) {
                if isZeroDecimal {
                    digitKey("000", compactFont: true)
                } else {
                    decimalKey
                }
                digitKey("0")
                operatorKey(.divide)
                operatorKey(.multiply)
            }

            // Primary Save bar (with quick `=` collapse button when an arithmetic expression is active)
            HStack(spacing: 8) {
                if engine.hasOperator {
                    Button {
                        haptic(.medium)
                        withAnimation(.snappy(duration: 0.16)) {
                            engine.commitEvaluation()
                        }
                    } label: {
                        Text("=")
                            .font(.custom("AvenirNext-DemiBold", size: 22))
                            .frame(width: 64, height: 48)
                            .foregroundStyle(Color.textPrimary)
                            .background(Color.softFill, in: Capsule())
                    }
                    .buttonStyle(KeypadButtonStyle())
                    .accessibilityLabel(L10n.text(language, en: "Calculate", vi: "Tính kết quả", zh: "计算结果"))
                }

                Button {
                    haptic(.medium)
                    onSave()
                } label: {
                    Text(saveTitle)
                }
                .blockButton(prominent: true)
                .disabled(!isSaveEnabled)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(Color.appBackground)
                .overlay(alignment: .top) {
                    Divider().overlay(Color.hairline)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Keys

    private func digitKey(_ digits: String, compactFont: Bool = false) -> some View {
        Button {
            haptic(.light)
            engine.tapDigit(digits)
        } label: {
            Text(digits)
                .font(.custom("AvenirNext-DemiBold", size: compactFont ? 18 : 22).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(KeypadButtonStyle())
    }

    private var decimalKey: some View {
        Button {
            haptic(.light)
            engine.tapDecimal()
        } label: {
            Text(".")
                .font(.custom("AvenirNext-DemiBold", size: 24))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(KeypadButtonStyle())
        .accessibilityLabel(L10n.text(language, en: "Decimal point", vi: "Dấu thập phân", zh: "小数点"))
    }

    private func operatorKey(_ op: KeypadOperator) -> some View {
        let isTrailing = engine.expression.last.map { String($0) == op.rawValue } ?? false
        return Button {
            haptic(.light)
            engine.tapOperator(op)
        } label: {
            Text(op.symbol)
                .font(.custom("AvenirNext-DemiBold", size: 22))
                .foregroundStyle(isTrailing ? Color.onInk : Color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isTrailing ? Color.ink : Color.softFill)
                )
        }
        .buttonStyle(KeypadButtonStyle())
    }

    private var backspaceKey: some View {
        Button {
            haptic(.light)
            engine.tapBackspace()
        } label: {
            CozyUIIcon(
                .backspace,
                size: 22,
                color: engine.isEmpty ? Color.textSecondary.opacity(0.45) : Color.accent
            )
            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.softFill)
                )
        }
        .buttonStyle(KeypadButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                haptic(.medium)
                engine.clear()
            }
        )
        .accessibilityLabel(L10n.text(language, en: "Delete digit. Hold to clear.", vi: "Xoá số. Nhấn giữ để xoá hết.", zh: "删除数字，长按清空。"))
    }

    // MARK: - Haptics

    private enum HapticWeight { case light, medium }

    private func haptic(_ weight: HapticWeight) {
        #if os(iOS)
        let style: UIImpactFeedbackGenerator.FeedbackStyle = (weight == .light) ? .light : .medium
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct KeypadKeyboardInputModifier: ViewModifier {
    @Binding var engine: AmountKeypadEngine
    let isEnabled: Bool
    let isSaveEnabled: Bool
    let onSave: () -> Void

    @FocusState private var isKeypadFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable(isEnabled)
            .focusEffectDisabled()
            .focused($isKeypadFocused)
            #if os(macOS)
            .onAppear {
                if isEnabled {
                    DispatchQueue.main.async {
                        if isEnabled { isKeypadFocused = true }
                    }
                }
            }
            #endif
            .onChange(of: isEnabled) { _, enabled in
                #if os(macOS)
                if enabled {
                    isKeypadFocused = true
                }
                #endif
            }
            .onKeyPress { press in
                guard isEnabled else { return .ignored }
                if press.key == .escape { return .ignored }
                if press.key == .delete {
                    engine.tapBackspace()
                    return .handled
                }
                if press.key == .return {
                    if engine.hasOperator {
                        withAnimation(.snappy(duration: 0.16)) {
                            engine.commitEvaluation()
                        }
                        return .handled
                    }
                    if isSaveEnabled {
                        onSave()
                        return .handled
                    }
                    return .ignored
                }
                if engine.handleKeyCharacter(press.characters) {
                    return .handled
                }
                return .ignored
            }
    }
}

extension View {
    /// Captures hardware keyboard digits, operators, Backspace, and Return for `AmountKeypadEngine`
    /// whenever no text field is currently active.
    public func keypadKeyboardInput(
        engine: Binding<AmountKeypadEngine>,
        isEnabled: Bool,
        isSaveEnabled: Bool = true,
        onSave: @escaping () -> Void
    ) -> some View {
        modifier(KeypadKeyboardInputModifier(
            engine: engine,
            isEnabled: isEnabled,
            isSaveEnabled: isSaveEnabled,
            onSave: onSave
        ))
    }
}
