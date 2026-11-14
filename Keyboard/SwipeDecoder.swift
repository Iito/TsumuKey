import CoreGraphics
import Foundation

/// A swipe: the finger's path across the letter keys, in key-map coordinates.
struct SwipeRequest {
    /// Everything before the swiped word (a space is added before it when needed).
    var before: String
    var path: [CGPoint]
    var keys: KeyMap
}

struct SwipeResult {
    /// Best first.
    var words: [String]
    var log: String
}

/// Swipe typing ("shape writing"): every word has an ideal path, from key
/// center to key center. A word fits a swipe when its letters lie along the
/// finger's path in order, starting where the finger landed and ending where
/// it lifted, and when its ideal path has the same shape. The model then
/// weighs the close fits by context, like it does for taps.
extension WordDecoder {
    /// Spread of the path around a key it passes, as a fraction of the key
    /// size: swipes are looser than taps.
    static var swipeSpread: CGFloat = 0.45
    /// Weight of the shape check (ideal path vs the finger's), per key width
    /// squared of mean distance.
    static var swipeShapeWeight: Float = 10
    /// Weight of the model's context score against the path and shape fit.
    static var swipeModelWeight: Float = 1
    /// Letters off the path cost more than this (nats), plus `swipeWorstPerLetter`
    /// for each letter: stop following the word. Small slips add up in long words.
    static var swipeWorst: Float = 8
    static var swipeWorstPerLetter: Float = 1.5
    /// How many path fits get the shape check, and how many of those the model.
    static let swipeShapeCandidates = 1500
    static let swipeModelCandidates = 24

    func swipe(_ r: SwipeRequest) -> SwipeResult {
        let started = Date()
        let samples = Self.resample(r.path, step: r.keys.keySize.width / 3, maxCount: 80)
        guard samples.count >= 2 else { return SwipeResult(words: [], log: "SWIPE too short") }
        let (context, leadingSpace) = Self.split(r.before)
        lm.setContext(context)
        lm.setTyped("", isWord: false)

        // 1. Words whose letters lie along the path, in order.
        let fits = followPath(samples, keys: r.keys)
        let tWalk = Date()

        // 2. Shape: the word's ideal path against the finger's. Short words
        // fit the path best (fewer letters to pay for), so the cheap filter
        // is length: an ideal path much shorter or longer isn't this swipe.
        let shape = Self.resample(samples, count: 32)
        let w = r.keys.keySize.width, h = r.keys.keySize.height
        let swiped = Self.length(samples)
        var spatial: [(key: String, score: Float)] = fits.compactMap { key, fit -> (String, [CGPoint], Float)? in
                let ideal = Self.dedupe(key.compactMap { r.keys.centers[$0] })
                let length = Self.length(ideal)
                guard length < swiped * 1.6 + w, length > swiped * 0.6 - w else { return nil }
                return (key, ideal, fit)
            }
            .sorted { $0.2 > $1.2 }.prefix(Self.swipeShapeCandidates).map { key, ideal, fit in
                let template = Self.resample(ideal, count: 32)
                var sum: Float = 0
                for (a, b) in zip(shape, template) {
                    let dx = (a.x - b.x) / w, dy = (a.y - b.y) / h
                    sum += Float(dx * dx + dy * dy)
                }
                return (key, fit - Self.swipeShapeWeight * sum / Float(shape.count))
            }
        spatial.sort { $0.score > $1.score }
        let tShape = Date()

        // 3. Context: every spelling of the best keys, scored by the model.
        var words: [(word: String, spatial: Float)] = []
        for (key, score) in spatial.prefix(Self.swipeModelCandidates) {
            for e in lexicon.lookup(key).prefix(3) { words.append((e.word, score)) }
        }
        guard !words.isEmpty else {
            return SwipeResult(words: [], log: "SWIPE no fit (\(samples.count) samples) \(swipeMs(started))ms")
        }
        let lmScores = lm.score(words.map { Self.displayWord($0.word) }, leadingSpace: leadingSpace || context.isEmpty)
        let ranked = zip(words, lmScores).map { ($0.word, $0.spatial + Self.swipeModelWeight * $1) }.sorted { $0.1 > $1.1 }
        var seen = Set<String>()
        let best = ranked.map { Self.displayWord($0.0) }.filter { seen.insert($0).inserted }
        let top = ranked.prefix(4).map { "\($0.0)=\(String(format: "%.1f", $0.1))" }.joined(separator: " ")
        return SwipeResult(words: Array(best.prefix(8)),
                           log: "SWIPE [\(top)] \(swipeMs(started))ms (walk \(fits.count) \(swipeMs(started, tWalk)) "
                               + "shape \(swipeMs(tWalk, tShape)) lm \(words.count))")
    }

    /// Every word-list key whose letters can be laid along the path in order,
    /// the first at the landing point and the last at the lift, and how well
    /// (nats, 0 = every letter's key center right on the path). Walks the list
    /// like `search`, one letter at a time down shared prefixes.
    private func followPath(_ samples: [CGPoint], keys: KeyMap) -> [String: Float] {
        let n = samples.count
        let sx = keys.keySize.width * Self.swipeSpread, sy = keys.keySize.height * Self.swipeSpread
        // cost[c * n + j]: letter c laid at sample j.
        var cost = [Float](repeating: .infinity, count: 26 * n)
        for c in 0..<26 {
            guard let center = keys.centers[Character(UnicodeScalar(UInt8(97 + c)))] else { continue }
            for (j, p) in samples.enumerated() {
                let dx = (p.x - center.x) / sx, dy = (p.y - center.y) / sy
                cost[c * n + j] = Float(dx * dx + dy * dy) / 2
            }
        }
        let worst = Self.swipeWorst, perLetter = Self.swipeWorstPerLetter
        // rows[d * n + j]: best cost of the first d+1 letters, letter d at sample j.
        let maxDepth = 24
        var rows = [Float](repeating: .infinity, count: maxDepth * n)
        var found: [String: Float] = [:]
        rows.withUnsafeMutableBufferPointer { rows in
            lexicon.walk(step: { d, byte in
                guard d < maxDepth, byte >= 97, byte <= 122 else { return false }
                let c = Int(byte) - 97, cur = d * n
                if d == 0 {
                    // The first letter is where the finger landed.
                    for j in 0..<n { rows[j] = .infinity }
                    rows[0] = cost[c * n]
                    return rows[0] <= worst + perLetter
                }
                // Letter d at sample j: the previous letter anywhere up to j.
                let prev = (d - 1) * n
                var running = Float.infinity, best = Float.infinity
                for j in 0..<n {
                    running = min(running, rows[prev + j])
                    let v = running + cost[c * n + j]
                    rows[cur + j] = v
                    best = min(best, v)
                }
                return best <= worst + perLetter * Float(d + 1)
            }, found: { length, index in
                // The last letter is where the finger lifted.
                guard length >= 2, length <= maxDepth else { return }
                let v = rows[(length - 1) * n + n - 1]
                if v <= worst + perLetter * Float(length) { found[lexicon.key(at: index)] = -v }
            })
        }
        return found
    }

    /// English "I" and its contractions, fixed spellings ("iPhone"),
    /// everything else as listed.
    static func displayWord(_ word: String) -> String {
        word == "i" || word.hasPrefix("i'") ? "I" + word.dropFirst() : WordCasing.apply(word)
    }

    // MARK: Paths

    /// Points every `step` along the path (at most `maxCount`, spaced wider
    /// for long paths), ends included.
    static func resample(_ path: [CGPoint], step: CGFloat, maxCount: Int) -> [CGPoint] {
        let length = Self.length(path)
        guard length > 0 else { return path.isEmpty ? [] : [path[0]] }
        let count = min(maxCount, max(2, Int(length / step) + 1))
        return resample(path, count: count)
    }

    /// `count` points evenly spaced along the path, ends included.
    static func resample(_ path: [CGPoint], count: Int) -> [CGPoint] {
        guard let first = path.first else { return [] }
        let length = Self.length(path)
        guard length > 0, count > 1, path.count > 1 else { return Array(repeating: first, count: max(count, 1)) }
        let step = length / CGFloat(count - 1)
        var out = [first]
        var carried: CGFloat = 0
        var i = 1
        var a = first
        while i < path.count, out.count < count - 1 {
            let b = path[i]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if carried + seg >= step, seg > 0 {
                let t = (step - carried) / seg
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                out.append(p)
                a = p
                carried = 0
            } else {
                carried += seg
                a = b
                i += 1
            }
        }
        while out.count < count { out.append(path[path.count - 1]) }
        return out
    }

    static func length(_ path: [CGPoint]) -> CGFloat {
        zip(path, path.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Doubled letters ("ll") are one point of the ideal path.
    static func dedupe(_ points: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in points where out.last != p { out.append(p) }
        return out
    }

    private func swipeMs(_ a: Date, _ b: Date = Date()) -> Int { Int(b.timeIntervalSince(a) * 1000) }
}
