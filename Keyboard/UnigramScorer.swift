import Foundation

/// A WordScorer that knows only how common each word is (no context): for
/// languages without a model yet (Korean). Log-probability in nats from the
/// word list's Zipf value; words not in the list get the floor.
final class UnigramScorer: WordScorer {
    let lexicon: Lexicon
    let keyFor: (String) -> String?
    /// Zipf of a word missing from the list: below anything in it.
    var floorZipf: Float = 1
    /// Zipf of a word with a jamo outside any syllable.
    var strayJamoZipf: Float = -2

    init(lexicon: Lexicon, keyFor: @escaping (String) -> String?) {
        self.lexicon = lexicon
        self.keyFor = keyFor
    }

    @discardableResult func setContext(_ text: String) -> Bool { true }

    func score(_ words: [String], leadingSpace: Bool) -> [Float] {
        words.map { word in
            var zipf = keyFor(word).flatMap { k in lexicon.lookup(k).first { $0.word == word }?.zipf } ?? floorZipf
            // A lone jamo left in a word (바뀌퉀ㅇ요) is a slip, not a word.
            if word.unicodeScalars.contains(where: { (0x3131...0x318E).contains($0.value) }) && word.count > 1 {
                zipf = min(zipf, strayJamoZipf)
            }
            // Zipf is log10 of uses per billion words.
            return (zipf - 9) * Float(M_LN10)
        }
    }

    func quickScore(_ words: [String], leadingSpace: Bool) -> [Float] { score(words, leadingSpace: leadingSpace) }
    func predict(count: Int, leadingSpace: Bool) -> [String] { [] }
}
