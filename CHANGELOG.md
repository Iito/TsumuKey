# TsumuKey changelog (BetterKeys until 0.5)

Versions are set in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
Bump the build number for every build installed on a phone and add an entry here.
The app shows its version at the bottom of the "Set up" section (from build 2 on).

## 0.5 (build 21), 2026-11-05
- Renamed BetterKeys → TsumuKey (紡ぎ "weaving" + key). New IDs without a personal
  name: app com.tsumukey, keyboard com.tsumukey.keyboard, UI tests
  com.tsumukey.uitests, App Group group.com.tsumukey, URL scheme tsumukey://,
  settings pasteboard com.tsumukey.settings. Project TsumuKey.xcodeproj, scheme TsumuKey.
- A new bundle ID is a new app to iOS: the keyboard has to be added again with
  Full Access, and settings and learned words start from defaults.

## 0.4 (build 20), 2026-11-05
Installed on both phones; tested on the iPhone 16 Pro Max (EN+FR): "pomm" now
offers pomme. Still open: "helo" offers heli/he'll/beli, not hello (a missed
letter costs more than a neighbouring-key slip; not new in this build).
- Bar: the completion one letter longer than the typed word is offered again
  ("pomm" → pomme, "Wohnu" → Wohnung). It was scored as a fix with a missed tap
  and lost to rarer, longer words (pommade, Wohnungssuche).

## 0.4 (build 19), 2026-11-05
Installed on the iPhone 16 Pro Max and tested there (testMenuAndLanguages):
⚙︎ menu panel, long-press "@" over A and "}" over P, German (Ich habe heute
keine → Lust, Ahnung, Zeit), Spanish (manz → manzana), German hidden with EN+FR.
Found: "pomm" missed pomme, "Wohnu" missed Wohnung (fixed in 20).
Not on the iPhone 15 (it went unreachable; it has build 18).
- Long-press: the key's symbol or digit (selected by default) now sits right
  above the pressed key; the other options run to its right, or to its left on
  keys too close to the right edge. The row used to be centred on the key, so
  the default option was off to the left.

## 0.4 (build 18), 2026-11-05
Installed on the iPhone 15 (not tested there).
- Dark mode: corner symbols are white (were grey). Custom letter colours are
  mixed with white just enough to read on the dark keys (luminance >= 0.4):
  #007AFF shows as #66AFFF, #FF3B30 as #FF8983. Saved colours and light mode unchanged.

## 0.4 (build 17), 2026-11-05
Installed on the iPhone 15 (not tested there).
- Dark colours match Gboard's night theme (measured from screenshots): keys
  #424242 (was #6B6B6B), function keys #303030, background #212121.
- The background is painted in Match iPhone too: iOS's frosted backdrop tinted
  the dark keyboard blue-grey.
- Space bar shows the prediction languages ("EN · FR"), like Gboard.

## 0.4 (build 16), 2026-11-05
Installed on the iPhone 15 (not tested there).
- Prediction languages get the same page as Layouts: a row opens the list,
  Edit to delete or reorder, "Add New Language" (up to 2, at least 1).

## 0.4 (build 15), 2026-11-05
Installed on the iPhone 15 (not tested there).
- Layouts page: deleting and reordering only work after tapping Edit (no
  swipe-to-delete, no long-press drag outside it).

## 0.4 (build 14), 2026-11-05
Installed on the iPhone 15 (not tested there).
- Layouts settings now work like iOS's Settings → Keyboards: a "Layouts" row
  opens its own page; Edit shows red delete buttons and drag handles, "Add New
  Layout" picks from the others. Top one is the default, up to 3.

## 0.4 (build 13), 2026-11-05
Installed on the iPhone 15 (not tested there).
- App: one "Layouts" list instead of the Layout picker plus the menu list. Drag
  to reorder; the top one is the default and the keyboard opens on it. Up to 3;
  the others are listed below with a + to add, swipe left to remove.
  Settings from older builds put the layout in use on top.

## 0.4 (build 12), 2026-11-05
Installed on the iPhone 15 (not tested there).
- Japanese keyboard setting: かな or ローマ字. The あ key and the ⚙︎ menu switch to
  that one only (was: whichever was used last; the menu listed both).

## 0.4 (build 11), 2026-11-05
Installed on the iPhone 15 (not tested there). Not on the iPhone 16 Pro Max yet (locked, then unreachable).
- Settings key menu (hold ⚙︎) looks like the iPhone's globe menu: "Keyboard
  Settings…", then the layouts picked in the app (up to 3, default QWERTY,
  Colemak, AZERTY), then かな and ローマ字; a checkmark on the one in use.
  App: new "Layouts in the keyboard menu" section.
- Prediction languages: pick 1 or 2 of English, French, German, Spanish (app
  section "Prediction languages", default English + French). The model is now
  Gemma 3 270M cut to a 64k vocabulary covering all four
  (gemma-3-270m-enfrdees64k-Q4_0.gguf, was enfr48k), and the word list stores
  each word's frequency per language (lexicon-enfrdees.bin, format BKW2), so
  turning a language off hides its words and "die" ranks as English.
  French elisions and English/French contractions only apply when that language is on.
- App: "-languages de,en" launch argument for UI tests (testMenuAndLanguages).
- UI test testDemo: the feature video (see 2026-11-05 recording).

## 0.3 (build 10), 2026-11-05
Installed on the iPhone 15 and the iPhone 16 Pro Max. Not tested on a phone yet
(the 16 Pro Max was locked).
- New layouts: QWERTZ (umlauts and ß first on long-press of a, o, u, s) and Dvorak
  (',.pyfgcrl / aoeuidhtns / qjkxbmwvz; ";" on long-press of '; the 9-letter
  bottom row uses narrower keys with 1-unit shift and backspace).
- Words you keep are learned: undoing an autocorrection with backspace, or picking
  the "as typed" word in the bar, adds it to a personal list (keyboard's
  UserDefaults "knownWords", up to 2000) that is never autocorrected again.
- Punctuation sticks to the word: . , ? ! ; : typed right after "word " removes
  that space ("word ." → "word.").
- App: "-layout <name>" launch argument for UI tests; quick-currency footer
  describes the key position for every layout.

## 0.3 (build 9), 2026-11-05
Built only, not installed.

## 0.3 (build 8), 2026-11-05
Installed on the iPhone 16 Pro Max (tested there) and the iPhone 15 (not tested).
- Japanese in the ABC keyboard: when the word being typed reads as romaji, the bar
  offers azooKey's conversion in red (watashi → 私, nihongowohanasu → 日本語を話す).
  First slot when the word isn't English or French, last when it is (same → サメ).
  Tap it to swap; no space is added. Space/autocorrect never convert on their own.
  Words with l, q, x, v or a c not followed by h are never treated as romaji.
  Kanji/kana end a word, so romaji typed right after kanji converts on its own
  (今日hatenkigaii → 今日は天気がいい). Setting: Keyboard → "Japanese in ABC" (on).
- The kana dictionary now stays loaded in ABC too (+4 MB, see build 4).
- Version fix: XcodeGen had hard-coded 1.0 (1) into both Info.plists, so every
  earlier build showed "Version 1.0 (build 1)" on the phone. The plists now take
  MARKETING_VERSION / CURRENT_PROJECT_VERSION; this is the first build that shows
  its real number.
- UI test testRomaji: "-prefill <text>" starts the app's field with that text.

## 0.3 (build 7), 2026-11-05
First Japanese-chip build; installed on both phones. "hello" got へっォ (fixed in 8).

## 0.3 (build 6), 2026-11-05
Installed on the iPhone 16 Pro Max (15:1x). The iPhone 15 has build 5.
- Memory leak fixed: iOS kept every closed keyboard's SwiftUI view tree alive,
  adding ~3 MB per opening on the iPhone 15 (~1.3 MB on the 16 Pro Max) until iOS
  killed the keyboard at ~75 MB. The view is now removed on close and rebuilt on
  open, and the keyboard state is one per process.
  iPhone 15, 20 opens with typing: steady at 35-36 MB (was 33 → 74 MB).
- Log lines "LIFE appear/disappear" record memory at each open and close.

## 0.3 (build 5), 2026-11-05
Leak-hunt test build with counters, installed on both phones during testing.
Same fix as build 6 plus diagnostic counters.

## 0.3 (build 4), 2026-11-05
Installed on the iPhone 16 Pro Max, then on the iPhone 15 (14:20).
- Temporary memory probe: launching the app with "-memProbe 1" pre-fills
  "memprobe", and the keyboard then times azooKey conversions with the
  English/French model loaded and logs memory to touch.log (UI test testMemProbe).
  Result on the 16 Pro Max: +5 MB (38 → 43 MB) for 44 conversions, limit 176 MB.
  iPhone 15: +4 MB (35 → 39 MB), limit 76 MB.
- Found: the keyboard grows 4–8 MB every time it opens and never gives it back,
  so on the iPhone 15 iOS kills it at ~75 MB every 5–15 minutes of use (fixed in build 6).

## 0.3 (build 3), 2026-11-05
Installed on the iPhone 15 and the iPhone 16 Pro Max.
- 123 key: tap opens the numpad, hold (0.4 s) opens a symbols layout with digits
  on its top row. Setting "Tap 123 for" (Numpad/Symbols) swaps tap and hold.
- Symbols layout has a second page ("#+=") with brackets, maths and currency signs.

## 0.2 (build 2), 2026-11-05
Installed on the iPhone 15 and the iPhone 16 Pro Max (12:3x).
- The app shows its version and build number.
- Night/Day themes paint the keyboard background too, not just the keys
  (iOS draws its own backdrop from the phone's appearance).
- Letter colours are one scheme at a time: Default, All keys, By row, or By thumb
  (left blue, right red by default). Vowels can be coloured on top of any scheme.

Bench (Colemak, same taps as Gboard on the iPhone 15, build 1 + apostrophe-word fix):
careful 90.6% words right (Gboard 85.5%), fast 66.7% (Gboard 65.3%).

## 0.1 (build 1), 2026-11-05
Installed on the iPhone 15 (12:10) and the iPhone 16 Pro Max (bench run). Built before
version tracking, so its version string still reads 0.1 (1).
- Taps between key rows are no longer lost: iOS drops touches on fully transparent
  pixels, so the keyboard now has a 1% background.
- Suggestion bar updates on every keystroke instead of waiting for an 80 ms pause;
  the clipboard check runs at most every 2 s.
- Apostrophes are part of the word being typed, and their tap position is recorded,
  so slips like "kn'w" get corrected.
- Gboard-style key popup above the pressed letter (key size + 20 pt wide, + 14 pt tall, 36 pt letter).
- Theme: Day, Night or Match iPhone.
- Letter colours: all keys, or per group (vowels, each row, left/right thumb).
- Decoder: multi-slip lexicon search, French elisions (m'envoyer, n'arrive), accent-only fixes (a → à).
- Japanese: kana flick pad and romaji input with azooKey conversion; settings key menu.
