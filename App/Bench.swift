import CoreGraphics
import Foundation

/// On-device speed test for the keyboard's model (launch the app with
/// -bench). Results go to Documents/bench.log, read from the Mac with
/// devicectl. The model is borrowed from the keyboard's bundle.
enum Bench {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-bench") else { return }
        DispatchQueue.global(qos: .userInitiated).async { run() }
    }

    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("bench.log")
    private static var lines: [String] = []
    private static func log(_ s: String) {
        lines.append(s)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func run() {
        lines = []
        guard let plugin = Bundle.main.builtInPlugInsURL?.appendingPathComponent("Keyboard.appex"),
              let lexicon = Lexicon(url: plugin.appendingPathComponent("lexicon-enfrdees.bin")) else {
            return log("no keyboard bundle")
        }
        // Gemma is downloaded on request now (ModelStore), not bundled.
        guard let modelPath = ModelStore.gemmaURL()?.path else { return log("Gemma not downloaded") }

        // QWERTY-ish geometry like an iPhone 15 (key 38.7 x 50).
        let u: CGFloat = 38.7
        var keys = KeyMap(keySize: CGSize(width: u, height: 50))
        for (row, letters, start) in [(0, "qwertyuiop", 0.0), (1, "asdfghjkl", 0.5), (2, "zxcvbnm", 1.5)] as [(Int, String, CGFloat)] {
            for (i, c) in letters.enumerated() {
                keys.centers[c] = CGPoint(x: 3 + (start + CGFloat(i) + 0.5) * u, y: 25 + CGFloat(row) * 50)
            }
        }
        let cases: [(String, String)] = [
            ("The brown fox jumps ", "ocer"), ("Any PR made ", "witn"), ("Je pense que c'est une ", "tres"),
            ("Il est ", "daccord"), ("Then I ", "woud"), ("La personne ", "dont"), ("I ", "dont"),
            ("Le chat est sur la ", "table"), ("Sentinel is done with my ", "accout"), ("over ", "te"),
        ]

        for threads in [2, 4] {
            let t0 = Date()
            guard let lm = LanguageModel(path: modelPath, threads: threads) else { return log("load failed") }
            log("threads=\(threads) load=\(ms(t0))ms")
            let decoder = WordDecoder(lm: lm, lexicon: lexicon)
            for full in [false, true] {
                var times: [Int] = []
                for _ in 0..<2 {
                    for (before, word) in cases {
                        let taps = word.map { Tap(letter: $0, point: keys.centers[$0]) }
                        let r = DecodeRequest(before: before, word: word, taps: taps, keys: keys, autocorrect: true)
                        let t = Date()
                        let result = decoder.decode(r, full: full)
                        times.append(ms(t))
                        if full && times.count <= cases.count { log("  " + result.log) }
                    }
                }
                times.sort()
                log("threads=\(threads) \(full ? "full" : "bar ") median=\(times[times.count / 2])ms max=\(times.last!)ms")
            }
            // Raw model cost: N words scored at once.
            lm.setContext("I think that we should")
            for n in [1, 3, 5, 10] {
                let words = Array(["go", "meet", "probably", "eat", "be", "try", "leave", "start", "call", "wait"].prefix(n))
                let t = Date()
                _ = lm.score(words, leadingSpace: true)
                log("threads=\(threads) score \(n) words: \(ms(t))ms")
            }
            let t = Date()
            _ = lm.predict(leadingSpace: true)
            log("threads=\(threads) predict: \(ms(t))ms")
        }
        log("done")
    }

    private static func ms(_ d: Date) -> Int { Int(Date().timeIntervalSince(d) * 1000) }
}
