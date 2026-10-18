import XCTest
@testable import GaussEngine

final class ArithmeticTests: XCTestCase {
    var definitions: DefinitionLoader!
    var tokenizer: Tokenizer!
    var matcher: Matcher!
    var evaluator: Evaluator!
    var context: Context!

    override func setUp() {
        definitions = try! DefinitionLoader()
        tokenizer = Tokenizer(definitions: definitions)
        matcher = Matcher(definitions: definitions)
        evaluator = Evaluator(definitions: definitions)
        context = Context()
    }

    /// End-to-end helper: tokenize -> match -> evaluate.
    func eval(_ input: String, line: Int = 0) -> Value {
        let tokens = tokenizer.tokenize(input)
        guard let expr = matcher.match(tokens) else { return .undefined }
        context.currentLineIndex = line
        let result = evaluator.evaluate(expr, context: context)
        context.lineResults[line] = result
        return result
    }

    // MARK: - Basic Arithmetic

    func testAddition() {
        XCTAssertEqual(eval("5 + 3"), .number(8))
    }

    func testSubtraction() {
        XCTAssertEqual(eval("10 - 2.5"), .number(7.5))
    }

    func testMultiplication() {
        XCTAssertEqual(eval("3 * 4"), .number(12))
    }

    func testDivision() {
        XCTAssertEqual(eval("10 / 4"), .number(2.5))
    }

    func testPower() {
        XCTAssertEqual(eval("2 ^ 10"), .number(1024))
    }

    func testModulo() {
        XCTAssertEqual(eval("10 mod 3"), .number(1))
    }

    func testPrecedence() {
        XCTAssertEqual(eval("2 + 3 * 4"), .number(14))
    }

    func testParentheses() {
        XCTAssertEqual(eval("(2 + 3) * 4"), .number(20))
    }

    func testNaturalLanguage() {
        XCTAssertEqual(eval("$6 times 5"), .currency(30, "USD"))
    }

    // MARK: - Division by Zero

    func testDivisionByZero() {
        XCTAssertEqual(eval("5 / 0"), .infinity(false))
    }

    func testNegativeDivisionByZero() {
        XCTAssertEqual(eval("-5 / 0"), .infinity(true))
    }

    // MARK: - Unary Minus

    func testUnaryMinus() {
        XCTAssertEqual(eval("-5"), .number(-5))
    }

    // MARK: - Currency Arithmetic

    func testCurrencyAdd() {
        XCTAssertEqual(eval("$10 + $5"), .currency(15, "USD"))
    }

    func testCurrencyMultiply() {
        XCTAssertEqual(eval("$8 times 5"), .currency(40, "USD"))
    }

    // MARK: - Percentages

    func testPercentOf() {
        XCTAssertEqual(eval("20% of $150"), .currency(30, "USD"))
    }

    func testPercentOn() {
        XCTAssertEqual(eval("15% on $20"), .currency(23, "USD"))
    }

    func testPercentOff() {
        XCTAssertEqual(eval("20% off $50"), .currency(40, "USD"))
    }

    // MARK: - Variables

    func testVariableAssignment() {
        let result = eval("price = $8 times 5", line: 0)
        XCTAssertEqual(result, .currency(40, "USD"))
        XCTAssertEqual(context.getVariable("price"), .currency(40, "USD"))
    }

    func testVariableReference() {
        _ = eval("price = $40", line: 0)
        XCTAssertEqual(eval("price - $5", line: 1), .currency(35, "USD"))
    }

    func testUndefinedVariable() {
        XCTAssertEqual(eval("unknown * 2"), .undefined)
    }

    // MARK: - Special Tokens

    func testPrev() {
        _ = eval("10", line: 0)
        XCTAssertEqual(eval("prev + 5", line: 1), .number(15))
    }

    func testSum() {
        _ = eval("10", line: 0)
        _ = eval("20", line: 1)
        _ = eval("30", line: 2)
        XCTAssertEqual(eval("sum", line: 3), .number(60))
    }

    func testAvg() {
        _ = eval("10", line: 0)
        _ = eval("20", line: 1)
        XCTAssertEqual(eval("avg", line: 2), .number(15))
    }

    // MARK: - Unit Conversion

    func testInchesToCm() {
        let result = eval("5 inches in cm")
        if case .unit(let val, _, let cat) = result {
            XCTAssertEqual(val, 12.7, accuracy: 0.01)
            XCTAssertEqual(cat, "length")
        } else {
            XCTFail("Expected unit result, got \(result)")
        }
    }

    func testCelsiusToFahrenheit() {
        let result = eval("100 celsius in fahrenheit")
        if case .unit(let val, _, _) = result {
            XCTAssertEqual(val, 212, accuracy: 0.01)
        } else {
            XCTFail("Expected unit result, got \(result)")
        }
    }

    func testMBtoKB() {
        let result = eval("3 MB in KB")
        if case .unit(let val, _, _) = result {
            XCTAssertEqual(val, 3000, accuracy: 0.01)
        } else {
            XCTFail("Expected unit result, got \(result)")
        }
    }

    // MARK: - Currency Conversion (Stub Rates)

    func testCurrencyConversion() {
        let result = eval("$100 in EUR")
        // Stub rates: EUR = 0.92 relative to USD
        if case .currency(let val, let code) = result {
            XCTAssertEqual(code, "EUR")
            XCTAssertEqual(val, 92, accuracy: 1) // approximate with stub rates
        } else {
            XCTFail("Expected currency result, got \(result)")
        }
    }

    func testCurrencyConversionByCode() {
        let result = eval("1 BRL in USD")
        if case .currency(let val, let code) = result {
            XCTAssertEqual(code, "USD")
            XCTAssertEqual(val, 1.0 / 4.97, accuracy: 0.001)
        } else {
            XCTFail("Expected currency result, got \(result)")
        }
    }

    func testCurrencyConversionByFullName() {
        let result = eval("1 Brazilian real in US dollar")
        if case .currency(let val, let code) = result {
            XCTAssertEqual(code, "USD")
            XCTAssertEqual(val, 1.0 / 4.97, accuracy: 0.001)
        } else {
            XCTFail("Expected currency result, got \(result)")
        }
    }

    // MARK: - Math Functions

    func testSqrt() {
        XCTAssertEqual(eval("sqrt(144)"), .number(12))
    }

    func testAbs() {
        XCTAssertEqual(eval("abs(-5)"), .number(5))
    }

    func testRound() {
        XCTAssertEqual(eval("round(3.7)"), .number(4))
    }

    func testFloor() {
        XCTAssertEqual(eval("floor(3.7)"), .number(3))
    }

    func testCeil() {
        XCTAssertEqual(eval("ceil(3.2)"), .number(4))
    }

    func testFactorial() {
        XCTAssertEqual(eval("fact(5)"), .number(120))
    }

    func testSin() {
        XCTAssertEqual(eval("sin(0)"), .number(0))
    }

    func testLog() {
        let result = eval("log(100)")
        if case .number(let val) = result {
            XCTAssertEqual(val, 2, accuracy: 0.0001) // log10(100) = 2
        } else { XCTFail() }
    }

    func testLn() {
        let result = eval("ln(1)")
        XCTAssertEqual(result, .number(0))
    }
}
