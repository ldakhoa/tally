import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

enum DictationRanking {
    private static let vietnameseLetters = CharacterSet(charactersIn: "ăđơưảãạấầẩẫậắằẳẵặẻẽẹếềểễệỉĩịỏọốồổỗộớờởỡợủũụứừửữựỷỹỵ")

    static func score(
        text: String,
        language: DictationLanguage,
        confidences: [Double],
        isFinal: Bool
    ) -> Double {
        let hasConfidence = confidences.contains { $0 > 0 }
        let confidence = !confidences.isEmpty && (isFinal || hasConfidence)
            ? confidences.reduce(0, +) / Double(confidences.count)
            : 0.5
        let normalized = text.precomposedStringWithCanonicalMapping.lowercased()
        let hasHan = normalized.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        let hasVietnameseLetters = normalized.unicodeScalars.contains { vietnameseLetters.contains($0) }

        if hasHan && language != .chinese { return confidence - 0.35 }
        if !hasHan && hasVietnameseLetters && language != .vietnamese { return confidence - 0.35 }

        let letterCount = normalized.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        if language == .chinese && !hasHan && letterCount >= 4 { return confidence - 0.2 }

        let scriptEvidence = hasHan || hasVietnameseLetters ? 0.1 : 0.0
        guard letterCount >= (hasHan ? 4 : 8) else { return confidence + scriptEvidence }

        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let probability: Double
        switch language {
        case .english: probability = hypotheses[.english] ?? 0
        case .vietnamese: probability = hypotheses[.vietnamese] ?? 0
        case .chinese: probability = max(hypotheses[.simplifiedChinese] ?? 0, hypotheses[.traditionalChinese] ?? 0)
        }
        return confidence + max(scriptEvidence, probability * 0.15)
        #else
        return confidence + scriptEvidence
        #endif
    }

    static func winner(
        scores: [DictationLanguage: Double],
        preferred: DictationLanguage,
        current: DictationLanguage?
    ) -> DictationLanguage? {
        let order = [preferred] + DictationLanguage.allCases.filter { $0 != preferred }
        guard let best = order.filter({ scores[$0] != nil }).max(by: {
            scores[$0, default: 0] < scores[$1, default: 0]
        }) else { return nil }
        if let current, let currentScore = scores[current], scores[best, default: 0] - currentScore < 0.08 {
            return current
        }
        return best
    }
}
