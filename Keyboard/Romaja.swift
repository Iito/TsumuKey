import Foundation

/// Romanised Korean typed on the Latin keyboard → the Hangul word, for the
/// red chip in the ABC bar ("annyeong" → 안녕, "gamsahamnida" → 감사합니다).
///
/// Every word in the Korean word list is romanised twice: syllable by
/// syllable (gamsahabnida) and as pronounced, with Revised Romanization's
/// sound changes (gamsahamnida). Both sides are then loosened the same way,
/// since people spell romaja loosely: g/k, d/t, b/p, r/l and j/ch merge, eo
/// counts as o, eu as u, ae as e, and doubled letters as single.
enum Romaja {
    static let initials = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
    static let medials = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"]
    /// Each final as written letter by letter, and as pronounced at the end of a syllable.
    static let finalsWritten = ["", "g", "kk", "gs", "n", "nj", "nh", "d", "l", "lg", "lm", "lb", "ls", "lt", "lp", "lh", "m", "b", "bs", "s", "ss", "ng", "j", "ch", "k", "t", "p", "h"]
    static let finalsSaid = ["", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "l", "l", "l", "p", "l", "m", "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "t"]
    /// The consonant a final hands to the next syllable when it starts with ㅇ (liaison).
    static let finalsCarried = ["", "g", "kk", "ks", "n", "nj", "n", "d", "r", "lg", "lm", "lb", "ls", "lt", "lp", "r", "m", "b", "bs", "s", "ss", "ng", "j", "ch", "k", "t", "p", ""]

    /// A key's sound for the phonetic overlay: ㄱ → g, ㅓ → eo, ㅇ → ng.
    static func letter(for jamo: Character) -> String? {
        if jamo == "ㅇ" { return "ng" }
        if let i = HangulComposer.initials.firstIndex(of: jamo) { return initials[i] }
        if let i = HangulComposer.medials.firstIndex(of: jamo) { return medials[i] }
        return nil
    }

    /// Both romanisations of a Hangul word (nil if it isn't all syllables).
    static func romanize(_ word: String) -> [String] {
        var parts: [(l: Int, v: Int, t: Int)] = []
        for scalar in word.unicodeScalars {
            let i = Int(scalar.value) - 0xAC00
            guard (0..<11172).contains(i) else { return [] }
            parts.append((i / 588, (i / 28) % 21, i % 28))
        }
        var written = "", said = ""
        for (k, p) in parts.enumerated() {
            written += initials[p.l] + medials[p.v] + finalsWritten[p.t]
            let next = k + 1 < parts.count ? parts[k + 1].l : nil
            var initial = initials[p.l]
            if k > 0, p.l == 11 { initial = "" }  // ㅇ: silent (a carried final fills it)
            said += initial + medials[p.v]
            guard p.t > 0 else { continue }
            switch next {
            case 11?:                      // liaison: 음악 eumak
                said += finalsCarried[p.t]
            case 2?, 6?:                   // before ㄴ ㅁ: k t p → ng n m (합니다 hamnida)
                let s = finalsSaid[p.t]
                said += s == "k" ? "ng" : s == "t" ? "n" : s == "p" ? "m" : s == "l" && next == 2 ? "l" : s
            case 5?:                       // before ㄹ: ㄴ → l (신라 silla)
                let s = finalsSaid[p.t]
                said += s == "n" ? "l" : s
            default:
                said += finalsSaid[p.t]
            }
        }
        return written == said ? [written] : [written, said]
    }

    /// The loose form both sides are compared in.
    static func loosen(_ s: String) -> String {
        var t = s.lowercased().filter { $0.isASCII && $0.isLetter }
        for (a, b) in [("ch", "c"), ("sh", "s"), ("eo", "o"), ("eu", "u"), ("ae", "e")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        let merge: [Character: Character] = ["g": "k", "d": "t", "b": "p", "r": "l", "j": "c", "f": "p", "z": "c"]
        var out = ""
        for c in t {
            let m = merge[c] ?? c
            if out.last != m { out.append(m) }  // doubled letters count once
        }
        return out
    }
}

extension KoreanWords {
    /// The most common Korean word the romaja could spell, or nil.
    func fromRomaja(_ latin: String) -> String? {
        guard isLoaded, latin.count >= 2, latin.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return romajaIndex[Romaja.loosen(latin)]
    }
}
