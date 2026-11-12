import Foundation

/// Small language detector (Models/langid.tkl, 26 Latin-script European
/// languages): hashed letter groups of each word, one fp16 weight per
/// (bucket, language), read straight from the memory-mapped file (3.4 MB, a
/// few µs per word). No NaturalLanguage dependency.
final class LangDetector {
    let languages: [String]
    let temperature: Float
    private let data: Data
    private let buckets: Int, count: Int, maxN: Int
    private let biasOffset: Int, weightOffset: Int

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count > 20,
              d.prefix(4) == Data("TKL1".utf8) else { return nil }
        data = d
        func u32(_ o: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }
        buckets = u32(4)
        count = u32(8)
        maxN = u32(12)
        temperature = d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: Float.self) }
        languages = (0 ..< count).map { i in
            String(decoding: d[(20 + 4 * i) ..< (24 + 4 * i)].prefix { $0 != 0 }, as: UTF8.self)
        }
        biasOffset = 20 + 4 * count
        weightOffset = biasOffset + 2 * count
        guard d.count == weightOffset + 2 * buckets * count else { return nil }
    }

    /// Log-probability of each language for one word. Letter groups are taken
    /// over Unicode scalars, as Python iterates a string, so hashes match.
    func wordLogProbs(_ word: String) -> [Float] {
        let w = word.lowercased()
        var z = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            for l in 0 ..< count { z[l] = Float(raw.loadUnaligned(fromByteOffset: biasOffset + 2 * l, as: Float16.self)) }
            func add(_ h: UInt32) {
                let row = weightOffset + Int(h % UInt32(buckets)) * count * 2
                for l in 0 ..< count { z[l] += Float(raw.loadUnaligned(fromByteOffset: row + 2 * l, as: Float16.self)) }
            }
            add(Ranker.fnv1a("W" + w))
            let s = Array(("<" + w + ">").unicodeScalars)
            for n in 1 ... maxN where s.count >= n {
                for i in 0 ... (s.count - n) {
                    var piece = String.UnicodeScalarView()
                    piece.append(contentsOf: s[i ..< i + n])
                    add(Ranker.fnv1a(String(piece)))
                }
            }
        }
        let m = z.max() ?? 0
        let lse = m + log(z.reduce(0) { $0 + exp($1 - m) })
        return z.map { $0 - lse }
    }

    /// Probability of each language over a window of words, from their
    /// per-word log-probabilities (the keyboard keeps these per finished word).
    func windowProbs(_ perWord: [[Float]]) -> [Float] {
        var z = [Float](repeating: 0, count: count)
        for lp in perWord { for l in 0 ..< count { z[l] += temperature * lp[l] } }
        let m = z.max() ?? 0
        let e = z.map { exp($0 - m) }
        let s = e.reduce(0, +)
        return e.map { $0 / s }
    }

    /// Words as the training script splits them.
    static func words(_ sentence: String) -> [String] {
        let edge = CharacterSet(charactersIn: ".,!?;:\"«»„“”()[]¿¡…—–-")
        return sentence.lowercased().split(separator: " ").compactMap { t -> String? in
            let w = t.trimmingCharacters(in: edge)
            return !w.isEmpty && w.contains(where: \.isLetter) && !w.contains(where: \.isNumber) ? w : nil
        }
    }
}

/// The languages of the user's recent words, carried across sentences and
/// text fields: each finished word's log-probabilities added to a sum that
/// decays by `decay` per word (~12 words of memory). Only these 26 numbers
/// are kept, never the words. The last 5 words alone let one ambiguous word
/// swap a session's second language (French slipping into DE+EN typing).
struct LangTracker: Codable {
    var score: [Float] = []
    var words = 0
    static let decay: Float = 0.92

    mutating func add(_ logProbs: [Float]) {
        if score.count != logProbs.count { score = logProbs; words = 1; return }
        for i in score.indices { score[i] = score[i] * Self.decay + logProbs[i] }
        words += 1
    }

    /// `known` best first; nil until two words have been seen.
    func ranked(_ detector: LangDetector, among known: [PredictionLanguage] = PredictionLanguage.allCases) -> [PredictionLanguage]? {
        guard words >= 2, score.count == detector.languages.count else { return nil }
        let scored = known.compactMap { lang in detector.languages.firstIndex(of: lang.rawValue).map { (lang, score[$0]) } }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

extension LangDetector {
    /// The prediction languages the last 5 words of `text` read as, best
    /// first; nil with fewer than 2 words. (The keyboard uses LangTracker,
    /// which carries over between sentences; this is the per-text view.)
    func detect(_ text: String, among known: [PredictionLanguage] = PredictionLanguage.allCases) -> [PredictionLanguage]? {
        let words = Self.words(text).suffix(5)
        guard words.count >= 2 else { return nil }
        let p = windowProbs(words.map(wordLogProbs))
        let scored = known.compactMap { lang in languages.firstIndex(of: lang.rawValue).map { (lang, p[$0]) } }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }
}
