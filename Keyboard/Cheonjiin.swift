import Foundation

/// Cheonjiin (천지인), the 12-key Hangul pad: vowels are built from three
/// strokes, ㅣ (person), ㆍ (sky) and ㅡ (earth): ㅣ+ㆍ → ㅏ, ㆍ+ㅡ → ㅗ, ㅡ+ㆍ+ㆍ → ㅠ.
/// Each consonant key cycles through its letters on repeated taps
/// (ㄱ → ㅋ → ㄲ). To type the same consonant twice in a row, tap → between.
///
/// Built on HangulComposer: every tap first undoes what the current unit
/// (a consonant being cycled, or a vowel being stroked) put in the document,
/// then types its new jamo, so syllables form exactly as on Dubeolsik.
struct Cheonjiin {
    /// Key label → what repeated taps cycle through.
    static let cycles: [String: [Character]] = [
        "ㄱㅋ": ["ㄱ", "ㅋ", "ㄲ"], "ㄴㄹ": ["ㄴ", "ㄹ"], "ㄷㅌ": ["ㄷ", "ㅌ", "ㄸ"],
        "ㅂㅍ": ["ㅂ", "ㅍ", "ㅃ"], "ㅅㅎ": ["ㅅ", "ㅎ", "ㅆ"], "ㅈㅊ": ["ㅈ", "ㅊ", "ㅉ"], "ㅇㅁ": ["ㅇ", "ㅁ"],
    ]
    static let strokes: Set<String> = ["ㅣ", "ㆍ", "ㅡ"]
    /// Punctuation key, cycled the same way.
    static let punctuation: [Character] = [".", ",", "?", "!"]
    static let punctuationKey = ".,?!"

    /// Stroke sequences and the vowel they make.
    static let vowels: [String: Character] = [
        "ㅣ": "ㅣ", "ㅡ": "ㅡ",
        "ㅣㆍ": "ㅏ", "ㅣㆍㆍ": "ㅑ", "ㆍㅣ": "ㅓ", "ㆍㆍㅣ": "ㅕ",
        "ㆍㅡ": "ㅗ", "ㆍㆍㅡ": "ㅛ", "ㅡㆍ": "ㅜ", "ㅡㆍㆍ": "ㅠ",
        "ㅣㆍㅣ": "ㅐ", "ㆍㅣㅣ": "ㅔ", "ㅣㆍㆍㅣ": "ㅒ", "ㆍㆍㅣㅣ": "ㅖ",
        "ㆍㅡㅣ": "ㅚ", "ㆍㅡㅣㆍ": "ㅘ", "ㆍㅡㅣㆍㅣ": "ㅙ",
        "ㅡㆍㅣ": "ㅟ", "ㅡㆍㆍㅣ": "ㅝ", "ㅡㆍㆍㅣㅣ": "ㅞ", "ㅡㅣ": "ㅢ",
    ]
    /// Shown while the strokes don't make a vowel yet.
    static let dots: [String: String] = ["ㆍ": "ㆍ", "ㆍㆍ": "ᆢ"]

    typealias Edit = (delete: Int, insert: String)

    private(set) var composer = HangulComposer()
    /// A lone ㆍ or ᆢ after the syllable, waiting for its next stroke.
    private var dot = ""
    /// What the document and composer looked like before the current unit.
    private var base: (composer: HangulComposer, text: String)?
    private var unitKey: String?
    private var unitIndex = 0
    private var unitStrokes = ""
    /// Characters at the end of the document written since `base`, counting
    /// the base text itself (a syllable the unit finished stays in it).
    private var unitSpan = 0

    /// The text this pad controls at the end of the document.
    var text: String { composer.text + dot }
    var isEmpty: Bool { composer.isEmpty && dot.isEmpty }
    /// A consonant is being cycled or a vowel stroked: → ends it.
    var inUnit: Bool { unitKey != nil }

    static func handles(_ key: String) -> Bool {
        cycles[key] != nil || strokes.contains(key) || key == punctuationKey
    }

    mutating func reset() {
        composer.reset()
        dot = ""
        endUnit()
    }

    /// Ends the current unit: the next tap on the same key starts a new
    /// letter instead of cycling (the → key).
    mutating func endUnit() {
        base = nil
        unitKey = nil
        unitIndex = 0
        unitStrokes = ""
    }

    /// One tap on a pad key. Returns the edits to make, in order.
    mutating func tap(_ key: String) -> [Edit] {
        if key == Self.punctuationKey {
            return cyclePunctuation()
        }
        if let letters = Self.cycles[key] {
            let again = unitKey == key
            let index = again ? (unitIndex + 1) % letters.count : 0
            var edits = again ? undoUnit() : startUnit(key)
            unitIndex = index
            edits.append(track(composer.type(letters[index])))
            return edits
        }
        // A stroke: continue this vowel if the strokes still make one.
        let candidate = (unitKey == "vowel" ? unitStrokes : "") + key
        let continues = unitKey == "vowel" && (Self.vowels[candidate] != nil || Self.dots[candidate] != nil)
        var edits = continues ? undoUnit() : startUnit("vowel")
        unitStrokes = continues ? candidate : key
        if let vowel = Self.vowels[unitStrokes] {
            edits.append(track(composer.type(vowel)))
        } else if let d = Self.dots[unitStrokes] {
            dot = d
            edits.append(track((0, d)))
        }
        return edits
    }

    /// Keeps `unitSpan` in step with an edit made inside the unit.
    private mutating func track(_ edit: Edit) -> Edit {
        unitSpan += edit.insert.count - edit.delete
        return edit
    }

    /// Backspace: a waiting dot first, then one jamo of the syllable. Nil
    /// when there's nothing left of ours (the keyboard deletes normally).
    mutating func backspace() -> Edit? {
        endUnit()
        if !dot.isEmpty {
            let n = dot.count
            dot = ""
            return (n, "")
        }
        return composer.backspace()
    }

    private var punctuationIndex = 0

    private mutating func cyclePunctuation() -> [Edit] {
        if unitKey == Self.punctuationKey {
            punctuationIndex = (punctuationIndex + 1) % Self.punctuation.count
            return [(1, String(Self.punctuation[punctuationIndex]))]
        }
        reset()
        unitKey = Self.punctuationKey
        punctuationIndex = 0
        return [(0, ".")]
    }

    /// Starts a new unit from the current state (dropping a lone dot that
    /// never became a vowel).
    private mutating func startUnit(_ key: String) -> [Edit] {
        var edits: [Edit] = []
        if !dot.isEmpty {
            edits.append((dot.count, ""))
            dot = ""
        }
        if unitKey == Self.punctuationKey { composer.reset() }
        base = (composer, composer.text)
        unitSpan = composer.text.count
        unitKey = key
        unitIndex = 0
        unitStrokes = ""
        return edits
    }

    /// Puts the document and composer back as they were before this unit.
    private mutating func undoUnit() -> [Edit] {
        guard let base else { return [] }
        let edit: Edit = (unitSpan, base.text)
        composer = base.composer
        dot = ""
        unitSpan = base.text.count
        return [edit]
    }
}
