import XCTest
@testable import GaussEngine

final class TokenizerTests: XCTestCase {

    private var tokenizer: Tokenizer!

    override func setUp() {
        super.setUp()
        do {
            let definitions = try DefinitionLoader()
            tokenizer = Tokenizer(definitions: definitions)
        } catch {
            XCTFail("Failed to create Tokenizer: \(error)")
        }
    }

    // MARK: - Helper

    private func tokens(_ input: String) -> [Token] {
        tokenizer.tokenize(input)
    }

    // MARK: - Empty / Whitespace

    func testEmptyString() {
        XCTAssertEqual(tokens(""), [])
    }

    func testWhitespaceOnly() {
        XCTAssertEqual(tokens("   "), [])
    }

    // MARK: - Basic Arithmetic

    func testAddition() {
        XCTAssertEqual(tokens("5 + 3"), [.number(5), .op(.add), .number(3)])
    }

    func testSubtraction() {
        XCTAssertEqual(tokens("10 - 2.5"), [.number(10), .op(.subtract), .number(2.5)])
    }

    func testMultiplication() {
        XCTAssertEqual(tokens("3 * 4"), [.number(3), .op(.multiply), .number(4)])
    }

    func testDivision() {
        XCTAssertEqual(tokens("10 / 3"), [.number(10), .op(.divide), .number(3)])
    }

    func testPower() {
        XCTAssertEqual(tokens("2 ^ 10"), [.number(2), .op(.power), .number(10)])
    }

    func testParentheses() {
        XCTAssertEqual(
            tokens("(5 + 3) * 2"),
            [.leftParen, .number(5), .op(.add), .number(3), .rightParen, .op(.multiply), .number(2)]
        )
    }

    // MARK: - Currency

    func testDollarInteger() {
        XCTAssertEqual(tokens("$8"), [.currency(8, "USD")])
    }

    func testDollarDecimal() {
        XCTAssertEqual(tokens("$8.50"), [.currency(8.5, "USD")])
    }

    func testEuro() {
        XCTAssertEqual(tokens("€20"), [.currency(20, "EUR")])
    }

    func testPound() {
        XCTAssertEqual(tokens("£15.99"), [.currency(15.99, "GBP")])
    }

    func testYen() {
        XCTAssertEqual(tokens("¥1000"), [.currency(1000, "JPY")])
    }

    // MARK: - Natural Language Operators

    func testKeywordTimes() {
        XCTAssertEqual(tokens("$6 times 5"), [.currency(6, "USD"), .keyword(.times), .number(5)])
    }

    func testKeywordPlus() {
        XCTAssertEqual(tokens("10 plus 5"), [.number(10), .keyword(.plus), .number(5)])
    }

    func testKeywordMinus() {
        XCTAssertEqual(tokens("20 minus 3"), [.number(20), .keyword(.minus), .number(3)])
    }

    // MARK: - Percentage

    func testPercentageInteger() {
        XCTAssertEqual(tokens("20%"), [.percentage(20)])
    }

    func testPercentageDecimal() {
        XCTAssertEqual(tokens("8.5%"), [.percentage(8.5)])
    }

    // MARK: - Unit Expressions with Keywords

    func testInchesInCm() {
        XCTAssertEqual(
            tokens("5 inches in cm"),
            [.number(5), .identifier("inches"), .keyword(.in), .identifier("cm")]
        )
    }

    func testDollarInEUR() {
        XCTAssertEqual(
            tokens("$20 in EUR"),
            [.currency(20, "USD"), .keyword(.in), .identifier("EUR")]
        )
    }

    func testCelsiusToFahrenheit() {
        XCTAssertEqual(
            tokens("100 celsius to fahrenheit"),
            [.number(100), .identifier("celsius"), .keyword(.to), .identifier("fahrenheit")]
        )
    }

    func testMultiWordCurrencyNames() {
        XCTAssertEqual(
            tokens("1 Brazilian real in US dollar"),
            [.number(1), .identifier("Brazilian real"), .keyword(.in), .identifier("US dollar")]
        )
    }

    func testMultiWordCurrencyCodesStillSplitAsIdentifiers() {
        XCTAssertEqual(
            tokens("1 BRL in USD"),
            [.number(1), .identifier("BRL"), .keyword(.in), .identifier("USD")]
        )
    }

    // MARK: - Hex Numbers

    func testHexFF() {
        XCTAssertEqual(tokens("0xFF"), [.hexNumber(255)])
    }

    func testHex1A2B() {
        XCTAssertEqual(tokens("0x1A2B"), [.hexNumber(6699)])
    }

    // MARK: - Binary Numbers

    func testBinary1010() {
        XCTAssertEqual(tokens("0b1010"), [.binaryNumber(10)])
    }

    func testBinary11111111() {
        XCTAssertEqual(tokens("0b11111111"), [.binaryNumber(255)])
    }

    // MARK: - Octal Numbers

    func testOctal17() {
        XCTAssertEqual(tokens("0o17"), [.octalNumber(15)])
    }

    // MARK: - Hex Colors

    func testHexColorUppercase() {
        XCTAssertEqual(tokens("#FF5733"), [.hexColor("FF5733")])
    }

    func testHexColorLowercase() {
        XCTAssertEqual(tokens("#ff5733"), [.hexColor("ff5733")])
    }

    // MARK: - Strings

    func testString() {
        XCTAssertEqual(tokens("\"hello world\""), [.string("hello world")])
    }

    // MARK: - Headers

    func testHeader() {
        XCTAssertEqual(tokens("# My Calculations"), [.header("My Calculations")])
    }

    // MARK: - Comments

    func testComment() {
        XCTAssertEqual(tokens("// this is a note"), [.comment("this is a note")])
    }

    // MARK: - Labels

    func testLabelWithCurrency() {
        XCTAssertEqual(tokens("Price: $10"), [.label("Price"), .currency(10, "USD")])
    }

    func testLabelWithPercentage() {
        XCTAssertEqual(tokens("Tax rate: 8.5%"), [.label("Tax rate"), .percentage(8.5)])
    }

    // MARK: - Assignment

    func testAssignment() {
        XCTAssertEqual(tokens("price = $8"), [.identifier("price"), .assignment, .currency(8, "USD")])
    }

    func testCompoundAssignment() {
        XCTAssertEqual(tokens("total += $20"), [.identifier("total"), .compoundAssignment(.add), .currency(20, "USD")])
    }

    // MARK: - Scale Shorthand

    func testScaleK() {
        XCTAssertEqual(tokens("5k"), [.number(5000)])
    }

    func testScaleM() {
        XCTAssertEqual(tokens("2.5M"), [.number(2_500_000)])
    }

    func testScaleBillion() {
        XCTAssertEqual(tokens("1.2billion"), [.number(1_200_000_000)])
    }

    // MARK: - Variables and Identifiers

    func testIdentifierPrice() {
        XCTAssertEqual(tokens("price"), [.identifier("price")])
    }

    func testIdentifierSqrt() {
        XCTAssertEqual(tokens("sqrt"), [.identifier("sqrt")])
    }

    func testIdentifierSum() {
        XCTAssertEqual(tokens("sum"), [.identifier("sum")])
    }

    // MARK: - Complex Expressions

    func testPriceAssignmentWithCurrencyAndKeyword() {
        XCTAssertEqual(
            tokens("price = $8 times 5"),
            [.identifier("price"), .assignment, .currency(8, "USD"), .keyword(.times), .number(5)]
        )
    }

    func testPercentOf() {
        XCTAssertEqual(
            tokens("20% of $150"),
            [.percentage(20), .keyword(.of), .currency(150, "USD")]
        )
    }

    func testPercentOn() {
        XCTAssertEqual(
            tokens("15% on $20"),
            [.percentage(15), .keyword(.on), .currency(20, "USD")]
        )
    }

    func testPercentOff() {
        XCTAssertEqual(
            tokens("20% off $50"),
            [.percentage(20), .keyword(.off), .currency(50, "USD")]
        )
    }

    // MARK: - RGB Color

    func testRgbColor() {
        XCTAssertEqual(tokens("rgb(255, 87, 51)"), [.rgbColor(255, 87, 51)])
    }
}
