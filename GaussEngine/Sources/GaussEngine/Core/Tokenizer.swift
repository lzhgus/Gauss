import Foundation

/// Converts a raw input string into a sequence of ``Token``s.
public struct Tokenizer {
    private let definitions: DefinitionLoader

    public init(definitions: DefinitionLoader) {
        self.definitions = definitions
    }

    // MARK: - Public API

    /// Tokenize one line of user input.
    public func tokenize(_ input: String) -> [Token] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        // 1. Header: starts with "# " (hash followed by space)
        if trimmed.hasPrefix("# ") {
            let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return [.header(title)]
        }
        if trimmed == "#" {
            return [.header("")]
        }

        // 2. Comment: starts with "//"
        if trimmed.hasPrefix("//") {
            let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return [.comment(text)]
        }

        // 3. Label: "SomeText: rest" — the part before ":" must be letters/spaces only
        if let colonIdx = trimmed.firstIndex(of: ":") {
            let before = String(trimmed[trimmed.startIndex..<colonIdx])
                .trimmingCharacters(in: .whitespaces)
            let after  = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)
            if isValidLabel(before) {
                var tokens: [Token] = [.label(before)]
                tokens.append(contentsOf: tokenizeExpression(after))
                return tokens
            }
        }

        // 4. Expression
        return tokenizeExpression(trimmed)
    }

    // MARK: - Label validation

    /// Returns true when `text` consists only of Unicode letters, spaces, and is non-empty.
    private func isValidLabel(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            CharacterSet.letters.union(.whitespaces).contains(scalar)
        }
    }

    // MARK: - Expression tokenizer (character scanner)

    private func tokenizeExpression(_ input: String) -> [Token] {
        var tokens: [Token] = []
        let scalars = Array(input.unicodeScalars)
        var idx = 0

        while idx < scalars.count {
            let sc = scalars[idx]

            // ── Whitespace ────────────────────────────────────────────────
            if CharacterSet.whitespaces.contains(sc) {
                idx += 1
                continue
            }

            // ── Double-quoted string ──────────────────────────────────────
            if sc.value == UInt32(UnicodeScalar("\"").value) {
                idx += 1
                var str = ""
                while idx < scalars.count && scalars[idx].value != UInt32(UnicodeScalar("\"").value) {
                    str.unicodeScalars.append(scalars[idx])
                    idx += 1
                }
                if idx < scalars.count { idx += 1 } // consume closing "
                tokens.append(.string(str))
                continue
            }

            // ── Hex color: # followed by exactly 6 hex digits ────────────
            if sc.value == UInt32(UnicodeScalar("#").value) {
                let remaining = scalars[(idx + 1)...]
                if remaining.count >= 6 {
                    let hexSlice = remaining.prefix(6)
                    let all6Hex  = hexSlice.allSatisfy { isHexDigit($0) }
                    // Must be exactly 6 — next char (if any) must not be hex
                    let after6 = idx + 7
                    let notContinued = after6 >= scalars.count || !isHexDigit(scalars[after6])
                    if all6Hex && notContinued {
                        let hexStr = String(String.UnicodeScalarView(hexSlice))
                        tokens.append(.hexColor(hexStr))
                        idx += 7
                        continue
                    }
                }
                // Not a valid hex colour — skip the '#' as unknown
                idx += 1
                continue
            }

            // ── Currency symbols ──────────────────────────────────────────
            if let currencyCode = currencyCodeForScalar(sc) {
                idx += 1
                // Some symbols are multi-scalar (e.g., "A$") — handled by
                // matching the full symbol string below; single-scalar handled here.
                // Scan the following number.
                let (value, newIdx) = scanDouble(scalars: scalars, from: idx)
                if let v = value {
                    tokens.append(.currency(v, currencyCode))
                    idx = newIdx
                } else {
                    // Not followed by a number — emit identifier of symbol
                    tokens.append(.identifier(String(sc)))
                }
                continue
            }

            // ── Numbers (digits, possibly with 0x/0b/0o prefix) ──────────
            if isDigit(sc) {
                // Look for 0x / 0b / 0o prefixes
                if sc.value == UInt32(UnicodeScalar("0").value) && idx + 1 < scalars.count {
                    let next = scalars[idx + 1]
                    if next.value == UInt32(UnicodeScalar("x").value) || next.value == UInt32(UnicodeScalar("X").value) {
                        // Hex integer
                        idx += 2
                        let start = idx
                        while idx < scalars.count && isHexDigit(scalars[idx]) { idx += 1 }
                        let hexStr = String(String.UnicodeScalarView(scalars[start..<idx]))
                        let value  = Int(hexStr, radix: 16) ?? 0
                        tokens.append(.hexNumber(value))
                        continue
                    }
                    if next.value == UInt32(UnicodeScalar("b").value) || next.value == UInt32(UnicodeScalar("B").value) {
                        // Binary integer
                        idx += 2
                        let start = idx
                        while idx < scalars.count && isBinaryDigit(scalars[idx]) { idx += 1 }
                        let binStr = String(String.UnicodeScalarView(scalars[start..<idx]))
                        let value  = Int(binStr, radix: 2) ?? 0
                        tokens.append(.binaryNumber(value))
                        continue
                    }
                    if next.value == UInt32(UnicodeScalar("o").value) || next.value == UInt32(UnicodeScalar("O").value) {
                        // Octal integer
                        idx += 2
                        let start = idx
                        while idx < scalars.count && isOctalDigit(scalars[idx]) { idx += 1 }
                        let octStr = String(String.UnicodeScalarView(scalars[start..<idx]))
                        let value  = Int(octStr, radix: 8) ?? 0
                        tokens.append(.octalNumber(value))
                        continue
                    }
                }

                // Regular decimal number
                let (value, newIdx) = scanDouble(scalars: scalars, from: idx)
                idx = newIdx
                let numValue = value ?? 0.0

                // Check for percentage immediately after number (no space)
                if idx < scalars.count && scalars[idx].value == UInt32(UnicodeScalar("%").value) {
                    tokens.append(.percentage(numValue))
                    idx += 1
                    continue
                }

                // Check for scale suffix immediately after number (no space)
                if let (scale, afterScale) = scanScaleSuffix(scalars: scalars, from: idx) {
                    tokens.append(.number(numValue * scale))
                    idx = afterScale
                    continue
                }

                tokens.append(.number(numValue))
                continue
            }

            // ── Letter sequences (keywords, identifiers, rgb, scales) ─────
            if isLetter(sc) {
                let start = idx
                while idx < scalars.count && (isLetter(scalars[idx]) || isDigit(scalars[idx])) {
                    idx += 1
                }
                let word = String(String.UnicodeScalarView(scalars[start..<idx]))

                // Special case: rgb(R, G, B)
                if word.lowercased() == "rgb" {
                    if idx < scalars.count && scalars[idx].value == UInt32(UnicodeScalar("(").value) {
                        if let (r, g, b, afterRgb) = scanRgb(scalars: scalars, from: idx) {
                            tokens.append(.rgbColor(r, g, b))
                            idx = afterRgb
                            continue
                        }
                    }
                }

                // Try multi-word operators first (e.g., "multiplied by", "divided by")
                if let (keyword, afterKeyword) = tryMatchMultiWordOperator(
                    word: word, scalars: scalars, from: idx
                ) {
                    tokens.append(keyword)
                    idx = afterKeyword
                    continue
                }

                // Single-word keyword check (in, to, as, of, on, off, from, times, plus, minus, divide)
                if let kw = keywordFor(word) {
                    tokens.append(.keyword(kw))
                    continue
                }

                if let (phrase, afterPhrase) = tryMatchMultiWordVariant(
                    word: word, scalars: scalars, from: idx
                ) {
                    tokens.append(.identifier(phrase))
                    idx = afterPhrase
                    continue
                }

                // Scale suffix: "billion", "million", "thousand" — but only when
                // the previous token is a number.
                if let multiplier = definitions.scales[word] {
                    if case .number(let prev) = tokens.last {
                        tokens[tokens.count - 1] = .number(prev * multiplier)
                        continue
                    }
                    // Otherwise fall through to identifier
                }

                // Natural language operators from definitions (single-word ones)
                // Note: multi-word handled above; avoid re-matching keywords already handled
                if let op = definitions.operators[word.lowercased()] {
                    // Only emit as op when not already covered by Keyword
                    tokens.append(.op(op))
                    continue
                }

                tokens.append(.identifier(word))
                continue
            }

            // ── Operators and punctuation ─────────────────────────────────

            // += / -= / *= / /= etc.
            if sc.value == UInt32(UnicodeScalar("+").value) {
                if idx + 1 < scalars.count && scalars[idx + 1].value == UInt32(UnicodeScalar("=").value) {
                    tokens.append(.compoundAssignment(.add))
                    idx += 2
                } else {
                    tokens.append(.op(.add))
                    idx += 1
                }
                continue
            }
            if sc.value == UInt32(UnicodeScalar("-").value) {
                if idx + 1 < scalars.count && scalars[idx + 1].value == UInt32(UnicodeScalar("=").value) {
                    tokens.append(.compoundAssignment(.subtract))
                    idx += 2
                } else {
                    tokens.append(.op(.subtract))
                    idx += 1
                }
                continue
            }
            if sc.value == UInt32(UnicodeScalar("*").value) {
                if idx + 1 < scalars.count && scalars[idx + 1].value == UInt32(UnicodeScalar("=").value) {
                    tokens.append(.compoundAssignment(.multiply))
                    idx += 2
                } else {
                    tokens.append(.op(.multiply))
                    idx += 1
                }
                continue
            }
            if sc.value == UInt32(UnicodeScalar("/").value) {
                if idx + 1 < scalars.count && scalars[idx + 1].value == UInt32(UnicodeScalar("=").value) {
                    tokens.append(.compoundAssignment(.divide))
                    idx += 2
                } else {
                    tokens.append(.op(.divide))
                    idx += 1
                }
                continue
            }
            if sc.value == UInt32(UnicodeScalar("^").value) {
                tokens.append(.op(.power))
                idx += 1
                continue
            }
            if sc.value == UInt32(UnicodeScalar("%").value) {
                // Standalone % (not after a number — those are handled above)
                tokens.append(.op(.mod))
                idx += 1
                continue
            }
            if sc.value == UInt32(UnicodeScalar("=").value) {
                tokens.append(.assignment)
                idx += 1
                continue
            }
            if sc.value == UInt32(UnicodeScalar("(").value) {
                tokens.append(.leftParen)
                idx += 1
                continue
            }
            if sc.value == UInt32(UnicodeScalar(")").value) {
                tokens.append(.rightParen)
                idx += 1
                continue
            }

            // Skip unknown characters
            idx += 1
        }

        return tokens
    }

    // MARK: - Scanning helpers

    /// Scan a Double starting at `from`. Returns (value, nextIndex) or (nil, from).
    private func scanDouble(scalars: [Unicode.Scalar], from start: Int) -> (Double?, Int) {
        var idx = start
        var str = ""
        while idx < scalars.count && isDigit(scalars[idx]) {
            str.unicodeScalars.append(scalars[idx])
            idx += 1
        }
        if idx < scalars.count && scalars[idx].value == UInt32(UnicodeScalar(".").value) {
            // Check next is digit
            if idx + 1 < scalars.count && isDigit(scalars[idx + 1]) {
                str.unicodeScalars.append(scalars[idx])   // "."
                idx += 1
                while idx < scalars.count && isDigit(scalars[idx]) {
                    str.unicodeScalars.append(scalars[idx])
                    idx += 1
                }
            }
        }
        guard !str.isEmpty, let value = Double(str) else {
            return (nil, start)
        }
        return (value, idx)
    }

    /// Try to match a scale suffix immediately after a number (no spaces).
    /// Returns (multiplier, nextIndex) or nil.
    private func scanScaleSuffix(scalars: [Unicode.Scalar], from start: Int) -> (Double, Int)? {
        guard start < scalars.count, isLetter(scalars[start]) else { return nil }
        var idx = start
        while idx < scalars.count && isLetter(scalars[idx]) { idx += 1 }
        let word = String(String.UnicodeScalarView(scalars[start..<idx]))
        if let multiplier = definitions.scales[word] {
            return (multiplier, idx)
        }
        return nil
    }

    /// Scan rgb(R, G, B) starting at the "(" index.
    private func scanRgb(scalars: [Unicode.Scalar], from parenIdx: Int) -> (Int, Int, Int, Int)? {
        var idx = parenIdx + 1  // skip "("
        // Skip whitespace
        while idx < scalars.count && CharacterSet.whitespaces.contains(scalars[idx]) { idx += 1 }
        guard let (r, idx2) = scanInt(scalars: scalars, from: idx) else { return nil }
        var i = idx2
        while i < scalars.count && CharacterSet.whitespaces.contains(scalars[i]) { i += 1 }
        guard i < scalars.count && scalars[i].value == UInt32(UnicodeScalar(",").value) else { return nil }
        i += 1
        while i < scalars.count && CharacterSet.whitespaces.contains(scalars[i]) { i += 1 }
        guard let (g, idx3) = scanInt(scalars: scalars, from: i) else { return nil }
        i = idx3
        while i < scalars.count && CharacterSet.whitespaces.contains(scalars[i]) { i += 1 }
        guard i < scalars.count && scalars[i].value == UInt32(UnicodeScalar(",").value) else { return nil }
        i += 1
        while i < scalars.count && CharacterSet.whitespaces.contains(scalars[i]) { i += 1 }
        guard let (b, idx4) = scanInt(scalars: scalars, from: i) else { return nil }
        i = idx4
        while i < scalars.count && CharacterSet.whitespaces.contains(scalars[i]) { i += 1 }
        guard i < scalars.count && scalars[i].value == UInt32(UnicodeScalar(")").value) else { return nil }
        i += 1
        return (r, g, b, i)
    }

    private func scanInt(scalars: [Unicode.Scalar], from start: Int) -> (Int, Int)? {
        var idx = start
        var str = ""
        while idx < scalars.count && isDigit(scalars[idx]) {
            str.unicodeScalars.append(scalars[idx])
            idx += 1
        }
        guard !str.isEmpty, let value = Int(str) else { return nil }
        return (value, idx)
    }

    // MARK: - Keyword / operator mapping

    /// Maps a single word to a ``Keyword`` if applicable.
    private func keywordFor(_ word: String) -> Keyword? {
        switch word.lowercased() {
        case "in":     return .in
        case "to":     return .to
        case "as":     return .as
        case "of":     return .of
        case "on":     return .on
        case "off":    return .off
        case "from":   return .from
        case "times":  return .times
        case "plus":   return .plus
        case "minus":  return .minus
        case "divide": return .divide
        default:       return nil
        }
    }

    /// Try to match multi-word operators like "multiplied by" or "divided by".
    /// Returns (token, nextIndex) if matched, nil otherwise.
    private func tryMatchMultiWordOperator(
        word: String,
        scalars: [Unicode.Scalar],
        from afterFirstWord: Int
    ) -> (Token, Int)? {
        // Build candidate multi-word strings by looking ahead through words
        var peek = afterFirstWord
        // Skip whitespace
        while peek < scalars.count && CharacterSet.whitespaces.contains(scalars[peek]) { peek += 1 }
        guard peek < scalars.count && isLetter(scalars[peek]) else { return nil }

        let secondStart = peek
        while peek < scalars.count && isLetter(scalars[peek]) { peek += 1 }
        let secondWord = String(String.UnicodeScalarView(scalars[secondStart..<peek]))

        let multiWord = "\(word.lowercased()) \(secondWord.lowercased())"
        if let op = definitions.operators[multiWord] {
            return (.op(op), peek)
        }
        return nil
    }

    private func tryMatchMultiWordVariant(
        word: String,
        scalars: [Unicode.Scalar],
        from afterFirstWord: Int
    ) -> (String, Int)? {
        var words = [word]
        var ends = [afterFirstWord]
        var peek = afterFirstWord

        for _ in 0..<4 {
            while peek < scalars.count && CharacterSet.whitespaces.contains(scalars[peek]) { peek += 1 }
            guard peek < scalars.count && isLetter(scalars[peek]) else { break }
            let start = peek
            while peek < scalars.count && (isLetter(scalars[peek]) || isDigit(scalars[peek])) {
                peek += 1
            }
            let next = String(String.UnicodeScalarView(scalars[start..<peek]))
            if keywordFor(next) != nil { break }
            words.append(next)
            ends.append(peek)
        }

        guard words.count >= 2 else { return nil }

        for i in stride(from: words.count, through: 2, by: -1) {
            let phrase = words[0..<i].joined(separator: " ")
            let lower = phrase.lowercased()
            if definitions.currencyByVariant[lower] != nil || definitions.unitsByVariant[lower] != nil {
                return (phrase, ends[i - 1])
            }
        }
        return nil
    }

    // MARK: - Currency symbol lookup

    /// Returns the currency code for a currency Unicode scalar, or nil.
    /// Scans the currencies list in definition order so the first matching currency
    /// wins (JPY is listed before CNY, so ¥ maps to JPY as expected).
    private func currencyCodeForScalar(_ sc: Unicode.Scalar) -> String? {
        let str = String(sc)
        for currency in definitions.currencies {
            if currency.symbol == str {
                return currency.code
            }
        }
        return nil
    }

    // MARK: - Character classification

    private func isDigit(_ sc: Unicode.Scalar) -> Bool {
        sc.value >= UInt32(UnicodeScalar("0").value) && sc.value <= UInt32(UnicodeScalar("9").value)
    }

    private func isLetter(_ sc: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(sc)
    }

    private func isHexDigit(_ sc: Unicode.Scalar) -> Bool {
        isDigit(sc)
        || (sc.value >= UInt32(UnicodeScalar("a").value) && sc.value <= UInt32(UnicodeScalar("f").value))
        || (sc.value >= UInt32(UnicodeScalar("A").value) && sc.value <= UInt32(UnicodeScalar("F").value))
    }

    private func isBinaryDigit(_ sc: Unicode.Scalar) -> Bool {
        sc.value == UInt32(UnicodeScalar("0").value) || sc.value == UInt32(UnicodeScalar("1").value)
    }

    private func isOctalDigit(_ sc: Unicode.Scalar) -> Bool {
        sc.value >= UInt32(UnicodeScalar("0").value) && sc.value <= UInt32(UnicodeScalar("7").value)
    }
}
