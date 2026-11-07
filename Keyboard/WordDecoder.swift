import CoreGraphics
import Foundation

/// One letter typed by a tap, with where the finger actually landed.
/// `point` is nil when the letter came from somewhere else (a popup).
struct Tap: Equatable {
    var letter: Character
    var point: CGPoint?
}

/// Centers of the letter keys, in the same coordinates as tap points.
struct KeyMap: Equatable {
    var centers: [Character: CGPoint] = [:]
    var keySize = CGSize(width: 39, height: 50)
}

struct DecodeRequest {
    /// Everything before the word being typed.
    var before: String
    var word: String
    var taps: [Tap]
    var keys: KeyMap
    var autocorrect: Bool
}

struct DecodeResult {
    var word: String
    var correction: String?
    var suggestions: [String]
    var log: String
}

/// What the decoder needs from a model: how likely each candidate word is
/// after the current context (log-probabilities, in nats), and guesses for
/// the next word. Gemma (LanguageModel) and the small ranker both provide it.
protocol WordScorer: AnyObject {
    @discardableResult func setContext(_ text: String) -> Bool
    /// Full score of each word as the next word.
    func score(_ words: [String], leadingSpace: Bool) -> [Float]
    /// Cheaper estimate, used to pick which candidates get the full score.
    func quickScore(_ words: [String], leadingSpace: Bool) -> [Float]
    func predict(count: Int, leadingSpace: Bool) -> [String]
    /// The word as typed (lowercased) and whether it's a real word, before scoring it and its fixes.
    func setTyped(_ word: String, isWord: Bool)
}

extension WordScorer {
    func setTyped(_ word: String, isWord: Bool) {}
}

/// Turns taps into words the way Gboard does: a tap isn't a letter, it's a
/// point that's probably that key and maybe a neighbour. Each candidate word
/// gets a score for how well its keys match where the fingers landed, plus
/// how likely the language model finds it here; the best total wins.
final class WordDecoder {
    let lm: WordScorer
    let lexicon: Lexicon
    /// French elisions ("menvoyer" → "m'envoyer") only when French is on.
    var french = true

    /// Cost (in nats, like the model's scores) of a tap with no letter, or a
    /// letter with no tap.
    static let editCost: Float = 5
    /// How much better a fix must score to replace a real word. Real words
    /// are usually meant, and a wrong "fix" is worse than a typo.
    static var replaceRealWordMargin: Float = 4.5
    /// Same, when the typed word isn't a word in either language.
    static var replaceTypoMargin: Float = 0.5
    /// Candidates too far from the taps aren't fixes, they're other words.
    static let worstSpatial: Float = -12
    /// Same letters, different accents or apostrophe ("a" → "à"), when what
    /// was typed is a real word too ("habite" must not become "habité").
    static let accentMargin: Float = 2.5
    /// How many tap-matching candidates go on to the model.
    static let maxCandidates = 40
    /// French elided prefixes: "menvoyer" → "m'envoyer".
    static let elisions = ["c", "d", "j", "l", "m", "n", "s", "t", "qu"]
    /// Only alternatives within this many nats of the best guess reach the bar.
    static let suggestionWindow: Float = 9
    /// Spread of taps around a key center, as a fraction of the key size.
    static let spread: CGFloat = 0.45
    /// How many candidates get the full (slow) model score.
    /// Full scoring costs ~4 ms per candidate on an iPhone 15 (the model's
    /// 48k-way output dominates), so only the best few get it.
    static let fullFixes = 6

    init(lm: WordScorer, lexicon: Lexicon) {
        self.lm = lm
        self.lexicon = lexicon
    }

    /// `full`: score the best candidates with the whole model (a finished
    /// word). Otherwise only the free first-token estimate is used (bar
    /// updates while typing), and no correction is proposed.
    func decode(_ r: DecodeRequest, full: Bool = true) -> DecodeResult {
        let started = Date()
        let (context, leadingSpace) = Self.split(r.before)
        lm.setContext(context)
        let tContext = Date()

        guard !r.word.isEmpty else {
            // The model knows all four languages; keep its guesses to the
            // enabled ones (a word with no key, like "2024", always passes).
            let predictions = ((leadingSpace || context.isEmpty)
                ? lm.predict(count: 3, leadingSpace: leadingSpace && !context.isEmpty) : [])
                .filter { Lexicon.key($0).map(lexicon.contains) ?? true }
            return DecodeResult(word: "", correction: nil, suggestions: predictions,
                                log: "PREDICT \(predictions) \(ms(started, Date()))ms")
        }
        let typed = r.word.lowercased()
        guard let typedKey = Lexicon.key(typed) else {
            return DecodeResult(word: r.word, correction: nil, suggestions: [], log: "DECODE \(r.word) skipped")
        }
        let gen = generate(r, typed: typed, typedKey: typedKey)
        let typedIsWord = gen.typedIsWord
        lm.setTyped(typed, isWord: typedIsWord)
        let keyOf = gen.keyOf
        var spatialCache = gen.spatial
        let spatialOf = { (k: String) -> Float in
            if let v = spatialCache[k] { return v }
            let v = Self.spatial(k, taps: gen.taps, keys: r.keys)
            spatialCache[k] = v
            return v
        }
        let tGen = Date()

        // Many candidates tie on taps alone (any missed letter costs the
        // same), so the model's free first-token guess breaks ties before
        // the full, slower scoring.
        let close = keyOf.filter { spatialOf($0.value) > Self.worstSpatial }.map(\.key)
        let quick = lm.quickScore(close.map { display($0, like: r.word) }, leadingSpace: leadingSpace)
        let rankedFixes = zip(close, quick).map { ($0, spatialOf(keyOf[$0]!) + $1) }.sorted { $0.1 > $1.1 }

        guard full else {
            // Bar while typing: completions and fixes on the quick estimate.
            // A completion one letter longer ("pomm" → "pomme") is also a
            // single-insertion fix, where it would pay the missed-tap cost and
            // drop below rarer, longer words. Score it as a completion.
            let longer = lexicon.completions(typedKey, limit: 12).map(\.word).filter { $0 != typed }
            let completing = Set(longer)
            let typedSpatial = spatialOf(typedKey)
            let quickLonger = lm.quickScore(longer.map { display($0, like: r.word) }, leadingSpace: leadingSpace)
            let pool = rankedFixes.filter { !completing.contains($0.0) }.prefix(6)
                + zip(longer, quickLonger).map { ($0, typedSpatial + $1) }
            let suggestions = pool.sorted { $0.1 > $1.1 }.map { display($0.0, like: r.word) }
                .filter { $0 != r.word }.prefix(3)
            return DecodeResult(word: r.word, correction: nil, suggestions: Array(suggestions),
                                log: "BAR \(r.word) \(Array(suggestions)) \(ms(started, Date()))ms")
        }
        let fixes = rankedFixes.prefix(Self.fullFixes).map(\.0)
        let completions: [String] = []
        let tRank = Date()

        let all = [typed] + fixes + completions
        let lmScores = lm.score(all.map { display($0, like: r.word) }, leadingSpace: leadingSpace)
        var total: [String: Float] = [:]
        for (i, w) in all.enumerated() {
            // Completions match the taps exactly as far as they go.
            let k = keyOf[w] ?? typedKey
            total[w] = spatialOf(k) + lmScores[i]
        }
        let tLM = Date()

        var correction: String?
        if r.autocorrect, let best = fixes.max(by: { total[$0]! < total[$1]! }) {
            let accentOnly = Lexicon.key(best) == typedKey
            var margin = typedIsWord ? Self.replaceRealWordMargin : Self.replaceTypoMargin
            // "a"/"à" is a coin flip the small model calls by only a nat or
            // so, and English context never favours "à": trust the lean.
            if accentOnly { margin = min(margin, typedKey.count == 1 ? 0.5 : Self.accentMargin) }
            // Two-letter "words" are often abbreviations or names: be surer.
            if typedKey.count == 2 && !accentOnly { margin += typedIsWord ? 2.5 : 1 }
            // A single letter only ever gets its accent ("a" → "à").
            if (typedKey.count >= 2 || accentOnly), total[best]! - total[typed]! > margin {
                correction = display(best, like: r.word)
            }
        }

        // Alternatives far behind the best guess are noise, not suggestions.
        let bestTotal = total.values.max() ?? 0
        // When a real word was typed, it's probably meant: only offer fixes
        // that are nearly as likely, so the bar leans on completions.
        let fixWindow = typedIsWord ? 3 : Self.suggestionWindow
        let suggestions = (fixes.filter { total[$0]! > bestTotal - fixWindow }
                           + completions.filter { total[$0]! > bestTotal - Self.suggestionWindow })
            .sorted { total[$0]! > total[$1]! }
            .map { display($0, like: r.word) }
            .filter { $0 != correction && $0 != r.word }
            .prefix(3)

        let top = all.sorted { total[$0]! > total[$1]! }.prefix(4)
            .map { "\($0)=\(String(format: "%.1f", total[$0]!))" }.joined(separator: " ")
        return DecodeResult(
            word: r.word, correction: correction, suggestions: Array(suggestions),
            log: "DECODE \(r.word)→\(correction ?? "-") [\(top)] \(ms(started, tLM))ms "
                + "(ctx \(ms(started, tContext)) gen \(ms(tContext, tGen))/\(keyOf.count) "
                + "rank \(ms(tGen, tRank)) lm \(ms(tRank, tLM))/\(all.count))")
    }

    // MARK: Candidates

    struct Generated {
        var taps: [Tap]
        var typedIsWord: Bool
        /// Candidate word -> its key (letters a-z) in the word list.
        var keyOf: [String: String]
        /// Key -> how well it fits the taps (nats), for every candidate key and the typed one.
        var spatial: [String: Float]
    }

    private func generate(_ r: DecodeRequest, typed: String, typedKey: String) -> Generated {
        let taps = Self.align(r.taps, to: typedKey, keys: r.keys)
        let typedIsWord = lexicon.lookup(typedKey).contains { $0.word == typed }

        // Real words the taps could have meant: a walk over the whole word
        // list, so several slips in one word are found, plus single edits
        // (swapped letters are cheap to type, costly in the walk).
        var spatial = search(taps, keys: r.keys, threshold: Self.worstSpatial)
        for (k, _) in spatial.sorted(by: { $0.value > $1.value }).dropFirst(Self.maxCandidates) {
            spatial[k] = nil
        }
        var keyOf: [String: String] = [:]
        for k in Set(spatial.keys).union(editKeys(typedKey, taps: taps, keys: r.keys)) {
            for e in lexicon.lookup(k) where e.word != typed && keyOf[e.word] == nil { keyOf[e.word] = k }
        }
        for (word, key) in elided(taps, keys: r.keys) where word != typed && keyOf[word] == nil {
            keyOf[word] = key
        }
        for k in Set(keyOf.values).union([typedKey]) where spatial[k] == nil {
            spatial[k] = Self.spatial(k, taps: taps, keys: r.keys)
        }
        return Generated(taps: taps, typedIsWord: typedIsWord, keyOf: keyOf, spatial: spatial)
    }

    /// For training the ranker offline: the typed word and every candidate the
    /// model would get to judge, each with its fit to the taps.
    func candidates(_ r: DecodeRequest) -> (typed: String, typedIsWord: Bool, words: [(String, Float)])? {
        let typed = r.word.lowercased()
        guard let typedKey = Lexicon.key(typed) else { return nil }
        let g = generate(r, typed: typed, typedKey: typedKey)
        let close = g.keyOf.compactMap { w, k in g.spatial[k].flatMap { $0 > Self.worstSpatial ? (w, $0) : nil } }
        return (typed, g.typedIsWord, [(typed, g.spatial[typedKey]!)] + close)
    }

    /// Every word-list key whose letters fit the taps with a spatial score
    /// of at least `threshold`, and that score. Same alignment as `spatial`,
    /// computed one letter at a time down the shared prefixes of the list.
    private func search(_ taps: [Tap], keys: KeyMap, threshold: Float) -> [String: Float] {
        let n = taps.count
        guard n > 0 else { return [:] }
        let e = Self.editCost
        // match[i * 26 + c]: how well tap i fits letter c.
        let sx = keys.keySize.width * Self.spread, sy = keys.keySize.height * Self.spread
        var match = [Float](repeating: -e, count: n * 26)
        for (i, tap) in taps.enumerated() {
            for c in 0..<26 {
                let letter = Character(UnicodeScalar(UInt8(97 + c)))
                if let p = tap.point, let center = keys.centers[letter] {
                    let dx = (p.x - center.x) / sx, dy = (p.y - center.y) / sy
                    match[i * 26 + c] = -Float(dx * dx + dy * dy) / 2
                } else if tap.letter == letter {
                    match[i * 26 + c] = 0
                }
            }
        }
        // rows[d * width + i]: best score for d letters against i taps.
        let maxDepth = n + 3, width = n + 1
        var rows = [Float](repeating: 0, count: (maxDepth + 1) * width)
        for i in 0...n { rows[i] = -e * Float(i) }
        var found: [String: Float] = [:]
        rows.withUnsafeMutableBufferPointer { rows in
            lexicon.walk(step: { d, byte in
                guard d < maxDepth, byte >= 97, byte <= 122 else { return false }
                let c = Int(byte) - 97
                let prev = d * width, cur = prev + width
                rows[cur] = rows[prev] - e
                var best = rows[cur]
                for i in stride(from: 1, through: n, by: 1) {
                    let v = max(rows[prev + i - 1] + match[(i - 1) * 26 + c],
                                rows[prev + i] - e, rows[cur + i - 1] - e)
                    rows[cur + i] = v
                    if v > best { best = v }
                }
                return best >= threshold
            }, found: { length, index in
                let score = rows[length * width + n]
                if score >= threshold { found[lexicon.key(at: index)] = score }
            })
        }
        return found
    }

    /// French elisions: "menvoyer" → "m'envoyer", "narive" → "n'arrive".
    /// The word list has the common ones ("c'est"); the rest are built from
    /// a prefix and any word starting with a vowel or h. Word → key.
    private func elided(_ taps: [Tap], keys: KeyMap) -> [String: String] {
        var out: [String: String] = [:]
        for prefix in Self.elisions where french && taps.count >= prefix.count + 2 {
            let head = Array(taps.prefix(prefix.count)), rest = Array(taps.dropFirst(prefix.count))
            let headScore = Self.spatial(prefix, taps: head, keys: keys)
            guard headScore > -3 else { continue }
            for (key, _) in search(rest, keys: keys, threshold: Self.worstSpatial - headScore) {
                // Common words only, 3+ letters: rarer ones made "s'he", "n'adige".
                for entry in lexicon.lookup(key) where entry.zipf >= 3 && key.count >= 3 {
                    guard let first = Lexicon.key(String(entry.word.prefix(1)))?.first,
                          "aeiouhy".contains(first), !entry.word.contains("'") else { continue }
                    out[prefix + "'" + entry.word] = prefix + key
                }
            }
        }
        return out
    }

    /// Keys one slip from `typed`: a neighbouring key, a missed tap, an
    /// extra tap, or two letters swapped.
    private func editKeys(_ typed: String, taps: [Tap], keys: KeyMap) -> Set<String> {
        let letters = Array(typed)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        let reach = max(keys.keySize.width, keys.keySize.height) * 1.6
        var out: Set<String> = [typed]

        for (i, tap) in taps.enumerated() where i < letters.count {
            let p = tap.point ?? keys.centers[letters[i]]
            for (key, center) in keys.centers where key != letters[i] {
                if let p, hypot(center.x - p.x, center.y - p.y) > reach { continue }
                var w = letters
                w[i] = key
                out.insert(String(w))
            }
        }
        if letters.count > 2 {
            for i in letters.indices {
                var w = letters
                w.remove(at: i)
                out.insert(String(w))
            }
        }
        if letters.count >= 2 {
            for i in 0...letters.count {
                for c in alphabet {
                    var w = letters
                    w.insert(c, at: i)
                    out.insert(String(w))
                }
            }
        }
        for i in letters.indices.dropLast() where letters[i] != letters[i + 1] {
            var w = letters
            w.swapAt(i, i + 1)
            out.insert(String(w))
        }
        return out
    }

    /// A word as it should appear: the typed word's capitals, and English "I".
    private func display(_ word: String, like typed: String) -> String {
        if word == "i" || word.hasPrefix("i'") { return "I" + word.dropFirst() }
        return Self.matchCase(of: typed, word)
    }

    private func ms(_ a: Date, _ b: Date) -> Int { Int(b.timeIntervalSince(a) * 1000) }

    // MARK: Spatial model

    /// Taps that match the typed key; when they don't (the cursor moved,
    /// text was pasted), pretend each letter was tapped dead center.
    static func align(_ taps: [Tap], to key: String, keys: KeyMap) -> [Tap] {
        let letters = Array(key)
        let tapKeys = taps.map { Lexicon.key(String($0.letter)).flatMap(\.first) }
        if taps.count == letters.count, zip(tapKeys, letters).allSatisfy({ $0 == $1 }) {
            return zip(taps, letters).map { tap, letter in
                Tap(letter: letter, point: tap.point ?? keys.centers[letter])
            }
        }
        return letters.map { Tap(letter: $0, point: keys.centers[$0]) }
    }

    /// How well a key (a-z letters) fits the taps: 0 is every tap dead
    /// center on the right key, about -2.5 is one tap squarely on a
    /// neighbour. An alignment, so a missed or extra tap costs `editCost`
    /// instead of shifting every letter after it.
    static func spatial(_ key: String, taps: [Tap], keys: KeyMap) -> Float {
        let letters = Array(key)
        let n = taps.count, m = letters.count
        guard n > 0 else { return 0 }
        let sx = keys.keySize.width * spread, sy = keys.keySize.height * spread

        func match(_ tap: Tap, _ c: Character) -> Float {
            guard let center = keys.centers[c], let p = tap.point else {
                return tap.letter == c ? 0 : -editCost
            }
            let dx = (p.x - center.x) / sx, dy = (p.y - center.y) / sy
            return -Float(dx * dx + dy * dy) / 2
        }

        var prev = [Float](repeating: 0, count: m + 1)
        for j in stride(from: 1, through: m, by: 1) { prev[j] = prev[j - 1] - editCost }
        for i in 1...n {
            var cur = [Float](repeating: 0, count: m + 1)
            cur[0] = prev[0] - editCost
            for j in stride(from: 1, through: m, by: 1) {
                cur[j] = max(prev[j - 1] + match(taps[i - 1], letters[j - 1]),
                             prev[j] - editCost,
                             cur[j - 1] - editCost)
            }
            prev = cur
        }
        return prev[m]
    }

    // MARK: Text helpers

    /// Splits the text before the word into the model's context and whether
    /// the word follows a space. "Je suis " → ("Je suis", true); "l'" → ("l'", false).
    static func split(_ before: String) -> (context: String, leadingSpace: Bool) {
        var context = String(before.suffix(300))
        let leadingSpace = context.last == " "
        while context.last == " " { context.removeLast() }
        return (context, leadingSpace)
    }

    /// Copies the typed word's capitals onto a candidate.
    static func matchCase(of typed: String, _ word: String) -> String {
        if typed.count > 1, typed == typed.uppercased(), typed != typed.lowercased() { return word.uppercased() }
        if typed.first?.isUppercase == true { return word.prefix(1).uppercased() + word.dropFirst() }
        return word
    }

}
