// swiftc -O Keyboard/Emoji.swift Tools/test_emoji_lookup.swift -o <directory>/test_emoji_lookup
// Place emoji.tsv beside the binary before running it.
import Foundation

@main struct TestEmojiLookup {
    static func main() throws {
        let url = Bundle.main.url(forResource: "emoji", withExtension: "tsv")!
        let text = try String(contentsOf: url, encoding: .utf8)
        let entries: [(String, String, [String])] = text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 4, EmojiData.Category(rawValue: String(f[0])) != nil else { return nil }
            return (String(f[1]), " " + f[2] + " ", f.count > 4 ? f[4].split(separator: "|").map(String.init) : [])
        }
        let stop: Set<String> = [
            "the", "and", "you", "for", "with", "not", "but", "are", "was", "this", "that", "from", "your", "our", "its",
            "les", "des", "une", "que", "qui", "avec", "pour", "dans", "sur", "pas", "est", "mon", "ton", "son", "par",
            "und", "mit", "der", "die", "das", "den", "dem", "ein", "eine", "ist", "für", "von", "auf", "nicht", "ich",
            "los", "las", "una", "con", "por", "para", "del", "muy", "pero", "sin",
        ]
        func reference(_ word: String) -> String? {
            let w = word.lowercased()
            guard w.count >= 3 || w == "ok", !stop.contains(w), !w.contains(" ") else { return nil }
            let needle = " \(w) "
            var best: (rank: Double, emoji: String)?
            var matches = 0
            for (emoji, keywords, names) in entries where keywords.contains(needle) {
                matches += 1
                let rank: Double
                if names.contains(w) { rank = 0 }
                else if let name = names.first(where: { " \($0) ".contains(needle) }) {
                    rank = 1 + Double(name.split(separator: " ").count) / 100
                } else {
                    let tokens = keywords.split(separator: " ")
                    rank = 2 + Double(tokens.firstIndex(of: Substring(w)) ?? tokens.count) / Double(tokens.count)
                }
                if rank < best?.rank ?? .infinity { best = (rank, emoji) }
            }
            guard let best, best.rank < 2 || matches <= 30 else { return nil }
            return best.emoji
        }
        precondition(entries.count > 1000 && EmojiData.entries.count == entries.count, "Emoji data missing")
        let words = Set(entries.flatMap { $0.1.split(separator: " ").map(String.init) }).sorted()
        var queries = stride(from: 0, to: words.count, by: max(1, words.count / 500)).map { words[$0] }
        queries += ["hello", "world", "the", "ok", "café", "cafe\u{301}", "ma\u{308}dchen", "メロン", "가족", "not a word"]
        queries += queries.prefix(100).map(\.decomposedStringWithCanonicalMapping)
        for query in queries {
            let actual = EmojiData.suggestion(for: query), expected = reference(query)
            precondition(actual == expected, "Mismatch for \(query): \(actual ?? "nil") vs \(expected ?? "nil")")
        }
        print("PASS \(queries.count) queries against original lookup, \(entries.count) entries")
    }
}
