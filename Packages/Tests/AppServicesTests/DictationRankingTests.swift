import XCTest
@testable import AppServices

final class DictationRankingTests: XCTestCase {
    func testShortCurrencyAmountUsesAppLanguageOnlyAsTieBreaker() {
        let scores = Dictionary(uniqueKeysWithValues: DictationLanguage.allCases.map { language in
            (language, DictationRanking.score(text: "$50", language: language, confidences: [0], isFinal: false))
        })

        XCTAssertEqual(DictationRanking.winner(scores: scores, preferred: .vietnamese, current: nil), .vietnamese)
        XCTAssertEqual(DictationRanking.winner(scores: scores, preferred: .english, current: .chinese), .chinese)
    }

    func testShortLoanwordDoesNotCountAsVietnamese() {
        let english = DictationRanking.score(text: "café", language: .english, confidences: [0.8], isFinal: true)
        let vietnamese = DictationRanking.score(text: "café", language: .vietnamese, confidences: [0.8], isFinal: true)

        XCTAssertEqual(english, vietnamese)
    }

    func testVietnameseDiacriticsWorkWithDecomposedText() {
        let text = "đi chợ".decomposedStringWithCanonicalMapping
        let vietnamese = DictationRanking.score(text: text, language: .vietnamese, confidences: [0], isFinal: false)
        let english = DictationRanking.score(text: text, language: .english, confidences: [0], isFinal: false)

        XCTAssertGreaterThan(vietnamese, english)
    }

    func testChineseCharactersCannotOverruleStrongerSpeechConfidence() {
        let chinese = DictationRanking.score(text: "午饭", language: .chinese, confidences: [0], isFinal: false)
        let vietnamese = DictationRanking.score(text: "ăn trưa", language: .vietnamese, confidences: [0.85], isFinal: true)

        XCTAssertEqual(DictationRanking.winner(
            scores: [.vietnamese: vietnamese, .chinese: chinese], preferred: .chinese, current: .chinese
        ), .vietnamese)
    }

    func testFinalConfidenceDoesNotDiscardZeroConfidenceSegments() {
        let score = DictationRanking.score(text: "Grab", language: .english, confidences: [0.8, 0], isFinal: true)

        XCTAssertEqual(score, 0.4, accuracy: 0.001)
    }

    func testSmallScoreChangesDoNotSwitchTheCurrentLanguage() {
        XCTAssertEqual(DictationRanking.winner(
            scores: [.vietnamese: 0.65, .english: 0.7], preferred: .english, current: .vietnamese
        ), .vietnamese)
        XCTAssertEqual(DictationRanking.winner(
            scores: [.english: 0.7], preferred: .vietnamese, current: .vietnamese
        ), .english)
    }
}
