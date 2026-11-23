import Foundation

public enum KeypadOperator: String, CaseIterable, Hashable, Sendable {
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"

    public var symbol: String { rawValue }
}

/// Pure Foundation calculator & numeric entry engine for Tally's in-app amount keypad.
/// Supports decimal currencies (SGD, USD, etc.) and zero-decimal currencies (VND with `000`),
/// plus inline arithmetic (`+`, `−`, `×`, `÷`) with standard operator precedence.
public struct AmountKeypadEngine: Equatable, Hashable, Sendable {
    public private(set) var expression: String
    public var maxFractionDigits: Int

    public init(initialAmountMajor: Double? = nil, maxFractionDigits: Int = 2) {
        self.maxFractionDigits = max(0, maxFractionDigits)
        if let amount = initialAmountMajor, amount > 0 {
            self.expression = Self.formatRawValue(amount, maxFractionDigits: max(0, maxFractionDigits))
        } else {
            self.expression = ""
        }
    }

    public var isEmpty: Bool { expression.isEmpty }

    public var hasOperator: Bool {
        expression.contains { Self.isOperator($0) }
    }

    /// The live numeric result of the expression (ignoring any dangling trailing operator).
    public var evaluatedValue: Double? {
        evaluateExpression(expression)
    }

    /// Pretty-printed expression with spaces around operators for the subtle formula subtitle.
    public var formattedExpression: String {
        var out = ""
        for ch in expression {
            if Self.isOperator(ch) {
                out.append(" \(ch) ")
            } else {
                out.append(ch)
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Formatted string for the hero amount display (without currency symbol).
    /// Preserves typed decimal point / trailing fraction zeros when entering a single number,
    /// and displays the live calculated result when an arithmetic operator is active.
    public func formattedDisplayNumber(currency: CurrencyCode) -> String {
        if expression.isEmpty {
            return "0"
        }

        let groupSep = currency == .vnd ? "." : ","
        let decSep = currency == .vnd ? "," : "."

        if !hasOperator {
            return Self.formatTypedOperand(expression, groupSeparator: groupSep, decimalSeparator: decSep)
        }

        guard let value = evaluatedValue, value.isFinite else {
            return "0"
        }
        let clamped = max(0, value)
        let raw = Self.formatRawValue(clamped, maxFractionDigits: maxFractionDigits)
        return Self.formatTypedOperand(raw, groupSeparator: groupSep, decimalSeparator: decSep)
    }

    // MARK: - Input Actions

    public mutating func tapDigit(_ digits: String) {
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return }

        let current = currentOperand()
        if let dotIndex = current.firstIndex(of: ".") {
            let fractionCount = current.distance(from: current.index(after: dotIndex), to: current.endIndex)
            let remaining = max(0, maxFractionDigits - fractionCount)
            guard remaining > 0 else { return }
            expression.append(contentsOf: digits.prefix(remaining))
            return
        }

        // Prevent overflowing reasonable money amounts (up to 11 integer digits, e.g. 99 billion VND).
        let intLimit = maxFractionDigits == 0 ? 11 : 8
        if current == "0" {
            if digits.allSatisfy({ $0 == "0" }) { return }
            expression.removeLast()
            let trimmed = String(digits.drop(while: { $0 == "0" }))
            expression.append(trimmed.isEmpty ? "0" : String(trimmed.prefix(intLimit)))
            return
        }

        if current.isEmpty && digits.allSatisfy({ $0 == "0" }) {
            expression.append("0")
            return
        }

        let remaining = max(0, intLimit - current.count)
        guard remaining > 0 else { return }
        expression.append(contentsOf: digits.prefix(remaining))
    }

    public mutating func tapDecimal() {
        guard maxFractionDigits > 0 else { return }
        let current = currentOperand()
        guard !current.contains(".") else { return }
        if current.isEmpty {
            expression.append("0.")
        } else {
            expression.append(".")
        }
    }

    public mutating func tapOperator(_ op: KeypadOperator) {
        guard !expression.isEmpty else { return }
        if let last = expression.last, Self.isOperator(last) {
            expression.removeLast()
        } else if expression.last == "." {
            expression.removeLast()
        }
        guard !expression.isEmpty else { return }
        expression.append(op.rawValue)
    }

    public mutating func tapBackspace() {
        guard !expression.isEmpty else { return }
        expression.removeLast()
    }

    public mutating func clear() {
        expression = ""
    }

    /// Evaluates the expression and replaces it with the simplified result.
    public mutating func commitEvaluation() {
        guard let value = evaluatedValue, value.isFinite else { return }
        let clamped = max(0, value)
        if clamped == 0 {
            expression = ""
        } else {
            expression = Self.formatRawValue(clamped, maxFractionDigits: maxFractionDigits)
        }
    }

    // MARK: - Private Helpers

    private func currentOperand() -> String {
        guard let lastOp = expression.lastIndex(where: { Self.isOperator($0) }) else {
            return expression
        }
        return String(expression[expression.index(after: lastOp)...])
    }

    private static func isOperator(_ ch: Character) -> Bool {
        ch == "+" || ch == "−" || ch == "-" || ch == "×" || ch == "*" || ch == "÷" || ch == "/"
    }

    private func evaluateExpression(_ expr: String) -> Double? {
        var cleaned = expr
        while let last = cleaned.last, Self.isOperator(last) || last == "." {
            cleaned.removeLast()
        }
        guard !cleaned.isEmpty else { return nil }

        // Tokenize into numbers and operators.
        var numbers: [Double] = []
        var operators: [Character] = []
        var buffer = ""

        for ch in cleaned {
            if Self.isOperator(ch) {
                guard let num = Double(buffer) else { return nil }
                numbers.append(num)
                operators.append(ch)
                buffer = ""
            } else {
                buffer.append(ch)
            }
        }
        if !buffer.isEmpty {
            guard let num = Double(buffer) else { return nil }
            numbers.append(num)
        }

        guard !numbers.isEmpty, numbers.count == operators.count + 1 else {
            return numbers.first
        }

        // First pass: resolve × and ÷ left-to-right.
        var reducedNumbers: [Double] = [numbers[0]]
        var reducedOps: [Character] = []

        for idx in operators.indices {
            let op = operators[idx]
            let rhs = numbers[idx + 1]
            if op == "×" || op == "*" {
                reducedNumbers[reducedNumbers.count - 1] *= rhs
            } else if op == "÷" || op == "/" {
                guard rhs != 0 else { return nil }
                reducedNumbers[reducedNumbers.count - 1] /= rhs
            } else {
                reducedOps.append(op)
                reducedNumbers.append(rhs)
            }
        }

        // Second pass: resolve + and − left-to-right.
        var total = reducedNumbers[0]
        for idx in reducedOps.indices {
            let op = reducedOps[idx]
            let rhs = reducedNumbers[idx + 1]
            if op == "+" {
                total += rhs
            } else {
                total -= rhs
            }
        }

        return total
    }

    private static func formatRawValue(_ value: Double, maxFractionDigits: Int) -> String {
        if maxFractionDigits == 0 {
            return "\(Int64(value.rounded()))"
        }
        let factor = pow(10.0, Double(maxFractionDigits))
        let rounded = (value * factor).rounded() / factor
        var text = String(format: "%.\(maxFractionDigits)f", rounded)
        if text.contains(".") {
            while text.last == "0" { text.removeLast() }
            if text.last == "." { text.removeLast() }
        }
        return text
    }

    private static func formatTypedOperand(
        _ raw: String,
        groupSeparator: String,
        decimalSeparator: String
    ) -> String {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        let intPart = String(parts.first ?? "0")
        let grouped = insertGroupSeparators(intPart, separator: groupSeparator)
        if parts.count > 1 {
            return "\(grouped)\(decimalSeparator)\(parts[1])"
        }
        return grouped
    }

    private static func insertGroupSeparators(_ digits: String, separator: String) -> String {
        guard digits.count > 3 else { return digits }
        var result = ""
        let count = digits.count
        for (index, ch) in digits.enumerated() {
            if index > 0 && (count - index) % 3 == 0 {
                result.append(separator)
            }
            result.append(ch)
        }
        return result
    }
}
