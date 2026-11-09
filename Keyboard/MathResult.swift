import Foundation

/// "Show Maths Results", like the iOS keyboard: when the text ends with a sum
/// and "=" ("12*3=", "(4+5)/2 ="), the result is offered in the bar.
/// A small parser of its own: NSExpression raises an Objective-C exception on
/// malformed input, which Swift can't catch.
enum MathResult {
    /// The result for text ending in "expression=", or nil.
    static func result(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("=") else { return nil }
        let allowed = Set("0123456789.,+-*/×÷^%() ")
        let expression = String(trimmed.dropLast().reversed().prefix { allowed.contains($0) }.reversed())
            .trimmingCharacters(in: .whitespaces)
        // A number alone ("2024=") or an operator at the start is not a sum.
        guard expression.contains(where: \.isNumber),
              expression.dropFirst().contains(where: { "+-*/×÷^%".contains($0) }) else { return nil }
        // "1,5" is a decimal comma (French, German, Spanish) unless there's a dot.
        let comma = !expression.contains(".") && expression.contains(",")
        var parser = Parser(Array(comma ? expression.replacingOccurrences(of: ",", with: ".") : expression))
        guard let value = parser.parse(), value.isFinite else { return nil }
        return format(value, comma: comma)
    }

    private static func format(_ value: Double, comma: Bool) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 8
        f.decimalSeparator = comma ? "," : "."
        f.minusSign = "-"
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// expr := term (('+'|'-') term)*; term := power (('*'|'/'|'%') power)*;
    /// power := unary ('^' power)?; unary := '-' unary | atom '%'?; atom := number | '(' expr ')'.
    private struct Parser {
        let chars: [Character]
        var i = 0
        init(_ chars: [Character]) { self.chars = chars.filter { $0 != " " } }

        mutating func parse() -> Double? {
            guard let v = expr(), i == chars.count else { return nil }
            return v
        }

        private var peek: Character? { i < chars.count ? chars[i] : nil }

        private mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while let c = peek, c == "+" || c == "-" {
                i += 1
                guard let r = term() else { return nil }
                v = c == "+" ? v + r : v - r
            }
            return v
        }

        private mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while let c = peek, "*/×÷".contains(c) {
                i += 1
                guard let r = power() else { return nil }
                if c == "*" || c == "×" { v *= r } else { guard r != 0 else { return nil }; v /= r }
            }
            return v
        }

        private mutating func power() -> Double? {
            guard let v = unary() else { return nil }
            guard peek == "^" else { return v }
            i += 1
            guard let r = power() else { return nil }
            return pow(v, r)
        }

        private mutating func unary() -> Double? {
            if peek == "-" { i += 1; return unary().map { -$0 } }
            guard var v = atom() else { return nil }
            if peek == "%" { i += 1; v /= 100 }
            return v
        }

        private mutating func atom() -> Double? {
            if peek == "(" {
                i += 1
                guard let v = expr(), peek == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while let c = peek, c.isNumber || c == "." { i += 1 }
            return i > start ? Double(String(chars[start..<i])) : nil
        }
    }
}
