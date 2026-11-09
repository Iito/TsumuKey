import Foundation

/// "100$ in €=", "100 usd to jpy =", "5000¥ en €=": the converted amount for the
/// bar, from the rates the app saved (CurrencyRates). Nil without rates or
/// for a currency the ECB doesn't list.
enum CurrencyResult {
    static var rates: CurrencyRates?

    /// (label for the bar, text to type). The label adds the rates' date
    /// when they're more than 3 days old.
    static func result(for text: String, now: Date = Date()) -> (label: String, text: String)? {
        guard let rates, text.hasSuffix("="), text.count < 4000 else { return nil }
        let tail = String(text.suffix(60))
        let cur = #"([$€£¥₹₩₺円]|[A-Za-z]{3,7})"#
        let num = #"([0-9]+(?:[.,][0-9]+)?)"#
        let pattern = "(?:\(cur)\\s*\(num)|\(num)\\s*\(cur))\\s+(?:in|to|en|a|à|nach|zu|→|->)\\s+\(cur)\\s*=$"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)) else { return nil }
        func group(_ i: Int) -> String? {
            Range(m.range(at: i), in: tail).map { String(tail[$0]) }
        }
        guard let amountText = group(2) ?? group(3),
              let fromText = group(1) ?? group(4), let toText = group(5),
              let from = code(fromText), let to = code(toText), from != to,
              let fromRate = rates.perEuro[from], let toRate = rates.perEuro[to] else { return nil }
        let comma = amountText.contains(",")
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let value = amount / fromRate * toRate
        let shown = format(value, code: to, typed: toText, comma: comma)
        guard now.timeIntervalSince(rates.date) > 3 * 86400 else { return (shown, shown) }
        let day = DateFormatter()
        day.dateFormat = "d MMM"
        return ("\(shown) · \(day.string(from: rates.date))", shown)
    }

    /// "100€", "€100", "12,50 $" at the end of the text (no "="): the amount in
    /// the three currencies most used with that one, best first. `replace` is
    /// how many characters a tap swaps for the result.
    static func quick(for text: String) -> (replace: Int, results: [String])? {
        guard let rates else { return nil }
        let tail = String(text.suffix(40))
        let pattern = #"(?:^|[\s(])(?:([$€£¥円])\s?([0-9]+(?:[.,][0-9]+)?)|([0-9]+(?:[.,][0-9]+)?)\s?([$€£¥円]))$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: tail).map { String(tail[$0]) } }
        guard let amountText = group(2) ?? group(3), let symbol = group(1) ?? group(4),
              let from = symbols[symbol], let fromRate = rates.perEuro[from],
              let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let comma = amountText.contains(",")
        let results = (quickTargets[from] ?? []).compactMap { to -> String? in
            guard let toRate = rates.perEuro[to] else { return nil }
            return format(amount / fromRate * toRate, code: to, typed: mainSymbol[to] ?? to, comma: comma)
        }
        guard !results.isEmpty, let whole = Range(m.range, in: tail) else { return nil }
        let matched = tail[whole].drop { $0.isWhitespace || $0 == "(" }
        return (matched.count, results)
    }

    private static let quickTargets: [String: [String]] = [
        "EUR": ["USD", "GBP", "JPY"],
        "JPY": ["USD", "EUR", "GBP"],
        "USD": ["EUR", "GBP", "JPY"],
        "GBP": ["USD", "EUR", "JPY"],
    ]
    private static let mainSymbol = ["USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥"]

    private static let symbols: [String: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "円": "JPY", "₹": "INR", "₩": "KRW", "₺": "TRY",
        "dollar": "USD", "dollars": "USD", "euro": "EUR", "euros": "EUR", "yen": "JPY",
        "pound": "GBP", "pounds": "GBP",
    ]

    private static func code(_ s: String) -> String? {
        if let c = symbols[s.lowercased()] { return c }
        let upper = s.uppercased()
        return upper.count == 3 && rates?.perEuro[upper] != nil ? upper : nil
    }

    /// "€92.15", "92,15 €" (decimal comma), "1,234 JPY" style: symbol before
    /// the number with a dot, after it with a comma; a typed code stays a code.
    private static func format(_ value: Double, code: String, typed: String, comma: Bool) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        let noCents: Set = ["JPY", "KRW", "IDR", "HUF", "ISK"]
        f.minimumFractionDigits = noCents.contains(code) ? 0 : 2
        f.maximumFractionDigits = f.minimumFractionDigits
        f.decimalSeparator = comma ? "," : "."
        let number = f.string(from: NSNumber(value: value)) ?? String(value)
        let symbol = typed.count == 1 ? typed : nil
        guard let symbol else { return "\(number) \(code)" }
        return comma || symbol == "円" ? "\(number) \(symbol)" : "\(symbol)\(number)"
    }
}
