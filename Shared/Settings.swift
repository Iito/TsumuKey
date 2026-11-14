import Foundation
import UIKit

/// Settings shared between the app and the keyboard through the App Group.
/// The keyboard can only read them with Full Access on; otherwise it
/// silently falls back to defaults.
enum SharedSettings {
    static let appGroup: String = {
        // AltStore and SideStore rename the App Group per Apple ID and note
        // the new name in Info.plist (ALTAppGroups), but not always in the
        // keyboard's own Info.plist: then it's only in the containing app's,
        // two folders up (TsumuKey.app/PlugIns/Keyboard.appex). The first name
        // this process can actually open wins.
        func noted(_ info: [String: Any]?) -> [String] { info?["ALTAppGroups"] as? [String] ?? [] }
        let appInfo = NSDictionary(contentsOf: Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")) as? [String: Any]
        let candidates = noted(Bundle.main.infoDictionary) + noted(appInfo) + ["group.com.tsumukey"]
        return candidates.first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        } ?? candidates[0]
    }()
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// Darwin notification (no payload) posted when settings change, so an
    /// open keyboard rereads them without being closed and reopened.
    static let changed = "com.tsumukey.settingsChanged" as CFString

    /// Set by the app while its own "Try it here" field is focused: the keyboard
    /// then offers a hide button (it can't tell which app it's typing in).
    static let inAppField = "com.tsumukey.inAppField" as CFString
    static let inAppFieldKey = "inAppFieldFocused"

    static func setInAppField(_ focused: Bool) {
        defaults.set(focused, forKey: inAppFieldKey)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(inAppField), nil, nil, true)
    }

    static func save<T: Encodable>(_ value: T, key: String, notify: Bool = true) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
        if notify {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFNotificationName(changed), nil, nil, true)
        }
    }
}

/// What the keyboard saw the last time it opened, written by the keyboard
/// into the App Group so the app can show whether settings reach it. Without
/// Full Access the write never reaches the app, which then shows no report.
struct KeyboardReport: Codable, Equatable {
    var build: String
    var openedAt: Date
    var fullAccess: Bool
    var settingsFound: Bool
    var layout: String
    private static let key = "keyboardReport"
    static func load() -> KeyboardReport? { SharedSettings.load(Self.self, key: key) }
    // Not a settings change: no notification (the keyboard writes this on every open).
    func save() { SharedSettings.save(self, key: Self.key, notify: false) }
}

enum LetterLayout: String, Codable, CaseIterable, Identifiable {
    case qwerty, colemak, azerty, qwertz, dvorak, bepo, workman, norman, maltron

    var id: Self { self }
    var name: String {
        switch self {
        case .qwerty: return "QWERTY"
        case .colemak: return "Colemak"
        case .azerty: return "AZERTY"
        case .qwertz: return "QWERTZ"
        case .dvorak: return "Dvorak"
        case .bepo: return "Bépo"
        case .workman: return "Workman"
        case .norman: return "Norman"
        case .maltron: return "Maltron"
        }
    }

    /// The three letter rows, top to bottom.
    var rows: [String] {
        switch self {
        case .qwerty: return ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        // Colemak's ";" slot holds an apostrophe instead: French and English
        // need it constantly, and ";" is still one long-press away.
        case .colemak: return ["qwfpgjluy'", "arstdhneio", "zxcvbkm"]
        // French phone AZERTY, with the apostrophe at the end of the bottom row.
        case .azerty: return ["azertyuiop", "qsdfghjklm", "wxcvbn'"]
        // German/Swiss: Z and Y swapped. Umlauts are on long-press (a, o, u).
        case .qwertz: return ["qwertzuiop", "asdfghjkl", "yxcvbnm"]
        // Dvorak as on a hardware keyboard, minus ";" (long-press on '):
        // the bottom row has 9 letters, so its keys are a little narrower.
        case .dvorak: return ["',.pyfgcrl", "aoeuidhtns", "qjkxbmwvz"]
        // French Bépo in its letter order. É and À keep their own keys; È, Ê
        // and Ç move to long-press (e, c), and "," "." live on the bottom row.
        case .bepo: return ["bépovdljzw", "auiectsrnm", "àyxk'qghf"]
        // Workman and Norman: ";" becomes an apostrophe, as in Colemak.
        case .workman: return ["qdrwbjfup'", "ashtgyneoi", "zxmcvkl"]
        case .norman: return ["qwdfkjurl'", "asetgynioh", "zxcvbpm"]
        // Maltron puts E on a thumb key; a phone has none, so E sits mid
        // bottom row with the letters Maltron keeps there (J G W K X).
        case .maltron: return ["qpycbvmuzl", "anisfdthor", "jgewkx'"]
        }
    }
}

struct KeyboardSettings: Codable, Equatable {
    var layout: LetterLayout = .qwerty
    var numberRow = true
    /// Small symbol in each key's corner. Long-press works either way.
    var showSymbolHints = true
    /// Hide-keyboard button at the right end of the suggestion bar, in every app
    /// (it always shows in the app's own test field).
    var hideKeyboardButton = false
    /// Skin tone for emoji that have them: 0 = default yellow, 1...5 light to dark.
    var emojiSkinTone = 0
    /// The currency on the D-position key's corner.
    var currency = "$"
    /// Height of one key row in points (the system keyboard is about 44–46).
    var rowHeight: Double = 50
    var autocorrect = true
    /// Like the iOS keyboard settings (which iOS doesn't share with other
    /// keyboards): capitals after a full stop, double-tap shift for caps lock,
    /// double-tap space for ". ", the letter shown above a pressed key, and
    /// the two below.
    var autoCapitalize = true
    var capsLock = true
    var periodShortcut = true
    var characterPreview = true
    /// Swipe typing: slide across the letters of a word without lifting.
    var swipeTyping = true
    /// Key taps vibrate (and flick or cursor moves tick). Needs Full Access.
    var haptics = true
    var hapticStyle: HapticStyle = .light
    /// 0.2...1, how strong each key tap is.
    var hapticStrength: Double = 1
    /// Curly quotes and apostrophes, "--" to "—".
    var smartPunctuation = true
    /// "12*3=" offers 36 in the bar.
    var mathResults = true
    /// "pizza" offers 🍕 in the bar.
    var emojiSuggestions = true
    /// "100$ in €=" in the bar. Off by default: the app then fetches daily
    /// rates from the European Central Bank (the keyboard stays offline).
    var currencyConversion = false
    var theme: KeyboardTheme = .system
    /// What a tap on 123 opens; holding it opens the other one.
    var numberKeyTap: NumberKeyTap = .numpad
    var letterColors = LetterColors()
    /// Kanji/kana for romaji words, offered in the ABC keyboard's bar.
    var japaneseInLatin = true
    /// How kana not yet converted show in the field.
    var japaneseComposition: JapaneseComposition = .plain
    /// How the ABC keyboard lists the Japanese word's other conversions.
    var japaneseChoices: JapaneseChoices = .grid
    /// The Japanese keyboard: the あ key and the ⚙︎ menu switch to this one.
    var japaneseInput: JapaneseInput = .kana
    /// The one Asian language next to the European ones: its keyboard is in
    /// the menu, and (Japanese) romaji in the ABC keyboard offers it.
    var asianLanguage: AsianLanguage = .japanese
    var koreanInput: KoreanInput = .dubeolsik
    /// Romanised Korean in the ABC keyboard offers the Hangul (annyeong → 안녕).
    var koreanInLatin = true
    /// Romaja under each Hangul key (ㄱ g, ㅏ a), for learners.
    var hangulRomaja = false
    /// Layouts listed when the settings key is held (1 to 3, in this order).
    /// The first is the default; `layout` is the one in use right now.
    var menuLayouts: [LetterLayout] = [.qwerty, .colemak, .azerty]
    /// Languages the bar and autocorrect use: 1 or 2. More would make
    /// autocorrect swap right words for look-alikes in another language.
    var predictionLanguages: [PredictionLanguage] = [.english, .french]
    /// Detect the language from the words typed: autocorrect searches the word
    /// lists of every language in `predictionLanguages` (up to all of them), and
    /// the model gets the two of them your recent words read as.
    var autoLanguages = true
    /// Which model judges corrections (Gemma, or a small ranker; bench option).
    var correctionModel: CorrectionModel = .dense

    static let maxMenuLayouts = 3
    static let maxPredictionLanguages = 2
    /// Without detection: the first two of the list (with detection the
    /// list is what it may pick from, up to all of them).
    var manualLanguages: [PredictionLanguage] { Array(predictionLanguages.prefix(Self.maxPredictionLanguages)) }
    static let rowHeightRange: ClosedRange<Double> = 40...64

    init() {}

    // Decoded field by field so settings saved by an older version (missing
    // newer fields) keep their values instead of resetting everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeyboardSettings()
        layout = try c.decodeIfPresent(LetterLayout.self, forKey: .layout) ?? d.layout
        numberRow = try c.decodeIfPresent(Bool.self, forKey: .numberRow) ?? d.numberRow
        showSymbolHints = try c.decodeIfPresent(Bool.self, forKey: .showSymbolHints) ?? d.showSymbolHints
        hideKeyboardButton = try c.decodeIfPresent(Bool.self, forKey: .hideKeyboardButton) ?? d.hideKeyboardButton
        emojiSkinTone = try c.decodeIfPresent(Int.self, forKey: .emojiSkinTone) ?? d.emojiSkinTone
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? d.currency
        rowHeight = try c.decodeIfPresent(Double.self, forKey: .rowHeight) ?? d.rowHeight
        autocorrect = try c.decodeIfPresent(Bool.self, forKey: .autocorrect) ?? d.autocorrect
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? d.autoCapitalize
        capsLock = try c.decodeIfPresent(Bool.self, forKey: .capsLock) ?? d.capsLock
        periodShortcut = try c.decodeIfPresent(Bool.self, forKey: .periodShortcut) ?? d.periodShortcut
        characterPreview = try c.decodeIfPresent(Bool.self, forKey: .characterPreview) ?? d.characterPreview
        swipeTyping = try c.decodeIfPresent(Bool.self, forKey: .swipeTyping) ?? d.swipeTyping
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        hapticStyle = try c.decodeIfPresent(HapticStyle.self, forKey: .hapticStyle) ?? d.hapticStyle
        hapticStrength = try c.decodeIfPresent(Double.self, forKey: .hapticStrength) ?? d.hapticStrength
        smartPunctuation = try c.decodeIfPresent(Bool.self, forKey: .smartPunctuation) ?? d.smartPunctuation
        mathResults = try c.decodeIfPresent(Bool.self, forKey: .mathResults) ?? d.mathResults
        emojiSuggestions = try c.decodeIfPresent(Bool.self, forKey: .emojiSuggestions) ?? d.emojiSuggestions
        currencyConversion = try c.decodeIfPresent(Bool.self, forKey: .currencyConversion) ?? d.currencyConversion
        theme = try c.decodeIfPresent(KeyboardTheme.self, forKey: .theme) ?? d.theme
        numberKeyTap = try c.decodeIfPresent(NumberKeyTap.self, forKey: .numberKeyTap) ?? d.numberKeyTap
        letterColors = try c.decodeIfPresent(LetterColors.self, forKey: .letterColors) ?? d.letterColors
        japaneseInLatin = try c.decodeIfPresent(Bool.self, forKey: .japaneseInLatin) ?? d.japaneseInLatin
        japaneseChoices = try c.decodeIfPresent(JapaneseChoices.self, forKey: .japaneseChoices) ?? d.japaneseChoices
        japaneseComposition = try c.decodeIfPresent(JapaneseComposition.self, forKey: .japaneseComposition) ?? d.japaneseComposition
        // Build 74 had "off" here; it's now Asian language "none".
        let japanese = try c.decodeIfPresent(String.self, forKey: .japaneseInput)
        japaneseInput = japanese.flatMap(JapaneseInput.init) ?? d.japaneseInput
        asianLanguage = try c.decodeIfPresent(AsianLanguage.self, forKey: .asianLanguage)
            ?? (japanese == "off" ? AsianLanguage.none : d.asianLanguage)
        koreanInput = try c.decodeIfPresent(KoreanInput.self, forKey: .koreanInput) ?? d.koreanInput
        koreanInLatin = try c.decodeIfPresent(Bool.self, forKey: .koreanInLatin) ?? d.koreanInLatin
        hangulRomaja = try c.decodeIfPresent(Bool.self, forKey: .hangulRomaja) ?? d.hangulRomaja
        // Settings from before the list: the layout in use goes on top.
        let menu = try c.decodeIfPresent([LetterLayout].self, forKey: .menuLayouts)
            ?? [layout] + d.menuLayouts.filter { $0 != layout }
        menuLayouts = menu.isEmpty ? d.menuLayouts : Array(menu.prefix(Self.maxMenuLayouts))
        let languages = try c.decodeIfPresent([PredictionLanguage].self, forKey: .predictionLanguages) ?? d.predictionLanguages
        autoLanguages = try c.decodeIfPresent(Bool.self, forKey: .autoLanguages) ?? d.autoLanguages
        predictionLanguages = languages.isEmpty ? d.predictionLanguages : Array(languages.prefix(PredictionLanguage.allCases.count))
        correctionModel = try c.decodeIfPresent(CorrectionModel.self, forKey: .correctionModel) ?? d.correctionModel
    }

    static let currencies = ["$", "€", "£", "¥", "₹", "₩", "₽", "₺", "₿", "¢"]
    private static let key = "keyboardSettings"

    static func load() -> KeyboardSettings { SharedSettings.load(Self.self, key: key) ?? KeyboardSettings() }
    func save() { SharedSettings.save(self, key: Self.key) }
}

/// Languages the keyboard can predict and correct in. One model and one word
/// list cover them all; the settings pick which ones are used.
enum PredictionLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en", french = "fr", german = "de", spanish = "es", italian = "it", portuguese = "pt"

    var id: Self { self }
    var name: String {
        switch self {
        case .english: return "English"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        }
    }
    /// Bit in the word list's per-word language mask.
    var bit: UInt8 { 1 << UInt8(Self.allCases.firstIndex(of: self)!) }
}

/// Gemma 3 270M (~100 MB), or a ~5 MB candidate ranker:
/// dense head, or mixture-of-experts head. Names carry the version of the
/// bundled .rank file: update them when Models/ranker-*.rank changes.
enum CorrectionModel: String, Codable, CaseIterable, Identifiable {
    case gemma, dense, moe

    var id: Self { self }
    var name: String {
        switch self {
        case .gemma: return "Gemma 3 (Transformer 18L × 4H, 141M params)"
        case .dense: return "Small (Transformer 2L × 4H, 4.3M params)"
        case .moe: return "Small (Transformer 2L × 4H, MoE 4 experts, 4.4M params)"
        }
    }

    /// What the picker offers; the MoE ranker has no suggestions and stays bench-only.
    static let choices: [CorrectionModel] = [.dense, .gemma]
}

/// Kana not yet converted, in the text field: underlined like the iOS
/// keyboard (marked text), or plain text edited in place. Plain: SwiftUI
/// text fields clear normally after Send; after marked text they keep
/// showing the old text.
enum JapaneseComposition: String, Codable, CaseIterable, Identifiable {
    case plain, underlined

    var id: Self { self }
    var name: String { self == .plain ? "Plain" : "Underlined" }
}

/// The Japanese word's other conversions in the ABC keyboard: a grid in
/// place of the keys (⌄ at the end of the bar, like iOS), or a list that
/// drops down from the word when it's held.
enum JapaneseChoices: String, Codable, CaseIterable, Identifiable {
    case grid, dropDown

    var id: Self { self }
    var name: String { self == .grid ? "Grid" : "Drop-down" }
}

enum JapaneseInput: String, Codable, CaseIterable, Identifiable {
    case kana, romaji

    var id: Self { self }
    var name: String { self == .kana ? "かな" : "ローマ字" }
}

/// "Other alphabet" in the app: one language with its own script (Japanese,
/// Korean), paired with the European prediction languages. None: the
/// language key cycles the layouts instead.
enum AsianLanguage: String, Codable, CaseIterable, Identifiable {
    case none, japanese, korean

    var id: Self { self }
    var name: String {
        switch self {
        case .none: return "None"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
    /// Corner hint on the ABC keyboard's language key.
    var keyHint: String? {
        switch self {
        case .none: return nil
        case .japanese: return "あ"
        case .korean: return "한"
        }
    }
}

enum KoreanInput: String, Codable, CaseIterable, Identifiable {
    case dubeolsik, cheonjiin

    var id: Self { self }
    var name: String { self == .dubeolsik ? "두벌식" : "천지인" }
}

enum NumberKeyTap: String, Codable, CaseIterable, Identifiable {
    case numpad, symbols

    var id: Self { self }
    var name: String { self == .numpad ? "Numpad" : "Symbols" }
}

enum KeyboardTheme: String, Codable, CaseIterable, Identifiable {
    case system, day, night

    var id: Self { self }
    var name: String {
        switch self {
        case .system: return "Match iPhone"
        case .day: return "Day"
        case .night: return "Night"
        }
    }
    var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .day: return .light
        case .night: return .dark
        }
    }
}

/// Where a letter key sits: its letter row (0 = top) and the x of its
/// center on the 10-unit grid. Used to colour groups of letters.
struct LetterSpot: Hashable {
    let row: Int
    let x: Double
}

/// How letter labels are coloured. One scheme at a time; vowels can be
/// coloured on top of any of them.
enum LetterScheme: String, Codable, CaseIterable, Identifiable {
    case none, all, rows, thumbs

    var id: Self { self }
    var name: String {
        switch self {
        case .none: return "Default"
        case .all: return "All keys"
        case .rows: return "By row"
        case .thumbs: return "By thumb"
        }
    }
}

/// Key label colours as hex ("#RRGGBB"). Every colour is kept even when its
/// scheme is off, so switching back restores the user's picks.
struct LetterColors: Codable, Equatable {
    var scheme: LetterScheme = .none
    /// Every key label, function keys included.
    var all = "#007AFF"
    var topRow = "#007AFF"
    var middleRow = "#34C759"
    var bottomRow = "#FF9500"
    var leftThumb = "#007AFF"
    var rightThumb = "#FF3B30"
    var vowelsOn = false
    var vowels = "#AF52DE"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LetterColors()
        scheme = try c.decodeIfPresent(LetterScheme.self, forKey: .scheme) ?? d.scheme
        all = try c.decodeIfPresent(String.self, forKey: .all) ?? d.all
        topRow = try c.decodeIfPresent(String.self, forKey: .topRow) ?? d.topRow
        middleRow = try c.decodeIfPresent(String.self, forKey: .middleRow) ?? d.middleRow
        bottomRow = try c.decodeIfPresent(String.self, forKey: .bottomRow) ?? d.bottomRow
        leftThumb = try c.decodeIfPresent(String.self, forKey: .leftThumb) ?? d.leftThumb
        rightThumb = try c.decodeIfPresent(String.self, forKey: .rightThumb) ?? d.rightThumb
        vowelsOn = try c.decodeIfPresent(Bool.self, forKey: .vowelsOn) ?? d.vowelsOn
        vowels = try c.decodeIfPresent(String.self, forKey: .vowels) ?? d.vowels
    }

    /// Latin vowels, and the Hangul vowel keys (Dubeolsik's right side).
    static let vowelLetters = "aeiouyàâäéèêëîïôöùûüÿæœㅏㅐㅑㅒㅓㅔㅕㅖㅗㅛㅜㅠㅡㅣ"

    /// nil keeps the theme's colour. `letter`/`spot` are set for letter keys only.
    func hex(letter: Character?, spot: LetterSpot?) -> String? {
        if vowelsOn, let letter, Self.vowelLetters.contains(letter) { return vowels }
        switch scheme {
        case .none: return nil
        case .all: return all
        case .rows:
            guard letter != nil, let spot else { return nil }
            return [topRow, middleRow, bottomRow][min(max(spot.row, 0), 2)]
        case .thumbs:
            // Split down the middle of the 10-unit grid; the middle key of an
            // offset row (QWERTY's G) goes to the left thumb that usually types it.
            guard letter != nil, let spot else { return nil }
            return spot.x <= 5 ? leftThumb : rightThumb
        }
    }
}

extension UIColor {
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

/// All delete-key timings in one place. The app edits them, the keyboard reads them.
struct DeleteTiming: Codable, Equatable {
    /// How long a press must last before it counts as a hold.
    var holdDelay: TimeInterval = 0.4
    /// Gap between character deletes while holding.
    var charRepeat: TimeInterval = 0.06
    /// Gap between word deletes during double-tap-and-hold.
    var wordRepeat: TimeInterval = 0.35
    /// Max time between releasing and pressing again for presses to chain
    /// into a "tap then hold" or "double tap and hold".
    var multiTapWindow: TimeInterval = 0.3

    private static let key = "deleteTiming"

    static func load() -> DeleteTiming { SharedSettings.load(Self.self, key: key) ?? DeleteTiming() }
    func save() { SharedSettings.save(self, key: Self.key) }
}

/// How a key tap feels. iOS doesn't let a keyboard set a vibration's length;
/// these are its tap styles, from a soft long thud to a short sharp click.
enum HapticStyle: String, Codable, CaseIterable, Identifiable {
    case soft, light, medium, heavy, rigid
    var id: Self { self }
    var name: String { rawValue.capitalized }

    var impact: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .soft: return .soft
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        case .rigid: return .rigid
        }
    }
}
