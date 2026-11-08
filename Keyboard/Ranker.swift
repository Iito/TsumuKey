import Foundation

/// Small candidate ranker that replaces Gemma for
/// correction: a few MB instead of ~100. It scores how well a word fits after
/// the context, on the same scale the decoder adds to the tap fit.
///
/// Words are hashed character n-grams (must match the model file), so
/// there's no vocabulary. Context: a 2-layer transformer over the last 8
/// tokens. Head: one of several small expert MLPs, picked per context by a
/// router (mixture of experts, top-1), or a single dense one.
final class Ranker: WordScorer {
    /// Multiplies every score (tuning knob for the bench).
    var weight: Float = 1
    var languages: [PredictionLanguage] = [.english, .french] {
        didSet { lastContext = nil; if languages != oldValue { predictionConstants.removeAll() } }
    }
    var lexicon: Lexicon? { didSet { predictionCache.removeAll(); predictionConstants.removeAll(); shortlistMask = nil } }
    private var predictionCache: [String: (projection: [Float], zipfs: [Float])] = [:]
    private var predictionConstants: [String: [Float]] = [:]
    private var predictionContext: [Float]?

    private let buckets, dim, layers, hidden, experts, ctxLen, maxNG, expertHidden, nFeat: Int
    private let hasShared: Bool
    private let embScale: [Float]
    private let emb: [Int8]
    private let pos, langW, langB: [Float]
    private struct Block { var n1w, n1b, qkvW, qkvB, oW, oB, n2w, n2b, f1W, f1B, f2W, f2B: [Float] }
    private let blocks: [Block]
    private let normW, normB, cprojW, cprojB, w1, b1, w2, b2, routerW, routerB: [Float]
    /// Always-on head of a shared-expert MoE (empty otherwise).
    private let sw1, sb1, sw2: [Float]
    private let sb2: Float

    private var lastContext: String?
    private var typed: (word: String, isWord: Bool)?

    func setTyped(_ word: String, isWord: Bool) { typed = (word, isWord) }
    private(set) var h: [Float] = []
    private var expert = 0

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url), data.count > 36, data.prefix(4) == Data("TKR3".utf8) else { return nil }
        var o = 4
        func u32() -> Int { defer { o += 4 }; return Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }
        buckets = u32(); dim = u32(); layers = u32(); hidden = u32(); experts = u32(); ctxLen = u32(); maxNG = u32()
        let bits = u32()
        hasShared = u32() == 1
        expertHidden = u32()
        nFeat = u32()
        func f16(_ n: Int) -> [Float] {
            defer { o += n * 2 }
            return data.withUnsafeBytes { raw in (0..<n).map { Float(raw.loadUnaligned(fromByteOffset: o + $0 * 2, as: Float16.self)) } }
        }
        embScale = f16(buckets)
        let n = buckets * dim
        if bits == 8 {
            emb = data.withUnsafeBytes { raw in (0..<n).map { raw.loadUnaligned(fromByteOffset: o + $0, as: Int8.self) } }
            o += n
        } else {
            // 6-bit: 4 values in 3 bytes, offset by 32.
            var e = [Int8](repeating: 0, count: n)
            data.withUnsafeBytes { raw in
                for g in 0..<(n / 4) {
                    let p = UInt32(raw[o + g * 3]) | UInt32(raw[o + g * 3 + 1]) << 8 | UInt32(raw[o + g * 3 + 2]) << 16
                    for j in 0..<4 { e[g * 4 + j] = Int8(Int((p >> (6 * UInt32(j))) & 63) - 32) }
                }
            }
            emb = e
            o += n / 4 * 3
        }
        let d = dim
        pos = f16(ctxLen * d); langW = f16(d * 4); langB = f16(d)
        var bs: [Block] = []
        for _ in 0..<layers {
            bs.append(Block(n1w: f16(d), n1b: f16(d), qkvW: f16(3 * d * d), qkvB: f16(3 * d), oW: f16(d * d), oB: f16(d),
                            n2w: f16(d), n2b: f16(d), f1W: f16(2 * d * d), f1B: f16(2 * d), f2W: f16(2 * d * d), f2B: f16(d)))
        }
        blocks = bs
        normW = f16(d); normB = f16(d); cprojW = f16(d * d); cprojB = f16(d)
        let nin = 3 * d + nFeat, ne = max(experts, 1)
        let eh = expertHidden
        w1 = f16(ne * nin * eh); b1 = f16(ne * eh); w2 = f16(ne * eh); b2 = f16(ne)
        if experts > 0 { routerW = f16(experts * d); routerB = f16(experts) } else { routerW = []; routerB = [] }
        if hasShared {
            sw1 = f16(nin * hidden); sb1 = f16(hidden); sw2 = f16(hidden); sb2 = f16(1)[0]
        } else {
            sw1 = []; sb1 = []; sw2 = []; sb2 = 0
        }
        guard o == data.count else { return nil }
    }

    // MARK: WordScorer

    @discardableResult
    func setContext(_ text: String) -> Bool {
        guard text != lastContext else { return true }
        lastContext = text
        predictionContext = nil
        let toks = Array((["<s>"] + Self.tokens(text)).suffix(ctxLen))
        let d = dim, pad = ctxLen - toks.count
        // x[t]: word vector + position; padding rows stay masked.
        var x = [Float](repeating: 0, count: ctxLen * d)
        for (i, t) in toks.enumerated() {
            let v = wordVector(t)
            for j in 0..<d { x[(pad + i) * d + j] = v[j] + pos[(pad + i) * d + j] }
        }
        for b in blocks { x = block(b, x, pad: pad) }
        let last = Array(x[(ctxLen - 1) * d..<ctxLen * d])
        var out = layerNorm(last, normW, normB)
        let bits = langBits()
        for j in 0..<d {
            var s = langB[j]
            for l in 0..<4 { s += langW[j * 4 + l] * bits[l] }
            out[j] += s
        }
        h = out
        if experts > 0 {
            var best = -Float.infinity
            for e in 0..<experts {
                var s = routerB[e]
                for j in 0..<d { s += routerW[e * d + j] * h[j] }
                if s > best { best = s; expert = e }
            }
        }
        return true
    }

    func score(_ words: [String], leadingSpace: Bool) -> [Float] {
        let d = dim, nin = 3 * d + nFeat, e = experts > 0 ? expert : 0
        let bits = langBits()
        return words.map { word in
            let w = word.lowercased().replacingOccurrences(of: "’", with: "'")
            let c: [Float]
            let z: [Float]
            if predicting, let cached = predictionCache[w] {
                c = cached.projection; z = cached.zipfs
            } else {
                let v = wordVector(w)
                var projection = cprojB
                for i in 0..<d {
                    var sum: Float = 0
                    for j in 0..<d { sum += cprojW[i * d + j] * v[j] }
                    projection[i] += sum
                }
                c = projection
                z = lexicon?.zipfs(of: w) ?? [0, 0, 0, 0]
                if predicting { predictionCache[w] = (c, z) }
            }
            var feats = [Float](repeating: 0, count: nFeat)
            var zmax: Float = 0
            for l in 0..<4 { feats[l] = z[l] * bits[l] / 8; zmax = max(zmax, z[l] * bits[l]) }
            feats[4] = zmax / 8; feats[5] = zmax == 0 ? 1 : 0
            if nFeat >= 8, let t = typed, w == t.word {
                feats[6] = 1; feats[7] = t.isWord ? 1 : 0
            }
            if nFeat == 9 { feats[8] = predicting ? 1 : 0 }  // task flag: suggesting, not correcting
            if predicting && experts == 0 && !hasShared {
                let base: [Float]
                if let existing = predictionConstants[w] {
                    base = existing
                } else {
                    var constant = b1
                    for i in 0..<d where c[i] != 0 {
                        let row = (d + i) * expertHidden
                        for k in 0..<expertHidden { constant[k] += c[i] * w1[row + k] }
                    }
                    for i in 0..<nFeat where feats[i] != 0 {
                        let row = (3 * d + i) * expertHidden
                        for k in 0..<expertHidden { constant[k] += feats[i] * w1[row + k] }
                    }
                    base = constant
                    predictionConstants[w] = constant
                }
                let ctx: [Float]
                if let existing = predictionContext {
                    ctx = existing
                } else {
                    var value = [Float](repeating: 0, count: expertHidden)
                    for i in 0..<d where h[i] != 0 {
                        let row = i * expertHidden
                        for k in 0..<expertHidden { value[k] += h[i] * w1[row + k] }
                    }
                    ctx = value
                    predictionContext = value
                }
                var a = base
                for k in 0..<expertHidden { a[k] += ctx[k] }
                for i in 0..<d {
                    let x = h[i] * c[i]
                    if x == 0 { continue }
                    let row = (2 * d + i) * expertHidden
                    for k in 0..<expertHidden { a[k] += x * w1[row + k] }
                }
                var result = b2[0]
                for k in 0..<expertHidden where a[k] > 0 { result += a[k] * w2[k] }
                return result * weight
            }
            var input = [Float](repeating: 0, count: nin)
            for j in 0..<d { input[j] = h[j]; input[d + j] = c[j]; input[2 * d + j] = h[j] * c[j] }
            for j in 0..<nFeat { input[3 * d + j] = feats[j] }
            var s = mlp(input, w1, b1, w2, b2[e], expert: e, hidden: expertHidden)
            if hasShared { s += mlp(input, sw1, sb1, sw2, sb2, expert: 0, hidden: hidden) }
            return s * weight
        }
    }

    func quickScore(_ words: [String], leadingSpace: Bool) -> [Float] { score(words, leadingSpace: leadingSpace) }

    /// Next-word suggestions: scores the most frequent words of the enabled
    /// languages after the context (models from v6 on; earlier ones give
    /// poor suggestions).
    func predict(count: Int, leadingSpace: Bool) -> [String] {
        guard let lexicon else { return [] }
        let mask = lexicon.languages
        // Round 10 on is trained with one or two languages enabled, so the list
        // is simply the most frequent words of whatever is on.
        if shortlistMask != mask {
            predictionCache.removeAll()
            predictionConstants.removeAll()
            shortlist = lexicon.completions("", limit: Self.shortlistSize).map(\.word)
            shortlistMask = mask
        }
        let saved = typed
        typed = nil  // nothing typed yet
        predicting = true
        let s = score(shortlist, leadingSpace: leadingSpace)
        predicting = false
        typed = saved
        return s.indices.sorted { s[$0] > s[$1] }.prefix(count).map { shortlist[$0] }
    }

    /// Words considered for suggestions (must match the model).
    static let shortlistSize = 2000
    private var shortlist: [String] = []
    private var shortlistMask: UInt8?
    private var predicting = false

    // MARK: Pieces

    /// relu(input · w1[e] + b1[e]) · w2[e] + b2, w1 laid out [expert][input][hidden].
    private func mlp(_ input: [Float], _ w1: [Float], _ b1: [Float], _ w2: [Float], _ b2: Float,
                     expert e: Int, hidden: Int) -> Float {
        let nin = input.count, base = e * nin * hidden
        var a = Array(b1[(e * hidden)..<((e + 1) * hidden)])
        for i in 0..<nin {
            let x = input[i]
            if x == 0 { continue }
            let row = base + i * hidden
            for k in 0..<hidden { a[k] += x * w1[row + k] }
        }
        var s = b2
        for k in 0..<hidden where a[k] > 0 { s += a[k] * w2[e * hidden + k] }
        return s
    }

    private func langBits() -> [Float] {
        PredictionLanguage.allCases.map { languages.contains($0) ? 1 : 0 }
    }

    /// Mean of the word's n-gram vectors (dequantized).
    private func wordVector(_ word: String) -> [Float] {
        let ids = Self.ngrams(word, buckets: buckets, max: maxNG)
        var v = [Float](repeating: 0, count: dim)
        for id in ids {
            let s = embScale[id]
            for j in 0..<dim { v[j] += Float(emb[id * dim + j]) * s }
        }
        let n = Float(max(ids.count, 1))
        return v.map { $0 / n }
    }

    private func block(_ b: Block, _ x: [Float], pad: Int) -> [Float] {
        let T = ctxLen, d = dim, heads = ModelStore.rankerHeads, hd = dim / heads
        var x = x
        var qkv = [Float](repeating: 0, count: T * 3 * d)
        for t in pad..<T {
            let n = layerNorm(Array(x[t * d..<(t + 1) * d]), b.n1w, b.n1b)
            for i in 0..<(3 * d) {
                var s = b.qkvB[i]
                for j in 0..<d { s += b.qkvW[i * d + j] * n[j] }
                qkv[t * 3 * d + i] = s
            }
        }
        // Layout per token: [q(heads*hd), k, v] as torch's view(B,T,3,H,hd).
        var att = [Float](repeating: 0, count: T * d)
        let scale = 1 / Float(hd).squareRoot()
        for t in pad..<T {
            for hh in 0..<heads {
                var w = [Float](repeating: 0, count: T)
                var m = -Float.infinity
                for u in pad..<T {
                    var s: Float = 0
                    for j in 0..<hd { s += qkv[t * 3 * d + hh * hd + j] * qkv[u * 3 * d + d + hh * hd + j] }
                    w[u] = s * scale; m = max(m, w[u])
                }
                var sum: Float = 0
                for u in pad..<T { w[u] = exp(w[u] - m); sum += w[u] }
                for u in pad..<T {
                    let p = w[u] / sum
                    for j in 0..<hd { att[t * d + hh * hd + j] += p * qkv[u * 3 * d + 2 * d + hh * hd + j] }
                }
            }
        }
        for t in pad..<T {
            for i in 0..<d {
                var s = b.oB[i]
                for j in 0..<d { s += b.oW[i * d + j] * att[t * d + j] }
                x[t * d + i] += s
            }
            let n = layerNorm(Array(x[t * d..<(t + 1) * d]), b.n2w, b.n2b)
            var f = [Float](repeating: 0, count: 2 * d)
            for i in 0..<(2 * d) {
                var s = b.f1B[i]
                for j in 0..<d { s += b.f1W[i * d + j] * n[j] }
                f[i] = max(s, 0)
            }
            for i in 0..<d {
                var s = b.f2B[i]
                for j in 0..<(2 * d) { s += b.f2W[i * 2 * d + j] * f[j] }
                x[t * d + i] += s
            }
        }
        return x
    }

    private func layerNorm(_ v: [Float], _ w: [Float], _ b: [Float]) -> [Float] {
        let n = Float(v.count)
        let mean = v.reduce(0, +) / n
        let variance = v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let r = 1 / (variance + 1e-5).squareRoot()
        return v.indices.map { (v[$0] - mean) * r * w[$0] + b[$0] }
    }

    // MARK: Hashing (must match the model file)

    static func fnv1a(_ s: String) -> UInt32 {
        var h: UInt32 = 0x811C9DC5
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 0x01000193 }
        return h
    }

    static func ngrams(_ word: String, buckets: Int, max: Int) -> [Int] {
        let w = Array("<" + word + ">")
        var out = [Int(fnv1a("W" + word) % UInt32(buckets))]
        for n in 2...4 where w.count >= n {
            for i in 0...(w.count - n) { out.append(Int(fnv1a(String(w[i..<i + n])) % UInt32(buckets))) }
        }
        return Array(out.prefix(max))
    }

    /// Lowercased words (letters with inner apostrophes) and . , ! ? ; :
    static func tokens(_ text: String) -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(text.lowercased().replacingOccurrences(of: "’", with: "'"))
        for (i, c) in chars.enumerated() {
            if c.isLetter {
                cur.append(c)
            } else if c == "'", !cur.isEmpty, i + 1 < chars.count, chars[i + 1].isLetter {
                cur.append(c)
            } else {
                if !cur.isEmpty { out.append(cur); cur = "" }
                if ".,!?;:".contains(c) { out.append(String(c)) }
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
