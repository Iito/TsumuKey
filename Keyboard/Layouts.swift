import CoreGraphics

enum KeyAction: Hashable {
    case text(String)
    case shift, backspace, space, returnKey
    case toNumpad, toLetters, globe
    /// Tap: switch between Latin and kana. Hold: settings and keyboards.
    case language
    case emoji
    /// Moves the cursor by this many characters.
    case cursor(Int)
    /// Kana: cycles the last character through ゛, ゜ and small forms.
    case kanaModifier
    /// Symbols layout: switches between its two pages.
    case symbolPage
}

/// Non-text choices that can appear in a long-press popup.
enum MenuAction: Hashable {
    case emoji, settings, oneHanded
    case layout(LetterLayout)
    case kana, romaji, hangul

    /// Shown as text when set, otherwise `symbol` is drawn as an icon.
    var title: String? {
        switch self {
        case .layout(let layout): return layout.name
        case .kana: return "かな"
        case .romaji: return "ローマ字"
        case .hangul: return "한국어"
        case .settings: return "Keyboard Settings…"
        default: return nil
        }
    }

    var symbol: String {
        switch self {
        case .emoji: return "face.smiling"
        case .settings: return "gearshape"
        case .oneHanded: return "keyboard.onehanded.right"
        case .layout, .kana, .romaji, .hangul: return "keyboard"
        }
    }
}

struct Key: Hashable {
    var action: KeyAction
    /// Small symbol drawn in the key's corner (when hints are on).
    var hint: String? = nil
    /// SF Symbol drawn in the corner instead of a text hint. Always shown,
    /// because it marks a feature with no other way in.
    var hintIcon: String? = nil
    /// Show `hint` even when symbol hints are turned off (digits on the top
    /// row when there's no number row: otherwise numbers would be hidden).
    var alwaysShowHint = false
    /// Long-press options, in order.
    var alternates: [String] = []
    /// Long-press actions, shown before `alternates`.
    var actions: [MenuAction] = []
    /// Kana flick: center, left, up, right, down ("" for none).
    var flicks: [String] = []
    /// Width in grid units; a full row is 10 units wide.
    var units: CGFloat = 1
    /// Letter keys only, set when the grid is laid out: for label colours.
    var spot: LetterSpot? = nil
}

enum RowItem: Hashable {
    case key(Key)
    case gap(CGFloat)
}

enum Layouts {
    /// Placeholder in `positionSymbols` for the user's chosen currency.
    private static let currencySlot = "¤"

    // Symbols are tied to the key POSITION, not the letter, so a symbol stays
    // in the same physical spot in every layout. The first one is the corner
    // hint; the rest only show on long-press.
    private static let positionSymbols: [[[String]]] = [
        [["%"], ["\\", "~"], ["|"], ["=", "≠", "^"], ["["], ["]"], ["<", "«"], [">", "»"], ["{"], ["}"]],
        [["@"], ["#"], [currencySlot], ["_"], ["&"], ["-"], ["+"], ["("], [")"], ["`"]],
        [["*"], ["\""], ["'"], [":"], [";"], ["!"], ["?"]],
    ]

    // Accents follow the letter. French variants come first because they are
    // the ones typed most here.
    private static let accents: [String: [String]] = [
        "a": ["à", "â", "æ", "á", "ä", "ã", "å", "ā"],
        "c": ["ç", "ć", "č"],
        "e": ["é", "è", "ê", "ë", "ē", "ė", "ę"],
        "i": ["î", "ï", "í", "ì", "ī"],
        "o": ["ô", "œ", "ö", "ó", "ò", "õ", "ø", "ō"],
        "u": ["ù", "û", "ü", "ú", "ū"],
        "y": ["ÿ", "ý"],
        "n": ["ñ", "ń"],
        "s": ["ß", "ś", "š"],
        "z": ["ž", "ź", "ż"],
        "l": ["ł"],
        "'": ["’", ";"],
    ]

    // Number row: no corner hints, long-press shows only fractions.
    private static let numberRow: [Key] = [
        ("1", ["½", "⅓", "¼", "⅕", "⅙", "⅛"]),
        ("2", ["⅔", "⅖"]),
        ("3", ["¾", "⅗", "⅜"]),
        ("4", ["⅘"]),
        ("5", ["⅚", "⅝"]),
        ("6", []),
        ("7", ["⅞"]),
        ("8", []),
        ("9", []),
        ("0", []),
    ].map { Key(action: .text($0.0), alternates: $0.1) }

    /// `romaji`: the same keys typing Japanese; ⚙ then leads back to Latin.
    static func letters(_ settings: KeyboardSettings, showGlobe: Bool, romaji: Bool = false,
                        field: FieldKind = .text) -> [[RowItem]] {
        let rows = settings.layout.rows

        // Bottom row: 7 letters between 1.5-wide shift and backspace; more
        // letters (Dvorak's 9) shrink everything to fit the 10 units.
        let bottomCount = CGFloat(rows[2].count)
        let edge: CGFloat = bottomCount > 7 ? 1 : 1.5
        let bottomUnits = min(1, (10 - 2 * edge) / bottomCount)

        func letterKeys(_ row: Int) -> [RowItem] {
            rows[row].enumerated().map { index, char in
                let letter = String(char)
                let units = row == 2 ? bottomUnits : 1
                // Symbols belong to positions; rows longer than usual reuse the last ones.
                // QWERTZ is German first: umlauts and ß lead the accents.
                var accented = accents[letter] ?? []
                if settings.layout == .qwertz {
                    let german = accented.filter { "äöüß".contains($0) }
                    accented = german + accented.filter { !german.contains($0) }
                }
                let slots = positionSymbols[row]
                var symbols = slots[min(index, slots.count - 1)]
                if symbols == [currencySlot] {
                    // Chosen currency first, then the other common ones.
                    symbols = [settings.currency] + KeyboardSettings.currencies.prefix(5).filter { $0 != settings.currency }
                }
                // No number row: the top row carries the digits instead.
                if row == 0 && !settings.numberRow {
                    let digit = String((index + 1) % 10)
                    return .key(Key(action: .text(letter), hint: digit, alwaysShowHint: true,
                                    alternates: [digit] + symbols + accented, units: units))
                }
                return .key(Key(action: .text(letter), hint: symbols[0],
                                alternates: symbols + accented, units: units))
            }
        }

        // QWERTY's middle row has 9 keys, so it gets half-key gaps to stay centered.
        let middleKeys = letterKeys(1)
        let indent = (10 - CGFloat(middleKeys.count)) / 2
        let middle: [RowItem] = indent > 0 ? [.gap(indent)] + middleKeys + [.gap(indent)] : middleKeys

        let fixed: CGFloat = 1.25 + 1 + 1 + 1 + 1.75 + (showGlobe ? 1 : 0)
        var bottom: [RowItem] = [
            .key(Key(action: .toNumpad, units: 1.25)),
        ]
        if showGlobe { bottom.append(.key(Key(action: .globe))) }
        bottom += [
            .key(Key(action: .language, hint: romaji ? "A" : settings.asianLanguage.keyHint,
                     alwaysShowHint: true)),
        ]
        // Web addresses and email: "www." or "@" where the comma was (the
        // comma and emoji on its long-press), domain endings on the period's.
        switch field {
        case .text:
            bottom += [
                .key(Key(action: .text(","), hintIcon: "face.smiling", actions: [.emoji, .oneHanded])),
                .key(Key(action: .space, units: 10 - fixed)),
                .key(Key(action: .text("."), hint: "?", alternates: ["?", "!", "…", "/"])),
            ]
        case .url:
            bottom += [
                .key(Key(action: .text("www."), hintIcon: "face.smiling", alternates: [","], actions: [.emoji, .oneHanded])),
                .key(Key(action: .space, units: 10 - fixed)),
                .key(Key(action: .text("."), alternates: Domains.web)),
            ]
        case .email:
            bottom += [
                .key(Key(action: .text("@"), hintIcon: "face.smiling", alternates: [","], actions: [.emoji, .oneHanded])),
                .key(Key(action: .space, units: 10 - fixed)),
                .key(Key(action: .text("."), alternates: Domains.mail)),
            ]
        }
        bottom += [
            .key(Key(action: .returnKey, units: 1.75)),
        ]

        var result: [[RowItem]] = []
        if settings.numberRow { result.append(numberRow.map { .key($0) }) }
        result += [
            letterKeys(0),
            middle,
            [.key(Key(action: .shift, units: edge))] + letterKeys(2) + [.key(Key(action: .backspace, units: edge))],
            bottom,
        ]
        return result
    }

    /// Dubeolsik Hangul, like the iOS Korean keyboard: consonants on the
    /// left, vowels on the right; shift gives ㄲ ㄸ ㅃ ㅆ ㅉ ㅒ ㅖ (also on
    /// long-press). ⚙ leads back to Latin.
    static func hangul(_ settings: KeyboardSettings, showGlobe: Bool) -> [[RowItem]] {
        let rows = ["ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ", "ㅋㅌㅊㅍㅠㅜㅡ"]
        func keys(_ row: Int, units: CGFloat = 1) -> [RowItem] {
            rows[row].map { c in
                let jamo = String(c)
                let tense = HangulComposer.shifted[jamo]
                // Phonetic overlay: the key's sound in the corner, always shown.
                if settings.hangulRomaja {
                    return .key(Key(action: .text(jamo), hint: Romaja.letter(for: c), alwaysShowHint: true,
                                    alternates: tense.map { [$0] } ?? [], units: units))
                }
                return .key(Key(action: .text(jamo), hint: tense, alternates: tense.map { [$0] } ?? [], units: units))
            }
        }
        let fixed: CGFloat = 1.25 + 1 + 1 + 1 + 1.75 + (showGlobe ? 1 : 0)
        var bottom: [RowItem] = [.key(Key(action: .toNumpad, units: 1.25))]
        if showGlobe { bottom.append(.key(Key(action: .globe))) }
        bottom += [
            .key(Key(action: .language, hint: "A", alwaysShowHint: true)),
            .key(Key(action: .text(","), hintIcon: "face.smiling", actions: [.emoji, .oneHanded])),
            .key(Key(action: .space, units: 10 - fixed)),
            .key(Key(action: .text("."), hint: "?", alternates: ["?", "!", "…", "/"])),
            .key(Key(action: .returnKey, units: 1.75)),
        ]
        var result: [[RowItem]] = []
        if settings.numberRow { result.append(numberRow.map { .key($0) }) }
        result += [
            keys(0),
            [.gap(0.5)] + keys(1) + [.gap(0.5)],
            [.key(Key(action: .shift, units: 1.5))] + keys(2) + [.key(Key(action: .backspace, units: 1.5))],
            bottom,
        ]
        return result
    }

    /// Cheonjiin (천지인), the 12-key Hangul pad: ㅣ ㆍ ㅡ build the vowels,
    /// each consonant key cycles on repeated taps (ㄱ → ㅋ → ㄲ); → separates
    /// two taps of the same key. Same frame as the kana pad.
    static func cheonjiin(_ settings: KeyboardSettings, showGlobe: Bool) -> [[RowItem]] {
        /// With the phonetic overlay, each key's sounds in the corner (ㄱㅋ → g k).
        func p(_ label: String) -> RowItem {
            let sounds = settings.hangulRomaja && label != Cheonjiin.punctuationKey && label != "ㆍ"
                ? label.compactMap { Romaja.letter(for: $0) }.joined(separator: " ") : nil
            return .key(Key(action: .text(label), hint: sounds, alwaysShowHint: sounds != nil, units: 2))
        }
        func k(_ action: KeyAction, hint: String? = nil, units: CGFloat = 2) -> RowItem {
            .key(Key(action: action, hint: hint, alwaysShowHint: true, units: units))
        }
        return [
            [k(showGlobe ? .globe : .cursor(-1)), p("ㅣ"), p("ㆍ"), p("ㅡ"), k(.backspace)],
            [k(.toNumpad), p("ㄱㅋ"), p("ㄴㄹ"), p("ㄷㅌ"), k(.cursor(1))],
            [k(.emoji), p("ㅂㅍ"), p("ㅅㅎ"), p("ㅈㅊ"), k(.space)],
            [k(.language, hint: "A"), p(Cheonjiin.punctuationKey), p("ㅇㅁ"), k(.returnKey, units: 4)],
        ]
    }

    /// Japanese 12-key flick pad, like the iPhone's: tap a kana for its
    /// "a" column, flick left/up/right/down for i/u/e/o. Every key is 2 units.
    static func kana(showGlobe: Bool) -> [[RowItem]] {
        func f(_ flicks: String) -> RowItem {
            let parts = flicks.split(separator: " ", omittingEmptySubsequences: false).map { $0 == "_" ? "" : String($0) }
            return .key(Key(action: .text(parts[0]), flicks: parts, units: 2))
        }
        func k(_ action: KeyAction, hint: String? = nil) -> RowItem {
            .key(Key(action: action, hint: hint, alwaysShowHint: true, units: 2))
        }
        return [
            [k(showGlobe ? .globe : .cursor(-1)), f("あ い う え お"), f("か き く け こ"), f("さ し す せ そ"), k(.backspace)],
            [k(.toNumpad), f("た ち つ て と"), f("な に ぬ ね の"), f("は ひ ふ へ ほ"), k(.cursor(1))],
            [k(.emoji), f("ま み む め も"), f("や （ ゆ ） よ"), f("ら り る れ ろ"), k(.space)],
            [k(.language, hint: "A"), k(.kanaModifier), f("わ を ん ー _"), f("、 。 ？ ！ …"), k(.returnKey)],
        ]
    }

    /// Next form for the ゛゜小 key: か→が→か, は→ば→ぱ→は, つ→っ→づ→つ…
    static func kanaVariant(_ c: Character) -> Character? {
        for cycle in kanaCycles {
            let chars = Array(cycle)
            if let i = chars.firstIndex(of: c) { return chars[(i + 1) % chars.count] }
        }
        return nil
    }

    private static let kanaCycles: [String] = {
        var cycles = ["あぁ", "いぃ", "うぅゔ", "えぇ", "おぉ", "やゃ", "ゆゅ", "よょ", "わゎ", "つっづ"]
        for (plain, voiced) in zip("かきくけこさしすせそたちてと", "がぎぐげござじずぜぞだぢでど") {
            cycles.append(String([plain, voiced]))
        }
        for (plain, (voiced, half)) in zip("はひふへほ", zip("ばびぶべぼ", "ぱぴぷぺぽ")) {
            cycles.append(String([plain, voiced, half]))
        }
        return cycles
    }()

    /// iOS-style symbols: digits on top, then punctuation; "#+=" flips to a
    /// second page of brackets and math. `page` is 1 or 2.
    static func symbols(_ settings: KeyboardSettings, page: Int, showGlobe: Bool) -> [[RowItem]] {
        func t(_ s: String, _ alts: [String] = [], units: CGFloat = 1) -> RowItem {
            .key(Key(action: .text(s), alternates: alts, units: units))
        }
        let others = KeyboardSettings.currencies.filter { $0 != settings.currency }
        let top: [RowItem]
        let middle: [RowItem]
        if page == 1 {
            top = numberRow.map { .key($0) }
            middle = [t("-", ["–", "—", "•"]), t("/", ["\\"]), t(":"), t(";"), t("("), t(")"),
                      t(settings.currency, Array(others.prefix(6))), t("&", ["§"]), t("@"), t("\"", ["«", "»", "“", "”"])]
        } else {
            top = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { t($0) }
            middle = [t("_"), t("\\"), t("|"), t("~"), t("<", ["≤"]), t(">", ["≥"]),
                      t("€"), t("£"), t("¥"), t("•", ["°", "·"])]
        }
        let punctuation: [RowItem] = [t(".", ["…"], units: 1.4), t(",", units: 1.4), t("?", ["¿"], units: 1.4),
                                       t("!", ["¡"], units: 1.4), t("'", ["’", "‘"], units: 1.4)]
        let third: [RowItem] = [.key(Key(action: .symbolPage, units: 1.5))] + punctuation
            + [.key(Key(action: .backspace, units: 1.5))]
        let fixed: CGFloat = 1.5 + 1.75 + (showGlobe ? 1 : 0)
        var bottom: [RowItem] = [.key(Key(action: .toLetters, units: 1.5))]
        if showGlobe { bottom.append(.key(Key(action: .globe))) }
        bottom += [.key(Key(action: .space, units: 10 - fixed)), .key(Key(action: .returnKey, units: 1.75))]
        return [top, middle, third, bottom]
    }

    /// Calculator-style pad: digits in a 3x3 grid, operators on the left,
    /// editing keys on the right. Every key is 2 units wide.
    static let numpad: [[RowItem]] = {
        func k(_ action: KeyAction, _ alts: [String] = []) -> RowItem {
            .key(Key(action: action, hint: alts.first, alternates: alts, units: 2))
        }
        func t(_ s: String, _ alts: [String] = []) -> RowItem { k(.text(s), alts) }
        return [
            [t("+", ["±"]), t("1"), t("2"), t("3"), k(.backspace)],
            [t("-", ["–", "—", "_"]), t("4"), t("5"), t("6"), k(.space)],
            [t("*", ["/", "×", "÷", "^"]), t("7"), t("8"), t("9"), k(.returnKey)],
            [k(.toLetters), t(",", [":", ";"]), t("0"), t(".", ["…", "°"]), t("=", ["%", "≠", "≈"])],
        ]
    }()
}
