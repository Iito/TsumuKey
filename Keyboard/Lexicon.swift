import Foundation

/// English/French/German/Spanish word list with per-language frequencies
/// (from wordfreq). `languages` picks which ones count: words
/// of the others are invisible, and shared words rank by the enabled ones.
///
/// Words are filed under their key: plain a-z, no accents or apostrophes.
/// Looking up what the fingers spelled ("tres", "dont") returns every real
/// spelling ("très"; "don't" and French "dont"). Memory-mapped and searched
/// in place, so it costs almost no RAM and each lookup takes microseconds.
final class Lexicon {
    struct Entry {
        let word: String
        /// Zipf frequency: log10 of uses per billion words (~1 rare, 7 "the").
        let zipf: Float
    }

    private let data: Data
    private let count: Int
    /// Frequencies stored per word: 4 in BKW2, any number in BKW3.
    let languageCount: Int
    /// Bit i on = language i (PredictionLanguage order) is used. Only touch
    /// it from the queue that reads the lexicon.
    var languages: UInt8 = 0b11
    private let keyOffsets: Int, wordOffsets: Int, zipfs: Int, keys: Int, words: Int

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count > 8,
              ["BKW2", "BKW3"].contains(String(decoding: data.prefix(4), as: UTF8.self)) else { return nil }
        let read = { (offset: Int) in Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }) }
        let count = read(4)
        // BKW3 adds u32 language count after the word count.
        let v3 = data[data.startIndex + 3] == UInt8(ascii: "3")
        let header = v3 ? 12 : 8
        languageCount = v3 ? read(8) : 4
        let wordOffsets = header + (count + 1) * 4
        let zipfs = wordOffsets + (count + 1) * 4
        self.data = data
        self.count = count
        keyOffsets = header
        self.wordOffsets = wordOffsets
        self.zipfs = zipfs
        keys = zipfs + count * languageCount
        // The last key offset is the keys blob's length.
        words = keys + read(wordOffsets - 4)
    }

    /// Every spelling filed under `key`, most frequent first.
    func lookup(_ key: String) -> [Entry] {
        let k = Array(key.utf8)
        var i = lowerBound(k)
        var out: [Entry] = []
        while i < count, compare(i, k) == 0 {
            if zipfByte(i) > 0 { out.append(entry(i)) }
            i += 1
        }
        // Sorted by frequency in any language; re-sort for the enabled ones.
        return out.count > 1 ? out.sorted { $0.zipf > $1.zipf } : out
    }

    /// Frequency of this exact spelling in each language (PredictionLanguage
    /// order), whatever is enabled; zeros when it isn't in the list.
    func zipfs(of word: String) -> [Float] {
        guard let key = Self.key(word) else { return [Float](repeating: 0, count: languageCount) }
        let k = Array(key.utf8)
        var i = lowerBound(k)
        while i < count, compare(i, k) == 0 {
            let start = words + u32(wordOffsets + i * 4), end = words + u32(wordOffsets + (i + 1) * 4)
            let w = data.withUnsafeBytes { String(decoding: $0[start..<end], as: UTF8.self) }
            if w == word {
                let base = data.startIndex + zipfs + i * languageCount
                return (0..<languageCount).map { Float(data[base + $0]) / 10 }
            }
            i += 1
        }
        return [Float](repeating: 0, count: languageCount)
    }

    /// `languages`: a mask other than `self.languages` (suggestions use the
    /// model's two languages while corrections search more).
    func contains(_ key: String, languages mask: UInt8? = nil) -> Bool {
        let k = Array(key.utf8)
        var i = lowerBound(k)
        while i < count, compare(i, k) == 0 {
            if zipfByte(i, mask ?? languages) > 0 { return true }
            i += 1
        }
        return false
    }

    /// The most frequent words whose key starts with `prefix` (longer than it).
    func completions(_ prefix: String, limit: Int, languages mask: UInt8? = nil) -> [Entry] {
        let p = Array(prefix.utf8)
        var i = lowerBound(p)
        var best: [(index: Int, zipf: UInt8)] = []
        // Short prefixes match thousands of words; frequencies are one byte
        // each, so scanning them all is still only microseconds.
        while i < count, hasPrefix(i, p) {
            let z = zipfByte(i, mask ?? languages)
            if z > 0, keyLength(i) > p.count, best.count < limit || z > best[best.count - 1].zipf {
                if best.count == limit { best.removeLast() }
                let at = best.firstIndex { $0.zipf < z } ?? best.count
                best.insert((i, z), at: at)
            }
            i += 1
        }
        return best.map { entry($0.index, mask ?? languages) }
    }

    /// Visits every distinct key in sorted order, like walking a trie:
    /// keys sharing a prefix share the work, and a pruned prefix skips every
    /// key under it. `step(depth, byte)` extends the prefix by one letter and
    /// returns false to prune; `found(length)` reports a key that survived,
    /// whose text is `key(at:)` of the index passed alongside.
    func walk(step: (Int, UInt8) -> Bool, found: (Int, Int) -> Void) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var path: [UInt8] = []
            var i = 0
            while i < count {
                let r = keyRange(i)
                let key = raw[r]
                var lcp = 0
                while lcp < path.count, lcp < key.count, path[lcp] == key[key.startIndex + lcp] { lcp += 1 }
                path.removeLast(path.count - lcp)
                var pruned = -1
                for d in lcp..<key.count {
                    let byte = key[key.startIndex + d]
                    if step(d, byte) { path.append(byte) } else { pruned = d; break }
                }
                if pruned >= 0 {
                    // Jump past every key starting with the pruned prefix.
                    var next = Array(key.prefix(pruned + 1))
                    next[pruned] += 1
                    i = lowerBound(next)
                    continue
                }
                found(key.count, i)
                i += 1
                while i < count, raw[keyRange(i)].elementsEqual(key) { i += 1 }
            }
        }
    }

    /// The key (a-z letters) of entry `i`.
    func key(at i: Int) -> String {
        data.withUnsafeBytes { String(decoding: $0[keyRange(i)], as: UTF8.self) }
    }

    /// The key for any spelling: "Très" → "tres", "don't" → "dont", "œuvre" → "oeuvre".
    /// Nil if it has characters no key can type (digits, symbols).
    static func key(_ word: String) -> String? {
        var w = word.lowercased()
        if w.contains(where: { "œæß".contains($0) }) {
            w = w.replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "æ", with: "ae")
                .replacingOccurrences(of: "ß", with: "ss")
        }
        w = w.folding(options: .diacriticInsensitive, locale: nil)
        w.removeAll { $0 == "'" || $0 == "’" || $0 == "-" }
        return !w.isEmpty && w.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) ? w : nil
    }

    // MARK: Binary layout

    private func u32(_ offset: Int) -> Int {
        Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) })
    }
    private func keyRange(_ i: Int) -> Range<Int> {
        (keys + u32(keyOffsets + i * 4))..<(keys + u32(keyOffsets + (i + 1) * 4))
    }
    private func keyLength(_ i: Int) -> Int { keyRange(i).count }
    /// Highest frequency among the enabled languages; 0 when it's a word
    /// in none of them.
    private func zipfByte(_ i: Int, _ mask: UInt8? = nil) -> UInt8 {
        let mask = mask ?? languages
        let base = data.startIndex + zipfs + i * languageCount
        var best: UInt8 = 0
        for l in 0..<languageCount where mask & (1 << l) != 0 { best = max(best, data[base + l]) }
        return best
    }

    private func entry(_ i: Int, _ mask: UInt8? = nil) -> Entry {
        let start = words + u32(wordOffsets + i * 4), end = words + u32(wordOffsets + (i + 1) * 4)
        let word = data.withUnsafeBytes { String(decoding: $0[start..<end], as: UTF8.self) }
        return Entry(word: word, zipf: Float(zipfByte(i, mask)) / 10)
    }

    /// Byte order comparison of entry i's key with `k`.
    private func compare(_ i: Int, _ k: [UInt8]) -> Int {
        let r = keyRange(i)
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            var a = r.lowerBound, b = 0
            while a < r.upperBound, b < k.count {
                let x = raw[a], y = k[b]
                if x != y { return x < y ? -1 : 1 }
                a += 1; b += 1
            }
            return (r.upperBound - a) - (k.count - b) == 0 ? 0 : (a < r.upperBound ? 1 : -1)
        }
    }

    private func hasPrefix(_ i: Int, _ p: [UInt8]) -> Bool {
        let r = keyRange(i)
        guard r.count >= p.count else { return false }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            for (j, byte) in p.enumerated() where raw[r.lowerBound + j] != byte { return false }
            return true
        }
    }

    private func lowerBound(_ k: [UInt8]) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if compare(mid, k) < 0 { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
