import Foundation

/// Touch-aware Korean autocorrection for the Dubeolsik keyboard. Dubeolsik
/// puts every jamo on a QWERTY key, so this is the Latin WordDecoder run over
/// the Korean word list (Models/lexicon-ko.bin), which files each word under
/// the keys its jamo are typed on: 안녕 → "dkssud". Taps are read exactly as
/// on the ABC keyboard. Frequencies only for now (no sentence context).
///
/// Memory-mapped, loaded while the Hangul keyboard is up; a decode takes a
/// few milliseconds, so it runs on the main thread.
final class KoreanDecoder {
    static let shared = KoreanDecoder()
    private var decoder: WordDecoder?
    private var lexicon: Lexicon?
    var isLoaded: Bool { decoder != nil }

    func load() {
        guard decoder == nil, let url = Bundle.main.url(forResource: "lexicon-ko", withExtension: "bin"),
              let lex = Lexicon(url: url) else { return }
        lex.languages = 1
        let d = WordDecoder(lm: UnigramScorer(lexicon: lex, keyFor: HangulComposer.qwertyKey), lexicon: lex)
        d.french = false
        d.keyFor = HangulComposer.qwertyKey
        lexicon = lex
        decoder = d
    }

    func unload() {
        decoder = nil
        lexicon = nil
    }

    /// `word`: the Hangul being typed; `taps`: one per jamo, named by the
    /// QWERTY letter of its key. `full` also decides on a correction.
    func decode(_ word: String, taps: [Tap], keys: KeyMap, autocorrect: Bool, full: Bool) -> DecodeResult? {
        guard let decoder, !word.isEmpty else { return nil }
        let request = DecodeRequest(before: "", word: word, taps: taps, keys: keys, autocorrect: autocorrect)
        return decoder.decode(request, full: full)
    }

    func isWord(_ word: String) -> Bool {
        guard let lexicon, let key = HangulComposer.qwertyKey(word) else { return false }
        return lexicon.lookup(key).contains { $0.word == word }
    }
}
