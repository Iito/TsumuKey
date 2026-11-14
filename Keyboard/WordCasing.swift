import Foundation

/// Words with a fixed spelling ("USA"-style acronyms, "iPhone", English
/// "Monday"), from casing.txt. The word list only has lowercase words, so
/// without this they'd come out as "api" and "iphone".
enum WordCasing {
    /// Lowercased word → its spelling. Empty when the file is missing (bench).
    static let forms: [String: String] = {
        guard let url = Bundle.main.url(forResource: "casing", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var forms: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let form = line.trimmingCharacters(in: .whitespaces)
            guard !form.isEmpty, !form.hasPrefix("#") else { continue }
            forms[form.lowercased()] = form
        }
        return forms
    }()

    /// The fixed spelling of a word (lowercase or not), with a possessive
    /// kept ("iphone's" → "iPhone's"), or nil when it has none.
    static func form(of word: String) -> String? {
        let lower = word.lowercased().replacingOccurrences(of: "’", with: "'")
        if let form = forms[lower] { return form }
        guard lower.hasSuffix("'s"), let form = forms[String(lower.dropLast(2))] else { return nil }
        return form + word.suffix(2)
    }

    /// The word as it should be typed: its fixed spelling, or as it is.
    static func apply(_ word: String) -> String { form(of: word) ?? word }

    /// A typed word to respell when it's finished ("iphone" → "iPhone"), or
    /// nil. Words typed in all capitals stay that way ("IPHONE").
    static func fix(for word: String) -> String? {
        guard let form = form(of: word), form != word else { return nil }
        if word.count > 1, word == word.uppercased() { return nil }
        return form
    }
}
