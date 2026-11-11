import KanaKanjiConverterModuleWithDefaultDictionary
import SwiftUI
import UIKit

/// `romaji`: the Latin layout typing Japanese ("nihongo" → にほんご → 日本語).
enum KeyboardMode: String {
    case letters, kana, romaji, hangul, numpad, emoji
    /// Numbers on top, punctuation below; `symbols2` is the "#+=" page.
    case symbols, symbols2
    var isJapanese: Bool { self == .kana || self == .romaji }
    /// A keyboard for the Asian language: no capitals, no Latin autocorrect.
    var isAsian: Bool { isJapanese || self == .hangul }
}
enum ShiftState { case off, on, locked }

enum PopupItem: Equatable {
    case text(String)
    case action(MenuAction)
}

enum OneHandSide: String { case left, right }

struct Popup: Equatable {
    var options: [PopupItem]
    var frame: CGRect
    var selected = 0
    var cellWidth: CGFloat = Popup.defaultCellWidth
    /// A column instead of a row (the layout menu on return).
    var vertical = false
    var cellHeight: CGFloat = 40
    /// Drawn as an iOS-style menu panel: left-aligned rows with separators.
    var menu = false
    /// Row with a checkmark (the keyboard in use).
    var checked: Int? = nil

    static let defaultCellWidth: CGFloat = 34
}

/// Kana around a held or flicked key, each on the side its flick goes.
struct FlickGuide: Equatable {
    /// Center, left, up, right, down ("" for none).
    var options: [String]
    /// The key, in keyboard coordinates. Its own kana isn't redrawn.
    var key: CGRect
    var selected = 0
    /// Held: every flick shows. Flicked straight away: only the chosen one.
    var full = false
}

final class KeyboardState: ObservableObject {
    static let shared = KeyboardState()
    @Published var mode: KeyboardMode = .letters
    /// Latin or kana: where the numpad and emoji panel go back to, and what
    /// the keyboard opens with. Remembered across launches.
    var textMode: KeyboardMode = UserDefaults.standard.string(forKey: "textMode")
        .flatMap(KeyboardMode.init) ?? .letters {
        didSet { UserDefaults.standard.set(textMode.rawValue, forKey: "textMode") }
    }

    /// The Japanese keyboard picked in the app: kana flick or romaji.
    var japaneseMode: KeyboardMode { settings.japaneseInput == .romaji ? .romaji : .kana }
    /// The Asian language's keyboard, or nil with none picked.
    var asianMode: KeyboardMode? {
        switch settings.asianLanguage {
        case .none: return nil
        case .japanese: return japaneseMode
        case .korean: return .hangul
        }
    }
    /// Romaji in the ABC keyboard offers Japanese.
    var japaneseInABC: Bool { settings.asianLanguage == .japanese && settings.japaneseInLatin }
    /// Romaja in the ABC keyboard offers Korean.
    var koreanInABC: Bool { settings.asianLanguage == .korean && settings.koreanInLatin }

    /// The Hangul syllable being built (Dubeolsik), or the Cheonjiin pad.
    private var hangul = HangulComposer()
    private var cheonjiin = Cheonjiin()
    private var usesCheonjiin: Bool { settings.koreanInput == .cheonjiin }
    /// Text the block put in the document: when the text before the cursor no
    /// longer ends with it (the cursor moved, the app changed it), it's done.
    private var hangulText = ""

    func switchTo(_ text: KeyboardMode) {
        commitComposition()
        hangul.reset()
        cheonjiin.reset()
        if text != .letters { shift = .off }
        textMode = text
        mode = text
        taps = []
        lateFix = nil
        loadEngines()
    }

    /// Japanese modes drop the English/French model; it isn't used there.
    /// The ABC keyboard can keep the kana dictionary too (Japanese chip):
    /// it adds ~4 MB next to the model's ~30.
    func loadEngines() {
        if textMode.isJapanese {
            predictor.unload()
            KanaConverter.shared.load()
        } else if textMode == .hangul {
            // Korean: touch-aware corrections from the Korean word list. The
            // European model stays: Dubeolsik taps spell Latin words too, and
            // the bar offers them (ㅗㄷㅣㅣㅐ → "hello").
            KanaConverter.shared.unload()
            if usesCheonjiin { KoreanDecoder.shared.unload() } else { KoreanDecoder.shared.load() }
            DispatchQueue.global(qos: .userInitiated).async {
                KoreanWords.shared.load()
                DispatchQueue.main.async { [weak self] in self?.textChanged() }
            }
            Suggester.languages = settings.predictionLanguages
            predictor.setLanguages(settings.predictionLanguages)
            predictor.setModel(settings.correctionModel)
            predictor.load()
        } else {
            KoreanDecoder.shared.unload()
            if !koreanInABC { KoreanWords.shared.unload() }
            if japaneseInABC { KanaConverter.shared.load() } else { KanaConverter.shared.unload() }
            if koreanInABC {
                DispatchQueue.global(qos: .userInitiated).async { KoreanWords.shared.load() }
            }
            Suggester.languages = settings.predictionLanguages
            predictor.setLanguages(settings.predictionLanguages)
            predictor.setModel(settings.correctionModel)
            predictor.load()
        }
    }

    // MARK: Hangul

    private func typeHangul(_ jamo: Character) {
        var j = jamo
        if shift != .off, let tense = HangulComposer.shifted[String(jamo)]?.first { j = tense }
        if shift == .on { shift = .off }
        // The block is only ours while the text still ends with it.
        if !hangul.isEmpty && !textBefore.hasSuffix(hangulText) { hangul.reset() }
        applyHangul([hangul.type(j)], text: hangul.text)
    }

    /// Makes the edits, then remembers `text` as the Hangul now ending the document.
    private func applyHangul(_ edits: [(delete: Int, insert: String)], text: String) {
        for edit in edits {
            for _ in 0..<edit.delete { proxy?.deleteBackward() }
            if !edit.insert.isEmpty { proxy?.insertText(edit.insert) }
        }
        hangulText = text
        lastCorrection = nil
        textChanged()
    }

    // MARK: Kana composition

    /// Kana typed but not yet committed, shown underlined in the text field.
    private var composing = ComposingText()
    private var candidates: [Candidate] = []
    /// Conversion candidates for the bar while composing.
    @Published private(set) var kanaCandidates: [String] = []
    /// Candidate picked with the space key (shown in the text, not yet committed).
    @Published private(set) var kanaSelected: Int?
    var isComposing: Bool { !composing.isEmpty }

    private func compose(_ s: String, style: InputStyle = .direct) {
        if let i = kanaSelected { commitCandidate(at: i) }
        composing.insertAtCursorPosition(s, inputStyle: style)
        updateComposition()
    }

    /// Shows the reading (or the picked candidate) as marked text and asks
    /// for new candidates.
    private func updateComposition(requestCandidates: Bool = true) {
        guard isComposing else {
            proxy?.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            proxy?.unmarkText()
            clearComposition()
            return
        }
        var shown = composing.convertTarget
        if let i = kanaSelected, i < candidates.count {
            var rest = composing
            rest.prefixComplete(composingCount: candidates[i].composingCount)
            shown = candidates[i].text + rest.convertTarget
        }
        proxy?.setMarkedText(shown, selectedRange: NSRange(location: (shown as NSString).length, length: 0))
        guard requestCandidates else { return }
        KanaConverter.shared.candidates(for: composing) { [weak self] found in
            guard let self, self.isComposing else { return }
            self.candidates = found
            self.kanaCandidates = found.map(\.text)
        }
    }

    private func clearComposition() {
        composing = ComposingText()
        candidates = []
        if !kanaCandidates.isEmpty { kanaCandidates = [] }
        kanaSelected = nil
        KanaConverter.shared.reset()
    }

    /// Commits a candidate; whatever reading it didn't cover stays composing.
    func commitCandidate(at index: Int) {
        guard index < candidates.count else { return }
        let c = candidates[index]
        proxy?.setMarkedText(c.text, selectedRange: NSRange(location: (c.text as NSString).length, length: 0))
        proxy?.unmarkText()
        KanaConverter.shared.didCommit(c)
        composing.prefixComplete(composingCount: c.composingCount)
        kanaSelected = nil
        candidates = []
        kanaCandidates = []
        if isComposing { updateComposition() } else { clearComposition() }
    }

    /// Commits the text as shown: the space-picked candidate, or the kana as typed.
    func commitComposition() {
        guard isComposing else { return }
        if let i = kanaSelected {
            commitCandidate(at: i)
            if !isComposing { return }
        }
        proxy?.unmarkText()
        clearComposition()
    }

    /// Space while composing: step to the next candidate, like 次候補.
    private func nextCandidate() {
        guard !candidates.isEmpty else { return }
        kanaSelected = ((kanaSelected ?? -1) + 1) % candidates.count
        tick()
        updateComposition(requestCandidates: false)
    }

    /// Backspace while composing: undo the picked candidate, else drop a kana.
    private func deleteComposing() {
        if kanaSelected != nil {
            kanaSelected = nil
            updateComposition(requestCandidates: false)
            return
        }
        composing.deleteBackwardFromCursorPosition(count: 1)
        updateComposition()
    }
    @Published var shift: ShiftState = .off
    @Published var popup: Popup?
    @Published var flickGuide: FlickGuide?
    @Published var suggestions: [String] = []
    /// The app's own test field has focus: show a hide-keyboard button.
    @Published var inAppField = false
    /// Shown in the empty suggestion bar when Full Access is off (settings unreachable).
    @Published var setupNote: String?
    @Published var canPaste = false
    /// Keys currently under a finger, for the pressed highlight.
    @Published var pressedKeys: Set<String> = []
    /// Applied when the user types a space or punctuation.
    @Published var pendingCorrection: String?

    /// The last automatic fix, kept so an immediate backspace can undo it.
    private var lastCorrection: (original: String, corrected: String, trigger: String)?
    /// A word whose fix was undone; left alone until the user moves on.
    private var rejectedWord: String?
    /// Words the user kept as typed (undid a fix, or picked "as typed"):
    /// never autocorrected again ("mcp", names, slang). Lowercased.
    private var knownWords = Set(UserDefaults.standard.stringArray(forKey: "knownWords") ?? [])
    private func learn(_ word: String) {
        let key = word.lowercased()
        guard !key.isEmpty, knownWords.insert(key).inserted else { return }
        UserDefaults.standard.set(Array(knownWords.suffix(2000)), forKey: "knownWords")
    }
    private func isKnown(_ word: String) -> Bool { knownWords.contains(word.lowercased()) }
    /// Punctuation that sticks to the word before it: "word ." becomes "word."
    private static let attachingPunctuation: Set<String> = [".", ",", "?", "!", ";", ":"]
    /// Return isn't one: a line break is often a deliberate "send as typed".
    private static let correctionTriggers: Set<String> = [" ", ".", ",", "?", "!", ";", ":"]
    @Published var showGlobe = false
    @Published var settings = KeyboardSettings.load() {
        // The app switched the Japanese keyboard while the other one was up.
        didSet {
            if textMode.isAsian && textMode != asianMode { switchTo(asianMode ?? .letters) }
        }
    }
    /// Emoji search in progress: letters, space and delete edit this instead
    /// of the document; the suggestion bar shows the query and the matches.
    @Published var emojiSearch: String?
    /// Emoji whose skin tones are shown after a long press (base and five tones).
    @Published var tonePicker: [String]?

    func startEmojiSearch() {
        emojiSearch = ""
        shift = .off
        mode = .letters
    }

    func endEmojiSearch() {
        emojiSearch = nil
        tonePicker = nil
        mode = .emoji
    }

    @Published private(set) var recentEmoji = UserDefaults.standard.stringArray(forKey: "recentEmoji") ?? []

    @Published var oneHand: OneHandSide? = UserDefaults.standard.string(forKey: "oneHand").flatMap(OneHandSide.init) {
        didSet { UserDefaults.standard.set(oneHand?.rawValue, forKey: "oneHand") }
    }

    weak var controller: KeyboardViewController?

    /// The language model, run in the background.
    var predictor: Predictor { Predictor.shared }
    /// Where each letter key sits, for reading taps as "probably this key".
    var keyMap = KeyMap()
    /// Taps that typed the current word, with where each finger landed.
    private var taps: [Tap] = []
    /// Dubeolsik taps of the Hangul word being typed, one per jamo, named by
    /// the QWERTY letter of the key (Korean and Latin decoders read them).
    private var hangulTaps: [Tap] = []
    /// A word finished before its correction was ready; the fix is applied
    /// when it arrives, as long as the text still ends the same way.
    private struct LateFix {
        let id: Int
        let word: String
        let trigger: String
        var tail = ""
    }
    private var lateFix: LateFix?
    private var lateFixCount = 0

    // Haptics need Full Access; without it iOS silently ignores them.
    private var tapFeedback = UIImpactFeedbackGenerator(style: .light)
    private var tapStyle = HapticStyle.light
    private let selectionFeedback = UISelectionFeedbackGenerator()

    func keyDown() {
        guard settings.haptics else { return }
        if settings.hapticStyle != tapStyle {
            tapStyle = settings.hapticStyle
            tapFeedback = UIImpactFeedbackGenerator(style: tapStyle.impact)
        }
        tapFeedback.impactOccurred(intensity: settings.hapticStrength)
        tapFeedback.prepare()
    }

    /// The small tick for flick and cursor moves, off with haptics.
    private func tick() {
        if settings.haptics { selectionFeedback.selectionChanged() }
    }
    var keyboardWidth: CGFloat = 0
    var keyboardHeight: CGFloat = 0

    /// Shows every flick of a held kana key around it, like the iPhone's guide.
    func showFlickGuide(_ options: [String], over key: CGRect, selected: Int, full: Bool) {
        let guide = FlickGuide(options: options, key: key, selected: selected, full: full)
        guard guide != flickGuide else { return }
        flickGuide = guide
        tick()
    }

    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }
    private var textBefore: String { proxy?.documentContextBeforeInput ?? "" }

    // MARK: Typing

    func display(_ s: String) -> String {
        guard shift != .off else { return s }
        if mode == .hangul { return HangulComposer.shifted[s] ?? s }
        let upper = s.uppercased()
        // "ß".uppercased() is "SS"; keep single characters single.
        return upper.count == s.count ? upper : s
    }

    func insert(_ s: String) {
        let s = smartened(s)
        lastCorrection = nil
        lateFix?.tail += s
        proxy?.insertText(s)
        textChanged()
    }

    /// Smart punctuation, like the iOS keyboard: straight quotes become curly
    /// (opening after a space or bracket, closing otherwise, so "don't" gets
    /// ’), and a second "-" turns "--" into "—". Off in Japanese, and where
    /// the text field asks for straight quotes or plain dashes.
    private func smartened(_ s: String) -> String {
        guard settings.smartPunctuation, !mode.isJapanese, let proxy else { return s }
        let quotes = proxy.smartQuotesType != .no
        if s == "-", proxy.smartDashesType != .no, textBefore.hasSuffix("-") {
            proxy.deleteBackward()
            if let tail = lateFix?.tail { lateFix?.tail = String(tail.dropLast()) }
            return "\u{2014}"
        }
        guard quotes, s.contains(where: { $0 == "'" || $0 == "\"" }) else { return s }
        var prev = textBefore.last
        var out = ""
        for c in s {
            var c2 = c
            if c == "'" || c == "\"" {
                let opening = prev.map { $0.isWhitespace || "([{<«“‘—–/".contains($0) } ?? true
                if c == "'" { c2 = opening ? "\u{2018}" : "\u{2019}" } else { c2 = opening ? "\u{201C}" : "\u{201D}" }
            }
            out.append(c2)
            prev = c2
        }
        return out
    }

    /// Types `s` from a key; spaces and punctuation apply the pending correction first.
    func type(_ s: String) {
        // "word ." → "word.": the space was from the previous word (or a
        // picked suggestion), and punctuation belongs against the word.
        if Self.attachingPunctuation.contains(s), mode != .kana, mode != .romaji {
            let before = textBefore
            if before.hasSuffix(" "), let prev = before.dropLast().last,
               prev.isLetter || prev.isNumber || ")]\"'’”»".contains(prev) {
                proxy?.deleteBackward()
                lastCorrection = nil
                taps = []
                insert(s)
                return
            }
        }
        guard Self.correctionTriggers.contains(s) else {
            insert(s)
            return
        }
        if mode == .hangul && !usesCheonjiin {
            let word = hangulWord
            let fixed = koreanCorrection(word, taps: hangulTaps)
            hangulTaps = []
            insert(s)
            if let fixed { lastCorrection = (word, fixed, s) }
            return
        }
        let word = currentWord
        let wordTaps = taps
        let fixed = applyCorrection(word)
        taps = []
        insert(s)
        if let fixed {
            lastCorrection = (fixed.original, fixed.corrected, s)
        } else if fixed == nil, needsLateFix(word) {
            requestLateFix(word: word, taps: wordTaps, trigger: s)
        }
    }

    /// Applies a correction that's already known: one the bar computed for
    /// exactly this word, or a missing apostrophe.
    private func applyCorrection(_ word: String) -> (original: String, corrected: String)? {
        guard !word.isEmpty, mode == .letters, autocorrectOn, rejectedWord == nil else { return nil }
        // English "i" (and i'm, i'll…) is always capitalized, even if it was once
        // learned by undoing the fix: learned words only protect real words.
        let pronoun = Suggester.pronounI(for: word)
        guard pronoun != nil || !isKnown(word) else { return nil }
        let fix: String?
        if let pronoun {
            fix = pronoun
        } else if let contraction = Suggester.contraction(for: word) {
            fix = contraction
        } else if correctionWord == word {
            fix = pendingCorrection
        } else if !predictor.isReady {
            fix = Suggester.autocorrection(for: word)
        } else {
            fix = nil
        }
        guard let fix else { return nil }
        for _ in 0..<word.count { proxy?.deleteBackward() }
        proxy?.insertText(fix)
        return (word, fix)
    }

    /// Fixes the Hangul word just finished, as the bar showed it (or works
    /// it out now: a Korean decode takes a few milliseconds). Returns the fix.
    private func koreanCorrection(_ word: String, taps: [Tap]) -> String? {
        guard !word.isEmpty, autocorrectOn, !isKnown(word), KoreanDecoder.shared.isLoaded else { return nil }
        let fix = correctionWord == word ? pendingCorrection
            : KoreanDecoder.shared.decode(word, taps: taps, keys: keyMap, autocorrect: true, full: true)?.correction
        guard let fix, fix != word else { return nil }
        for _ in 0..<word.count { proxy?.deleteBackward() }
        proxy?.insertText(fix)
        return fix
    }

    /// Typing outran the bar: the model hasn't seen this word yet.
    /// One-letter words too: the decoder only ever gives them an accent
    /// ("a" → "à" in French), which used to be skipped here.
    private func needsLateFix(_ word: String) -> Bool {
        !word.isEmpty && mode == .letters && autocorrectOn && rejectedWord == nil
            && !isKnown(word) && predictor.isReady && correctionWord != word
    }

    private func requestLateFix(word: String, taps: [Tap], trigger: String) {
        lateFixCount += 1
        let fix = LateFix(id: lateFixCount, word: word, trigger: trigger)
        lateFix = fix
        let before = String(textBefore.dropLast(trigger.count + word.count))
        let request = DecodeRequest(before: before, word: word, taps: taps, keys: keyMap, autocorrect: true)
        predictor.correct(request) { [weak self] result in self?.finishLateFix(fix.id, result) }
    }

    private func finishLateFix(_ id: Int, _ result: DecodeResult) {
        guard let late = lateFix, late.id == id else { return }
        lateFix = nil
        guard let fix = result.correction, fix != late.word else { return }
        let expected = late.word + late.trigger + late.tail
        // Only if nothing but plain typing happened since.
        guard textBefore.hasSuffix(expected) else { return }
        for _ in 0..<expected.count { proxy?.deleteBackward() }
        proxy?.insertText(fix + late.trigger + late.tail)
        if late.tail.isEmpty { lastCorrection = (late.word, fix, late.trigger) }
        textChanged()
    }

    var typedWord: String { currentWord }

    func insertEmoji(_ emoji: String) {
        insert(emoji)
        recentEmoji.removeAll { $0 == emoji }
        recentEmoji = Array(([emoji] + recentEmoji).prefix(24))
        UserDefaults.standard.set(recentEmoji, forKey: "recentEmoji")
    }

    func deleteBackward() {
        if emojiSearch != nil {
            if emojiSearch?.isEmpty == false { emojiSearch?.removeLast() }
            return
        }
        if isComposing {
            deleteComposing()
            return
        }
        if mode == .hangul, usesCheonjiin, !cheonjiin.isEmpty, textBefore.hasSuffix(hangulText),
           let edit = cheonjiin.backspace() {
            applyHangul([edit], text: cheonjiin.text)
            return
        }
        if mode == .hangul, !usesCheonjiin, !hangul.isEmpty, textBefore.hasSuffix(hangulText),
           let edit = hangul.backspace() {
            if !hangulTaps.isEmpty { hangulTaps.removeLast() }
            applyHangul([edit], text: hangul.text)
            return
        }
        hangul.reset()
        cheonjiin.reset()
        hangulTaps = []
        if !taps.isEmpty { taps.removeLast() }
        if let late = lateFix {
            // Deleting into the finished word means it's being edited by hand.
            if late.tail.isEmpty { lateFix = nil } else { lateFix?.tail.removeLast() }
        }
        // Backspace right after an automatic fix restores what was typed.
        if let c = lastCorrection, textBefore.hasSuffix(c.corrected + c.trigger) {
            lastCorrection = nil
            for _ in 0..<(c.corrected.count + c.trigger.count) { proxy?.deleteBackward() }
            proxy?.insertText(c.original)
            rejectedWord = c.original
            learn(c.original)
            textChanged()
            return
        }
        lastCorrection = nil
        proxy?.deleteBackward()
        textChanged()
    }

    /// Deletes like Option-Delete on a Mac: trailing spaces, then either the
    /// word or the run of punctuation before them.
    func deleteWordBackward() {
        if var q = emojiSearch {
            while q.last == " " { q.removeLast() }
            while let c = q.last, c != " " { q.removeLast() }
            emojiSearch = q
            return
        }
        if isComposing {
            // Holding delete while composing wipes the whole composition.
            composing = ComposingText()
            updateComposition()
            return
        }
        taps = []
        lateFix = nil
        var chars = Array(textBefore)
        var count = 0
        func eat(while matches: (Character) -> Bool) {
            while let c = chars.last, matches(c) { chars.removeLast(); count += 1 }
        }

        eat { $0 == " " || $0 == "\t" }
        if let last = chars.last {
            if last.isNewline && count == 0 {
                count = 1
            } else if last.isLetter || last.isNumber {
                eat { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" }
            } else if !last.isWhitespace {
                eat { !($0.isLetter || $0.isNumber || $0.isWhitespace) }
            }
        }
        // Some apps hide the text around the cursor; fall back to one character.
        for _ in 0..<max(count, 1) { proxy?.deleteBackward() }
        textChanged()
    }

    private(set) lazy var backspace = Backspace(
        deleteChar: { [unowned self] in deleteBackward() },
        deleteWord: { [unowned self] in deleteWordBackward() }
    )

    func space() {
        if mode.isJapanese {
            // Japanese: space converts while composing, else a full-width space.
            if isComposing { nextCandidate() } else { insert("\u{3000}") }
            return
        }
        let now = Date()
        defer { lastSpaceTap = now }
        // Double-tap space after a word types ". "
        let before = textBefore
        if settings.periodShortcut, now.timeIntervalSince(lastSpaceTap) < 0.4, before.hasSuffix(" "),
           let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
            proxy?.deleteBackward()
            insert(". ")
        } else {
            type(" ")
        }
    }

    /// 123 key: a tap opens the layout chosen in settings, a hold the other.
    func openNumbers(held: Bool) {
        commitComposition()
        let numpadFirst = settings.numberKeyTap == .numpad
        mode = numpadFirst != held ? .numpad : .symbols
    }

    func tapShift() {
        let now = Date()
        defer { lastShiftTap = now }
        switch shift {
        case .locked: shift = .off
        case .on where settings.capsLock && now.timeIntervalSince(lastShiftTap) < 0.3: shift = .locked
        case .on: shift = .off
        case .off: shift = .on
        }
    }

    // MARK: Japanese in the ABC keyboard

    /// Kanji/kana for the romaji word being typed ("watashi" → 私).
    @Published private(set) var japaneseChip: Candidate?
    /// Hangul for the romaja word being typed ("annyeong" → 안녕).
    @Published private(set) var koreanChip: String?
    /// What the red chip shows, Japanese or Korean.
    var chipText: String? { japaneseChip?.text ?? koreanChip }
    /// First in the bar when the word isn't English or French, else last.
    @Published private(set) var japaneseChipFirst = false

    private func refreshKoreanChip(_ word: String) {
        let found = koreanInABC ? KoreanWords.shared.fromRomaja(word) : nil
        if found != koreanChip { koreanChip = found }
        if found != nil { japaneseChipFirst = !Suggester.isWord(word) }
    }

    private func refreshJapaneseChip(_ word: String) {
        guard japaneseInABC, let reading = Self.romajiReading(word) else {
            if japaneseChip != nil { japaneseChip = nil }
            return
        }
        let first = !Suggester.isWord(word)
        KanaConverter.shared.candidates(for: reading, predict: false, fresh: true) { [weak self] found in
            guard let self, self.mode == .letters, self.currentWord == word else { return }
            // Skip candidates with Latin left over ("gomen" → "ご目n").
            self.japaneseChip = found.first { !$0.text.contains { $0.isASCII } }
            self.japaneseChipFirst = first
        }
    }

    /// The word as kana to convert, or nil when it can't be romaji.
    static func romajiReading(_ word: String) -> ComposingText? {
        let lower = word.lowercased()
        guard lower.count >= 2, lower.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        // l and x type small kana in IME romaji ("hello" → へっォ), q and v
        // barely occur, and c only in "ch": words with them are not Japanese.
        guard !lower.contains(where: { "lqxv".contains($0) }),
              !lower.enumerated().contains(where: { i, c in
                  c == "c" && (i + 1 == lower.count || lower[lower.index(lower.startIndex, offsetBy: i + 1)] != "h")
              }) else { return nil }
        // A final single "n" becomes ん once the word ends (gomen → ごめん).
        let input = lower.hasSuffix("n") && !lower.hasSuffix("nn") ? lower + "n" : lower
        var text = ComposingText()
        text.insertAtCursorPosition(input, inputStyle: .roman2kana)
        return text.convertTarget.contains { $0.isASCII } ? nil : text
    }

    /// Swaps the romaji word for the chip's kanji. No space after: Japanese
    /// doesn't use them.
    func pickJapanese() {
        if japaneseChip == nil, let korean = koreanChip {
            // Korean uses spaces between words, like a picked suggestion.
            lateFix = nil
            taps = []
            koreanChip = nil
            for _ in 0..<currentWord.count { proxy?.deleteBackward() }
            insert(korean + " ")
            return
        }
        guard let candidate = japaneseChip else { return }
        lateFix = nil
        taps = []
        japaneseChip = nil
        for _ in 0..<currentWord.count { proxy?.deleteBackward() }
        insert(candidate.text)
        KanaConverter.shared.didCommit(candidate)
    }

    func pick(suggestion: String) {
        if mode == .hangul {
            // A completion replaces the Hangul word being typed.
            let word = hangulWord
            // The word as typed over a pending fix: keep it from now on.
            if pendingCorrection != nil, suggestion == word { learn(word) }
            hangul.reset()
            cheonjiin.reset()
            hangulTaps = []
            for _ in 0..<word.count { proxy?.deleteBackward() }
            insert(suggestion + " ")
            return
        }
        // Picking the word exactly as typed over a pending fix: keep it.
        if pendingCorrection != nil, suggestion == currentWord { learn(suggestion) }
        lateFix = nil
        taps = []
        for _ in 0..<currentWord.count { proxy?.deleteBackward() }
        insert(suggestion + " ")
    }

    // MARK: Long-press popup

    /// What a key does when tapped (released without a long-press).
    /// `point`: where the finger landed, in key-map coordinates.
    func tap(_ key: Key, at point: CGPoint? = nil) {
        if emojiSearch != nil {
            switch key.action {
            case .text(let s):
                emojiSearch? += s.lowercased()
                if shift == .on { shift = .off }
                return
            case .space:
                emojiSearch? += " "
                return
            case .returnKey, .emoji:
                endEmojiSearch()
                return
            case .toLetters where mode == .letters:
                endEmojiSearch()
                return
            case .language, .cursor, .kanaModifier:
                return  // they act on the document
            default:
                break   // shift, number pages, globe: as usual
            }
        }
        if mode == .hangul && usesCheonjiin {
            switch key.action {
            case .text(let s) where Cheonjiin.handles(s):
                if !cheonjiin.isEmpty && !textBefore.hasSuffix(hangulText) { cheonjiin.reset() }
                applyHangul(cheonjiin.tap(s), text: cheonjiin.text)
                return
            case .cursor(1) where cheonjiin.inUnit:
                cheonjiin.endUnit()  // → between two taps of the same key: ㄱ, ㄱ
                return
            case .backspace:
                break
            default:
                cheonjiin.reset()
            }
        } else if mode == .hangul {
            switch key.action {
            case .text(let s) where s.count == 1 && HangulComposer.isJamo(s.first!):
                if hangulWord.isEmpty { hangulTaps = [] }
                if let letter = HangulComposer.qwerty[s.first!] { hangulTaps.append(Tap(letter: letter, point: point)) }
                typeHangul(s.first!)
                return
            case .backspace, .shift:
                break
            default:
                hangul.reset()  // punctuation, space, other keys end the syllable
            }
        }
        switch key.action {
        case .text(let s) where mode == .kana:
            compose(s)
        case .text(let s) where mode == .romaji:
            // Letters and the punctuation azooKey reads as kana (- , . ? !)
            // compose; anything else ends the composition first.
            if s.count == 1, let c = s.lowercased().first, c.isASCII, c.isLetter || "-,.?!".contains(c) {
                compose(String(c), style: .roman2kana)
            } else {
                commitComposition()
                type(s)
            }
        case .text(let s):
            // The apostrophe too: it's part of words (l'ami, don't), and a
            // slip onto it mid-word ("kn'w") needs its position to be fixed.
            if s.count == 1, let letter = s.lowercased().first, letter.isLetter || letter == "'" {
                taps.append(Self.tap(letter, at: point))
            }
            type(display(s))
        case .shift: tapShift()
        case .space: space()
        case .returnKey:
            if isComposing { commitComposition() } else { type("\n") }
        case .toNumpad:
            openNumbers(held: false)
        case .symbolPage:
            mode = mode == .symbols ? .symbols2 : .symbols
        case .toLetters: mode = textMode
        case .globe: controller?.advanceToNextInputMode()
        case .language:
            if mode.isAsian {
                switchTo(.letters)
            } else if let asian = asianMode {
                switchTo(asian)
            } else if let i = settings.menuLayouts.firstIndex(of: settings.layout), settings.menuLayouts.count > 1 {
                // No Japanese: a tap goes to the next layout in the menu.
                settings.layout = settings.menuLayouts[(i + 1) % settings.menuLayouts.count]
                settings.save()
                switchTo(.letters)
            }
        case .emoji:
            commitComposition()
            mode = .emoji
        case .cursor(let n):
            commitComposition()
            moveCursor(by: n)
        case .kanaModifier: cycleKana()
        case .backspace: break // handled by Backspace on press
        }
    }

    /// Long-press on a key: the first option (the corner symbol or digit)
    /// sits right above the finger, already selected, and the rest run
    /// sideways from it; to the left on keys too close to the right edge.
    func showPopup(for key: Key, over frame: CGRect) {
        let options = key.actions.map(PopupItem.action) + key.alternates.map(PopupItem.text)
        let cell = Popup.defaultCellWidth
        let width = CGFloat(options.count) * cell + 8
        let firstX = frame.midX - cell / 2 - 4          // popup's x with cell 0 over the key
        if firstX + width <= keyboardWidth - 4 || options.count == 1 {
            showPopup(options: options, over: frame, originX: firstX)
        } else {
            // Mirrored: cell 0 is the rightmost one, still over the key.
            showPopup(options: options.reversed(), over: frame, selected: options.count - 1,
                      originX: frame.midX + cell / 2 + 4 - width)
        }
    }

    /// Long-press on the language key: an iOS-style panel with settings, the
    /// layouts picked in the app (up to 3), then the Japanese keyboard. The finger
    /// slides up to pick; the keyboard in use has a checkmark.
    func showKeyboardMenu(over key: CGRect) {
        let options: [MenuAction] = [.settings] + settings.menuLayouts.map { .layout($0) }
            + (asianMode.map { [$0 == .romaji ? .romaji : $0 == .hangul ? .hangul : .kana] } ?? [])
        let current: MenuAction = textMode == .kana ? .kana : textMode == .romaji ? .romaji
            : textMode == .hangul ? .hangul : .layout(settings.layout)
        let checked = options.firstIndex(of: current)
        showPopup(options: options.map(PopupItem.action), over: key, cellWidth: 220,
                  selected: checked ?? 0, vertical: true, menu: true, checked: checked)
    }

    /// ゛゜小: swaps the character before the cursor for its next form.
    private func cycleKana() {
        if isComposing {
            guard let last = composing.convertTarget.last, let next = Layouts.kanaVariant(last) else { return }
            kanaSelected = nil
            composing.deleteBackwardFromCursorPosition(count: 1)
            composing.insertAtCursorPosition(String(next), inputStyle: .direct)
            updateComposition()
            return
        }
        guard let last = textBefore.last, let next = Layouts.kanaVariant(last) else { return }
        proxy?.deleteBackward()
        insert(String(next))
    }

    func showPopup(options: [PopupItem], over key: CGRect,
                   cellWidth: CGFloat = Popup.defaultCellWidth, selected: Int = 0, vertical: Bool = false,
                   menu: Bool = false, checked: Int? = nil, originX: CGFloat? = nil) {
        // Columns shrink their rows to fit above the key, up to the bar's top.
        let room = key.minY + Metrics.suggestionBarHeight - 10
        let cellHeight: CGFloat = vertical ? min(menu ? 44 : 40, (room / CGFloat(options.count)).rounded(.down)) : 40
        let width = vertical ? cellWidth + 8 : CGFloat(options.count) * cellWidth + 8
        let height = vertical ? CGFloat(options.count) * cellHeight + 8 : max(44, key.height)
        // Columns start at the key's left edge so the finger can slide straight up.
        let x = vertical
            ? min(max(4, key.minX), keyboardWidth - width - 4)
            : min(max(4, originX ?? key.midX - width / 2), keyboardWidth - width - 4)
        // The extension can't draw outside its own view, so number-row popups
        // rise only as far as the top of the suggestion bar.
        let y = max(-Metrics.suggestionBarHeight + 2, key.minY - height - 4)
        let shown = options.map { item -> PopupItem in
            if case .text(let s) = item { return .text(display(s)) }
            return item
        }
        popup = Popup(options: shown, frame: CGRect(x: x, y: y, width: width, height: height),
                      selected: selected, cellWidth: cellWidth, vertical: vertical, cellHeight: cellHeight,
                      menu: menu, checked: checked)
        tick()
    }

    /// `point` in keyboard coordinates.
    func movePopupSelection(to point: CGPoint) {
        guard var p = popup else { return }
        let index = p.vertical
            ? Int(floor((point.y - p.frame.minY - 4) / p.cellHeight))
            : Int(floor((point.x - p.frame.minX - 4) / p.cellWidth))
        p.selected = min(max(0, index), p.options.count - 1)
        if p != popup {
            popup = p
            tick()
        }
    }

    /// The corrector knows a-z only: an accented letter (a Bépo é key, or
    /// one picked by long-press) counts as its plain letter, typed exactly.
    private static func tap(_ letter: Character, at point: CGPoint?) -> Tap {
        guard !letter.isASCII, let plain = String(letter).folding(options: .diacriticInsensitive, locale: nil).first,
              plain.isASCII else { return Tap(letter: letter, point: point) }
        return Tap(letter: plain, point: nil)
    }

    func commitPopup() {
        guard let p = popup else { return }
        popup = nil
        switch p.options[p.selected] {
        case .text(let s) where mode == .hangul && s.count == 1 && HangulComposer.isJamo(s.first!):
            typeHangul(s.first!)   // ㄲ ㅃ… from a long-press join the syllable too
        case .text(let s):
            if mode == .hangul { hangul.reset() }
            if s.count == 1, let letter = s.lowercased().first, letter.isLetter || letter == "'" {
                taps.append(Self.tap(letter, at: nil))
            }
            commitComposition()
            type(s)
        case .action(.emoji):
            commitComposition()
            mode = .emoji
        case .action(.settings): controller?.openContainingApp()
        case .action(.oneHanded): oneHand = oneHand == nil ? .right : nil
        case .action(.layout(let layout)):
            settings.layout = layout
            settings.save()
            switchTo(.letters)
        case .action(.kana): switchTo(.kana)
        case .action(.romaji): switchTo(.romaji)
        case .action(.hangul): switchTo(.hangul)
        }
    }

    // MARK: Context

    /// Letters just before the cursor.
    /// Apostrophes count as part of the word (l'ami, don't), so a slip onto
    /// the apostrophe key mid-word ("kn'w") is still one word to correct.
    /// Latin-script letters only: kanji or kana picked from the Japanese
    /// chip end the word, so "日本語wo" is read as "wo".
    private var currentWord: String {
        String(textBefore.reversed().prefix {
            ($0.isLetter && ($0.unicodeScalars.first?.value ?? 0) < 0x2E80) || $0 == "'" || $0 == "’"
        }.reversed())
    }

    /// Space-bar trackpad: moves the cursor without typing.
    func moveCursor(by offset: Int) {
        guard offset != 0, let proxy else { return }
        // A tick per word, not per character: only when the cursor passes
        // a space or line break. Read before moving; the proxy's context
        // can lag right after an adjustment.
        let passed = offset < 0
            ? String((proxy.documentContextBeforeInput ?? "").suffix(-offset))
            : String((proxy.documentContextAfterInput ?? "").prefix(offset))
        proxy.adjustTextPosition(byCharacterOffset: offset)
        if passed.contains(where: \.isWhitespace) { tick() }
        // Whatever was being typed is no longer under the cursor.
        taps = []
        lateFix = nil
        textChanged()
    }

    func paste() {
        commitComposition()
        if let text = UIPasteboard.general.string { insert(text) }
    }

    /// Cheap per-keystroke work only; the bar refresh runs on the next
    /// run-loop turn and its model work off the main thread.
    /// The result of a sum or a currency conversion typed before "=", for
    /// the bar: what it shows, and what a tap types.
    /// `replace`: characters a tap swaps for `text` ("100€" → "$111.65"); 0
    /// after "=", where the result is added.
    struct BarResult: Equatable { var label: String; var text: String; var replace = 0 }
    @Published private(set) var mathResults: [BarResult] = []

    func pickMath(_ result: BarResult) {
        mathResults = []
        taps = []
        for _ in 0..<result.replace { proxy?.deleteBackward() }
        insert(result.text)
    }

    func textChanged() {
        var math: [BarResult] = []
        if !mode.isJapanese, textBefore.hasSuffix("=") || textBefore.hasSuffix("= ") {
            let before = textBefore.trimmingCharacters(in: .whitespaces)
            if settings.currencyConversion, let r = CurrencyResult.result(for: before) {
                math = [BarResult(label: r.label, text: r.text)]
            } else if settings.mathResults, let r = MathResult.result(for: before) {
                math = [BarResult(label: r, text: r)]
            }
        } else if !mode.isJapanese, settings.currencyConversion, let q = CurrencyResult.quick(for: textBefore) {
            math = q.results.map { BarResult(label: $0, text: $0, replace: q.replace) }
        }
        if math != mathResults { mathResults = math }
        let word = currentWord
        if word != rejectedWord { rejectedWord = nil }
        if word.isEmpty { taps = [] }
        updateAutoShift()
        scheduleRefresh()
    }

    private var refreshWork: DispatchWorkItem?
    /// The word `pendingCorrection` was computed for.
    private var correctionWord: String?
    /// Last clipboard check: it costs 10-25 ms on the main thread, too much
    /// for every keystroke, and the clipboard rarely changes mid-sentence.
    private var pasteCheckedAt: CFTimeInterval = 0

    /// Every keystroke, like Gboard: the predictor drops requests that are
    /// already stale, so fast typing never queues up work. (This used to wait
    /// for an 80 ms pause, which left the bar frozen during fast typing.)
    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshBar() }
        refreshWork = work
        DispatchQueue.main.async(execute: work)
    }

    /// Hangul just before the cursor: the word the Korean bar completes.
    private var hangulWord: String {
        String(textBefore.reversed().prefix { c in
            c.unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
        }.reversed())
    }

    private func refreshBar() {
        let started = CACurrentMediaTime()
        // Keyboards may only read the clipboard with Full Access. `hasStrings`
        // checks without reading the contents, so it doesn't trigger iOS's
        // paste-permission banner.
        if started - pasteCheckedAt > 2 {
            pasteCheckedAt = started
            let pasteAvailable = controller?.hasFullAccess == true && UIPasteboard.general.hasStrings
            if pasteAvailable != canPaste { canPaste = pasteAvailable }
        }
        if mode == .hangul {
            refreshHangulBar()
            return
        }
        guard mode == .letters else {
            if japaneseChip != nil { japaneseChip = nil }
            if koreanChip != nil { koreanChip = nil }
            return
        }
        let word = currentWord
        refreshJapaneseChip(word)
        refreshKoreanChip(word)
        guard predictor.isReady else {
            // Model still loading: the plain dictionary bar.
            let fix = correction(for: word)
            correctionWord = word
            if fix != pendingCorrection { pendingCorrection = fix }
            suggestions = Suggester.suggestions(for: word).filter { $0 != fix }
            return
        }
        let request = DecodeRequest(before: String(textBefore.dropLast(word.count)), word: word, taps: taps,
                                    keys: keyMap, autocorrect: autocorrectOn && rejectedWord == nil && !isKnown(word))
        // Mid-word this is the quick estimate only; the full check runs once
        // the word is finished (see `requestLateFix`).
        correctionWord = nil
        if pendingCorrection != nil { pendingCorrection = nil }
        predictor.refresh(request) { [weak self] result in
            guard let self, result.word == self.currentWord else { return }
            if result.suggestions != self.suggestions { self.suggestions = result.suggestions }
        }
    }

    /// Hangul bar: a pending fix ("typed", fix, one more), else completions
    /// and fixes; plus the European word the same taps spell, when there is one.
    private func refreshHangulBar() {
        let word = hangulWord
        var korean: [String]
        var fix: String?
        if KoreanDecoder.shared.isLoaded, !word.isEmpty {
            let canFix = autocorrectOn && !isKnown(word)
            fix = KoreanDecoder.shared.decode(word, taps: hangulTaps, keys: keyMap, autocorrect: canFix, full: true)?.correction
            korean = KoreanDecoder.shared.decode(word, taps: hangulTaps, keys: keyMap, autocorrect: false, full: false)?
                .suggestions.filter { $0 != fix } ?? []
        } else {
            korean = KoreanWords.shared.complete(word)
        }
        correctionWord = word
        if fix != pendingCorrection { pendingCorrection = fix }
        if korean != suggestions { suggestions = korean }
        // The same taps as Latin letters, when they're the whole word.
        let letters = String(hangulTaps.map(\.letter))
        guard predictor.isReady, letters.count >= 2, HangulComposer.qwertyKey(word) == letters else { return }
        let request = DecodeRequest(before: "", word: letters, taps: hangulTaps, keys: keyMap, autocorrect: true)
        predictor.latinWord(request) { [weak self] latin in
            guard let self, let latin, self.mode == .hangul, self.hangulWord == word else { return }
            // Letters that spell the word exactly always show; a fixed Latin
            // word only when Korean can't explain the taps (no word, no fix).
            if latin != letters && (KoreanDecoder.shared.isWord(word) || self.pendingCorrection != nil) { return }
            var list = korean.filter { $0 != latin }
            if self.pendingCorrection != nil { list.insert(latin, at: 0) } else { list = Array(list.prefix(2)) + [latin] }
            if list != self.suggestions { self.suggestions = list }
        }
    }

    private func correction(for word: String) -> String? {
        autocorrectOn && rejectedWord == nil && !isKnown(word) ? Suggester.autocorrection(for: word) : nil
    }

    /// The setting, unless the text field asks for no autocorrection
    /// (URLs, email addresses, code, search fields in some apps).
    private var autocorrectOn: Bool {
        settings.autocorrect && proxy?.autocorrectionType != .no
    }

    private func updateAutoShift() {
        guard shift != .locked, let proxy else { return }
        // Japanese and Korean have no capitals (Hangul's shift is for ㄲ ㅃ…).
        guard !mode.isAsian else {
            if shift != .off { shift = .off }
            return
        }
        let before = textBefore
        let wantsCap: Bool
        switch settings.autoCapitalize ? proxy.autocapitalizationType ?? .sentences : .none {
        case .none: wantsCap = false
        case .allCharacters: wantsCap = true
        case .words: wantsCap = before.isEmpty || before.last?.isWhitespace == true
        default:
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            wantsCap = trimmed.isEmpty || before.hasSuffix("\n")
                || ([".", "!", "?"].contains(trimmed.last.map(String.init) ?? "") && before.last == " ")
        }
        shift = wantsCap ? .on : .off
    }
}
