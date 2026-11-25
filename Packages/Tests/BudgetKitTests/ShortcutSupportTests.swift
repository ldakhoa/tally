import BudgetKit
import TallyCore
import XCTest

final class ShortcutSupportTests: XCTestCase {
    func testApplePayFormattedAmountParsing() {
        let sgd = ApplePayInputParser.parseFormattedAmount("S$18.50", defaultCurrency: .sgd)
        XCTAssertEqual(sgd?.amountMajor, 18.50)
        XCTAssertEqual(sgd?.currencyCode, "SGD")

        let dollarSGD = ApplePayInputParser.parseFormattedAmount("$10.00", defaultCurrency: .sgd)
        XCTAssertEqual(dollarSGD?.amountMajor, 10.0)
        XCTAssertEqual(dollarSGD?.currencyCode, "SGD")

        let dollarVND = ApplePayInputParser.parseFormattedAmount("$10.00", defaultCurrency: .vnd)
        XCTAssertEqual(dollarVND?.amountMajor, 10.0)
        XCTAssertEqual(dollarVND?.currencyCode, "SGD")

        let dollarUSD = ApplePayInputParser.parseFormattedAmount("$10.00", defaultCurrency: .usd)
        XCTAssertEqual(dollarUSD?.amountMajor, 10.0)
        XCTAssertEqual(dollarUSD?.currencyCode, "USD")

        let suffixDollar = ApplePayInputParser.parseFormattedAmount("10.00 $", defaultCurrency: .usd)
        XCTAssertEqual(suffixDollar?.amountMajor, 10.0)
        XCTAssertEqual(suffixDollar?.currencyCode, "USD")

        let nbspSGD = ApplePayInputParser.parseFormattedAmount("SGD\u{00A0}18.50", defaultCurrency: .usd)
        XCTAssertEqual(nbspSGD?.amountMajor, 18.50)
        XCTAssertEqual(nbspSGD?.currencyCode, "SGD")

        let hkd = ApplePayInputParser.parseFormattedAmount("HK$83.75", defaultCurrency: .sgd)
        XCTAssertEqual(hkd?.amountMajor, 83.75)
        XCTAssertEqual(hkd?.currencyCode, "HKD")

        let eurPrefixComma = ApplePayInputParser.parseFormattedAmount("€12,50", defaultCurrency: .sgd)
        XCTAssertEqual(eurPrefixComma?.amountMajor, 12.50)
        XCTAssertEqual(eurPrefixComma?.currencyCode, "EUR")

        let eurSuffixComma = ApplePayInputParser.parseFormattedAmount("12,50 €", defaultCurrency: .sgd)
        XCTAssertEqual(eurSuffixComma?.amountMajor, 12.50)
        XCTAssertEqual(eurSuffixComma?.currencyCode, "EUR")

        let eurGrouped = ApplePayInputParser.parseFormattedAmount("1.234,56 €", defaultCurrency: .sgd)
        XCTAssertEqual(eurGrouped?.amountMajor, 1234.56)
        XCTAssertEqual(eurGrouped?.currencyCode, "EUR")

        let usdGrouped = ApplePayInputParser.parseFormattedAmount("1,234.56 USD", defaultCurrency: .sgd)
        XCTAssertEqual(usdGrouped?.amountMajor, 1234.56)
        XCTAssertEqual(usdGrouped?.currencyCode, "USD")

        let vndSuffixSymbol = ApplePayInputParser.parseFormattedAmount("125.000 ₫", defaultCurrency: .sgd)
        XCTAssertEqual(vndSuffixSymbol?.amountMajor, 125_000)
        XCTAssertEqual(vndSuffixSymbol?.currencyCode, "VND")

        let vndPrefixSymbol = ApplePayInputParser.parseFormattedAmount("₫125.000", defaultCurrency: .sgd)
        XCTAssertEqual(vndPrefixSymbol?.amountMajor, 125_000)
        XCTAssertEqual(vndPrefixSymbol?.currencyCode, "VND")

        let vndCode = ApplePayInputParser.parseFormattedAmount("125,000 VND", defaultCurrency: .sgd)
        XCTAssertEqual(vndCode?.amountMajor, 125_000)
        XCTAssertEqual(vndCode?.currencyCode, "VND")

        let jpy = ApplePayInputParser.parseFormattedAmount("¥1,200", defaultCurrency: .sgd)
        XCTAssertEqual(jpy?.amountMajor, 1_200)
        XCTAssertEqual(jpy?.currencyCode, "JPY")

        let cny = ApplePayInputParser.parseFormattedAmount("¥1,200", defaultCurrency: .cny)
        XCTAssertEqual(cny?.amountMajor, 1_200)
        XCTAssertEqual(cny?.currencyCode, "CNY")

        let krw = ApplePayInputParser.parseFormattedAmount("₩15,000", defaultCurrency: .sgd)
        XCTAssertEqual(krw?.amountMajor, 15_000)
        XCTAssertEqual(krw?.currencyCode, "KRW")

        let myr = ApplePayInputParser.parseFormattedAmount("RM 15.90", defaultCurrency: .sgd)
        XCTAssertEqual(myr?.amountMajor, 15.90)
        XCTAssertEqual(myr?.currencyCode, "MYR")

        let aedPrefix = ApplePayInputParser.parseFormattedAmount("AED 120.50", defaultCurrency: .sgd)
        XCTAssertEqual(aedPrefix?.amountMajor, 120.50)
        XCTAssertEqual(aedPrefix?.currencyCode, "AED")

        let aedSuffix = ApplePayInputParser.parseFormattedAmount("120.50 AED", defaultCurrency: .sgd)
        XCTAssertEqual(aedSuffix?.amountMajor, 120.50)
        XCTAssertEqual(aedSuffix?.currencyCode, "AED")

        let negative = ApplePayInputParser.parseFormattedAmount("-S$18.50", defaultCurrency: .sgd)
        XCTAssertEqual(negative?.amountMajor, 18.50)
        XCTAssertEqual(negative?.currencyCode, "SGD")

        let plain = ApplePayInputParser.parseFormattedAmount("18.50", defaultCurrency: .sgd)
        XCTAssertEqual(plain?.amountMajor, 18.50)
        XCTAssertEqual(plain?.currencyCode, "SGD")

        let overridden = ApplePayInputParser.parseFormattedAmount(
            "S$18.50",
            explicitCurrency: "USD",
            defaultCurrency: .sgd
        )
        XCTAssertEqual(overridden?.amountMajor, 18.50)
        XCTAssertEqual(overridden?.currencyCode, "USD")

        XCTAssertNil(ApplePayInputParser.parseFormattedAmount("", defaultCurrency: .sgd))
        XCTAssertNil(ApplePayInputParser.parseFormattedAmount("S$0.00", defaultCurrency: .sgd))
        XCTAssertNil(ApplePayInputParser.parseFormattedAmount("abc", defaultCurrency: .sgd))
    }

    func testApplePayMerchantAndCardFallbacks() {
        let withMerchantAndCard = ApplePayInputParser.parse(
            amountText: "S$6.50",
            merchant: "  Ya Kun Kaya Toast ",
            cardName: "DBS Live Fresh",
            defaultCurrency: .sgd
        )
        XCTAssertEqual(withMerchantAndCard?.merchantName, "Ya Kun Kaya Toast")
        XCTAssertEqual(withMerchantAndCard?.cardName, "DBS Live Fresh")
        XCTAssertEqual(withMerchantAndCard?.note, "Apple Pay · DBS Live Fresh")

        let cardFallback = ApplePayInputParser.parse(
            amountText: "S$6.50",
            merchant: "   ",
            cardName: "DBS Live Fresh",
            defaultCurrency: .sgd
        )
        XCTAssertEqual(cardFallback?.merchantName, "DBS Live Fresh")
        XCTAssertEqual(cardFallback?.cardName, "DBS Live Fresh")
        XCTAssertEqual(cardFallback?.note, "Apple Pay")

        let bothBlank = ApplePayInputParser.parse(
            amountText: "S$6.50",
            merchant: nil,
            cardName: "",
            defaultCurrency: .sgd
        )
        XCTAssertEqual(bothBlank?.merchantName, "Apple Pay")
        XCTAssertNil(bothBlank?.cardName)
        XCTAssertEqual(bothBlank?.note, "Apple Pay")
    }

    func testShortcutICloudLinkValidationAndNormalization() {
        let validFull = ShortcutICloudLink.normalizedURL(from: "https://www.icloud.com/shortcuts/0123456789abcdef0123456789abcdef")
        XCTAssertEqual(validFull?.absoluteString, "https://www.icloud.com/shortcuts/0123456789abcdef0123456789abcdef")

        let validBare = ShortcutICloudLink.normalizedURL(from: "  icloud.com/shortcuts/abcd_1234-efgh/ \n")
        XCTAssertEqual(validBare?.absoluteString, "https://www.icloud.com/shortcuts/abcd_1234-efgh")

        let validHTTP = ShortcutICloudLink.normalizedURL(from: "http://icloud.com/Shortcuts/ABCDEF123456")
        XCTAssertEqual(validHTTP?.absoluteString, "https://www.icloud.com/shortcuts/ABCDEF123456")

        XCTAssertNil(ShortcutICloudLink.normalizedURL(from: ""))
        XCTAssertNil(ShortcutICloudLink.normalizedURL(from: "https://evil.com/shortcuts/0123456789abcdef"))
        XCTAssertNil(ShortcutICloudLink.normalizedURL(from: "https://icloud.com.evil.com/shortcuts/0123456789abcdef"))
        XCTAssertNil(ShortcutICloudLink.normalizedURL(from: "https://www.icloud.com/shortcuts/short"))
        XCTAssertNil(ShortcutICloudLink.normalizedURL(from: "https://www.icloud.com/shortcuts/0123456789abcdef/extra"))
        XCTAssertNil(ShortcutICloudLink.normalizedURL(from: "https://www.icloud.com/notes/0123456789abcdef"))
    }

    func testLocalParserRecognizesDongSymbolSuffix() {
        let draft = LocalTransactionParser.parse("Highlands Coffee 125.000 ₫", defaultCurrency: .sgd)
        XCTAssertEqual(draft?.amountMajor, 125_000)
        XCTAssertEqual(draft?.currencyCode, "VND")
        XCTAssertEqual(draft?.category, .food)
    }
}
