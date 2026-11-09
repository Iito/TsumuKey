import Foundation

/// Emoji in Unicode's order and groups, with search keywords in English,
/// French, German, Spanish and Japanese (emoji.tsv, from Unicode 15.0 and
/// CLDR, what iOS 17 can draw).
enum EmojiData {
    enum Category: String, CaseIterable, Identifiable {
        case recents, smileys, people, animals, food, travel, activities, objects, symbols, flags
        var id: Self { self }
        var symbol: String {
            switch self {
            case .recents: "clock"
            case .smileys: "face.smiling"
            case .people: "hand.wave"
            case .animals: "pawprint"
            case .food: "fork.knife"
            case .travel: "car"
            case .activities: "soccerball"
            case .objects: "lightbulb"
            case .symbols: "heart"
            case .flags: "flag"
            }
        }
        var name: String {
            switch self {
            case .recents: "Recently used"
            case .smileys: "Smileys"
            case .people: "People"
            case .animals: "Animals and nature"
            case .food: "Food and drink"
            case .travel: "Travel and places"
            case .activities: "Activities"
            case .objects: "Objects"
            case .symbols: "Symbols"
            case .flags: "Flags"
            }
        }
    }

    struct Entry {
        let emoji: String
        let category: Category
        /// " word word …": a leading space so " " + query matches word starts.
        let keywords: String
        /// Five skin-tone versions, light to dark; empty when it has none.
        let tones: [String]
    }

    static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 4, let c = Category(rawValue: String(f[0])) else { return nil }
            return Entry(emoji: String(f[1]), category: c, keywords: " " + f[2],
                         tones: f[3].split(separator: " ").map(String.init))
        }
    }()

    private static let tonesByEmoji: [String: [String]] = Dictionary(
        entries.filter { !$0.tones.isEmpty }.map { ($0.emoji, $0.tones) }, uniquingKeysWith: { a, _ in a })

    /// The emoji and its five skin tones (nil when it has none), for the long-press picker.
    static func toneChoices(_ emoji: String) -> [String]? {
        tonesByEmoji[emoji].map { [emoji] + $0 }
    }

    /// The emoji in skin tone 1...5 (0 = the default yellow); unchanged when it has no tones.
    static func toned(_ emoji: String, _ tone: Int) -> String {
        guard tone > 0, let t = tonesByEmoji[emoji], tone <= t.count else { return emoji }
        return t[tone - 1]
    }

    static var all: [String] { entries.map(\.emoji) }

    /// Emoji whose keywords start with every word of the query (any of the
    /// five languages); whole-word matches first, then Unicode order.
    static func search(_ query: String, limit: Int = 80) -> [String] {
        let words = query.lowercased().split(separator: " ").map { " " + $0 }
        guard !words.isEmpty else { return [] }
        var exact: [String] = [], prefix: [String] = []
        for e in entries where words.allSatisfy({ e.keywords.contains($0) }) {
            if words.allSatisfy({ e.keywords.contains($0 + " ") || e.keywords.hasSuffix(String($0)) }) {
                exact.append(e.emoji)
            } else {
                prefix.append(e.emoji)
            }
        }
        return Array((exact + prefix).prefix(limit))
    }
}
