import UIKit

/// Word suggestions (iOS spell checker) that query the enabled languages
/// together, so the bar never gets stuck in one: each word is matched in all.
/// Used until the model is loaded, and for the Japanese chip's "is this a word".
enum Suggester {
    private static let checker = UITextChecker()

    /// Set from the settings each time the keyboard opens (main thread).
    static var languages: [PredictionLanguage] = [.english, .french] {
        didSet { if languages != oldValue { codes = Self.checkerCodes(for: languages) } }
    }
    private static var codes = checkerCodes(for: languages)

    private static func checkerCodes(for languages: [PredictionLanguage]) -> [String] {
        let available = UITextChecker.availableLanguages
        let preferred: [PredictionLanguage: String] = [.english: "en_US", .french: "fr_FR", .german: "de_DE", .spanish: "es_ES"]
        // Exact codes vary by device ("en_US" vs "en"), so match by prefix.
        return languages.compactMap { l in
            available.first { $0 == preferred[l] } ?? available.first { $0.hasPrefix(l.rawValue) }
        }
    }

    /// Missing apostrophes, fixed without asking. Words that are also real
    /// words on their own (its, were, ill, id, wed, lets, shell, nest, and French "dont"…) are left out
    /// on purpose.
    fileprivate static var contractions: [String: String] {
        (languages.contains(.english) ? english : [:]).merging(languages.contains(.french) ? french : [:]) { a, _ in a }
    }
    private static let english: [String: String] = [
        "i": "I", "im": "I'm", "ive": "I've",
        "cant": "can't", "wont": "won't", "aint": "ain't",
        "isnt": "isn't", "arent": "aren't", "wasnt": "wasn't", "werent": "weren't",
        "doesnt": "doesn't", "didnt": "didn't", "hasnt": "hasn't", "havent": "haven't",
        "hadnt": "hadn't", "couldnt": "couldn't", "shouldnt": "shouldn't",
        "wouldnt": "wouldn't", "mustnt": "mustn't", "neednt": "needn't",
        "youre": "you're", "youve": "you've", "youll": "you'll", "youd": "you'd",
        "theyre": "they're", "theyve": "they've", "theyll": "they'll", "theyd": "they'd",
        "weve": "we've", "hes": "he's", "shes": "she's",
        "thats": "that's", "whats": "what's", "whos": "who's", "wheres": "where's",
        "theres": "there's", "heres": "here's", "yall": "y'all",
    ]
    private static let french: [String: String] = [
        "cest": "c'est", "jai": "j'ai", "jetais": "j'étais", "jaime": "j'aime",
        "quil": "qu'il", "quils": "qu'ils",
        "daccord": "d'accord", "aujourdhui": "aujourd'hui", "jusqua": "jusqu'à",
    ]

    /// The correction to apply automatically on space or punctuation, if any.
    /// Deliberately conservative: when typing two languages, guessing at
    /// general typos would keep "fixing" French words into English.
    static func autocorrection(for word: String) -> String? {
        guard !word.isEmpty else { return nil }
        let lower = word.lowercased()

        if let fix = contractions[lower] {
            let cased = word.first?.isUppercase == true ? fix.prefix(1).uppercased() + fix.dropFirst() : fix
            return cased == word ? nil : cased
        }

        // Accent-only fixes, when the word is wrong in every language:
        // "ecole" -> "école", but never a different word.
        guard word.count >= 3, isMisspelledEverywhere(lower) else { return nil }
        for language in codes {
            let range = NSRange(location: 0, length: (lower as NSString).length)
            for guess in checker.guesses(forWordRange: range, in: lower, language: language) ?? []
            where guess != lower && guess.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) == lower {
                return word.first?.isUppercase == true ? guess.prefix(1).uppercased() + guess.dropFirst() : guess
            }
        }
        return nil
    }

    /// Spelled right in one of the enabled languages.
    static func isWord(_ word: String) -> Bool { !isMisspelledEverywhere(word.lowercased()) }

    private static func isMisspelledEverywhere(_ word: String) -> Bool {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return codes.allSatisfy {
            checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false,
                                          language: $0).location != NSNotFound
        }
    }

    static func suggestions(for word: String, limit: Int = 3) -> [String] {
        guard !word.isEmpty else { return [] }
        let query = word.lowercased() as NSString
        let range = NSRange(location: 0, length: query.length)

        let perLanguage = codes.map {
            checker.completions(forPartialWordRange: range, in: query as String, language: $0) ?? []
        }

        // If the word is a typo in every language, add spelling fixes too.
        // This is what turns "ecole" into "école" without hunting for accents.
        let misspelledEverywhere = codes.allSatisfy {
            checker.rangeOfMisspelledWord(in: query as String, range: range, startingAt: 0,
                                          wrap: false, language: $0).location != NSNotFound
        }
        let fixes = misspelledEverywhere
            ? codes.map { checker.guesses(forWordRange: range, in: query as String, language: $0) ?? [] }
            : []

        // Interleave languages so the top results always include both.
        var merged: [String] = []
        var seen = Set<String>()
        for list in [fixes, perLanguage] {
            let depth = list.map(\.count).max() ?? 0
            for i in 0..<depth {
                for candidates in list where i < candidates.count {
                    let candidate = candidates[i]
                    if candidate != query as String, seen.insert(candidate).inserted {
                        merged.append(candidate)
                    }
                }
            }
        }

        let capitalized = word.first?.isUppercase == true
        return merged.prefix(limit).map { capitalized ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }
    }
}

extension Suggester {
    /// A missing apostrophe fixed without asking ("im" → "I'm"), or nil.
    static func contraction(for word: String) -> String? {
        guard let fix = contractions[word.lowercased()] else { return nil }
        let cased = word.first?.isUppercase == true ? fix.prefix(1).uppercased() + fix.dropFirst() : fix
        return cased == word ? nil : cased
    }
}
