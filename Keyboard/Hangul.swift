import Foundation

/// Dubeolsik (2-set) Hangul: jamo typed one by one, assembled into syllables
/// as you go, like the iOS Korean keyboard. "ㅎㅏㄴㄱㅡㄹ" → 한글.
///
/// The keyboard only rewrites the syllable being built (the "block"): each
/// jamo returns how many characters to delete before the cursor and what to
/// insert instead. A vowel after a final consonant moves that consonant (or
/// the second half of a double final) into a new syllable: 갑 + ㅏ → 가바.
struct HangulComposer {
    /// Choseong, jungseong and jongseong in Unicode's syllable order.
    static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let medials = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let finals: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map { $0 }

    static let compoundVowels: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ",
    ]
    static let compoundFinals: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ",
        "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
    ]
    /// Shift on the top row: tense consonants and ㅒ ㅖ.
    static let shifted: [String: String] = ["ㅂ": "ㅃ", "ㅈ": "ㅉ", "ㄷ": "ㄸ", "ㄱ": "ㄲ", "ㅅ": "ㅆ", "ㅐ": "ㅒ", "ㅔ": "ㅖ"]

    static func isJamo(_ c: Character) -> Bool { isConsonant(c) || isVowel(c) }
    static func isConsonant(_ c: Character) -> Bool { initials.contains(c) }
    static func isVowel(_ c: Character) -> Bool { medials.contains(c) }

    /// One syllable in progress. Any part can be missing: a lone consonant
    /// or vowel shows as the jamo itself.
    struct Syllable: Equatable {
        var initial: Character?
        var medial: Character?
        var final: Character?

        var text: String {
            guard let medial else {
                return initial.map(String.init) ?? ""
            }
            guard let initial,
                  let l = HangulComposer.initials.firstIndex(of: initial),
                  let v = HangulComposer.medials.firstIndex(of: medial) else {
                return String(medial)   // vowel with no consonant before it
            }
            let t = HangulComposer.finals.firstIndex(of: final) ?? 0
            return String(UnicodeScalar(0xAC00 + (l * 21 + v) * 28 + t)!)
        }
    }

    /// The block being built, and every state it went through (for backspace).
    private(set) var history: [Syllable] = []
    var current: Syllable? { history.last }
    /// What the block looks like in the document right now.
    var text: String { current?.text ?? "" }
    var isEmpty: Bool { history.isEmpty }

    mutating func reset() { history = [] }

    /// Types one jamo. Returns the edit to make: delete `delete` characters
    /// before the cursor, then insert `insert`.
    mutating func type(_ jamo: Character) -> (delete: Int, insert: String) {
        let before = text.count
        guard var s = current else {
            history = [start(jamo)]
            return (0, text)
        }
        let consonant = Self.isConsonant(jamo)
        switch (s.initial, s.medial, s.final) {
        case (_, nil, _):
            // A lone consonant: a vowel joins it, another consonant starts anew.
            if consonant { return finish(start: jamo, before: before) }
            s.medial = jamo
        case (nil, let v?, _):
            // A lone vowel: only a compound vowel continues it.
            guard !consonant, let joined = Self.compoundVowels["\(v)\(jamo)"] else {
                return finish(start: jamo, before: before)
            }
            s.medial = joined
        case (_, let v?, nil):
            if consonant {
                // ㄸ ㅃ ㅉ never end a syllable.
                guard Self.finals.contains(jamo) else { return finish(start: jamo, before: before) }
                s.final = jamo
            } else {
                guard let joined = Self.compoundVowels["\(v)\(jamo)"] else {
                    return finish(start: jamo, before: before)
                }
                s.medial = joined
            }
        case (_, _, let f?):
            if consonant {
                guard let joined = Self.compoundFinals["\(f)\(jamo)"] else {
                    return finish(start: jamo, before: before)
                }
                s.final = joined
            } else {
                // The final consonant moves on to start the next syllable.
                var kept = s
                let moved: Character
                if let pair = Self.compoundFinals.first(where: { $0.value == f })?.key {
                    kept.final = pair.first
                    moved = pair.last!
                } else {
                    kept.final = nil
                    moved = f
                }
                let next = Syllable(initial: moved, medial: jamo, final: nil)
                history = [Syllable(initial: moved), next]
                return (before, kept.text + next.text)
            }
        }
        history.append(s)
        return (before, s.text)
    }

    /// Backspace inside the block: back to the previous state. Nil when the
    /// block is empty (the keyboard then deletes normally).
    mutating func backspace() -> (delete: Int, insert: String)? {
        guard !history.isEmpty else { return nil }
        let before = text.count
        history.removeLast()
        return (before, text)
    }

    private func start(_ jamo: Character) -> Syllable {
        Self.isConsonant(jamo) ? Syllable(initial: jamo) : Syllable(medial: jamo)
    }

    /// The block is done; `jamo` starts the next one.
    private mutating func finish(start jamo: Character, before: Int) -> (delete: Int, insert: String) {
        history = [start(jamo)]
        return (0, text)
    }
}

extension HangulComposer {
    /// Typing-order jamo of a Hangul string: 왔 → ㅇㅗㅏㅆ, 닭 → ㄷㅏㄹㄱ. Lets a
    /// syllable still being typed match: 안 (ㅇㅏㄴ) is a prefix of 아니 (ㅇㅏㄴㅣ).
    static func jamoKey(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            let v = Int(scalar.value)
            guard (0xAC00...0xD7A3).contains(v) else {
                out += split(Character(scalar))
                continue
            }
            let i = v - 0xAC00
            out.append(initials[i / (21 * 28)])
            out += split(medials[(i / 28) % 21])
            if let f = finals[i % 28] { out += split(f) }
        }
        return out
    }

    /// The Dubeolsik key each jamo sits on, named by its QWERTY letter.
    /// Tense consonants and ㅒ ㅖ share their unshifted key.
    static let qwerty: [Character: Character] = {
        var map = Dictionary(uniqueKeysWithValues: zip("ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡ", "qwertyuiopasdfghjklzxcvbnm"))
        for (tense, plain) in zip("ㅃㅉㄸㄲㅆㅒㅖ", "ㅂㅈㄷㄱㅅㅐㅔ") { map[tense] = map[plain] }
        return map
    }()

    /// The keys a Hangul word is typed on, as QWERTY letters: 안녕 → "dkssud".
    /// How the Korean word list files its words, so the touch-aware decoder
    /// reads Korean taps like Latin ones. Nil for anything but Hangul.
    static func qwertyKey(_ word: String) -> String? {
        let keys = jamoKey(word).compactMap { qwerty[$0] }
        return keys.isEmpty || keys.count != jamoKey(word).count ? nil : String(keys)
    }

    /// Compound vowels and finals as their typed parts (ㅘ → ㅗㅏ, ㄺ → ㄹㄱ).
    private static func split(_ c: Character) -> String {
        if let pair = compoundVowels.first(where: { $0.value == c })?.key { return pair }
        if let pair = compoundFinals.first(where: { $0.value == c })?.key { return pair }
        return String(c)
    }
}

/// Korean word list for completions on the Hangul keyboards (Models/words-ko.txt:
/// whole words with their counts, from OpenSubtitles via FrequencyWords).
/// Loaded on first use, only while a Hangul keyboard is up.
final class KoreanWords {
    static let shared = KoreanWords()
    private var entries: [(key: String, word: String, count: Int)] = []
    private(set) var isLoaded = false
    /// Loose romaja → the most common word with that spelling (Romaja.swift).
    private(set) var romajaIndex: [String: String] = [:]

    func load(from url: URL? = Bundle.main.url(forResource: "words-ko", withExtension: "txt")) {
        guard !isLoaded, let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        entries = text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let count = Int(parts[1]) else { return nil }
            let word = String(parts[0])
            return (HangulComposer.jamoKey(word), word, count)
        }.sorted { $0.key < $1.key }
        // Most common first, so the first word to claim a spelling keeps it.
        var index: [String: String] = [:]
        for e in entries.sorted(by: { $0.count > $1.count }) {
            for form in Romaja.romanize(e.word) {
                let key = Romaja.loosen(form)
                if index[key] == nil { index[key] = e.word }
            }
        }
        romajaIndex = index
        isLoaded = true
    }

    func unload() {
        entries = []
        romajaIndex = [:]
        isLoaded = false
    }

    /// The most frequent words starting with what was typed (by jamo), the
    /// typed word itself excluded.
    func complete(_ typed: String, count: Int = 3) -> [String] {
        guard isLoaded, !typed.isEmpty else { return [] }
        let key = HangulComposer.jamoKey(typed)
        var lo = 0, hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].key < key { lo = mid + 1 } else { hi = mid }
        }
        var best: [(word: String, count: Int)] = []
        var i = lo
        while i < entries.count, entries[i].key.hasPrefix(key) {
            let e = entries[i]
            // Words that keep the syllables as typed come first: 안 → 안녕
            // before 아니 (whose ㄴ only matches the jamo).
            if e.word != typed { best.append((e.word, e.word.hasPrefix(typed) ? e.count * 8 : e.count)) }
            i += 1
        }
        return best.sorted { $0.count > $1.count }.prefix(count).map(\.word)
    }
}
