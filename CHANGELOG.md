# TsumuKey changelog (BetterKeys until 0.5)

Versions are set in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
The app shows its version at the bottom of its settings (from build 44; before, under "Set up").

Rules (from 0.6.0):
- Build number: +1 for every build installed on a phone, with an entry here. Never reset.
- Version: bumped only when work reaches main, once per merge, however many features it
  packs (from 0.12.0). Builds on a branch carry the version that merge will get.
- Version, major.minor.patch:
  - major: first public release (1.0.0), later a big change in how the app works;
  - minor: a new feature worth telling a user about (setting, screen, model type);
  - patch: fixes and polish, nothing new to learn.
- Model updates shipped through Hugging Face don't change the app version; the small model
  has its own version (v10 = training round 10).
- Versions before 0.6.0 were set by feel and written with two parts (0.1 to 0.6).

## 0.13.0 (build 101), 2026-11-12
Installed on the iPhone 15.
- Italian and Portuguese: new prediction languages, with a 6-language word list
  (Models/lexicon-eu6.bin, format BKW3) and the small model v11 (training round 11, same
  architecture as v10, trained with Italian and Portuguese added). Offline tap bench:
  Italian/Portuguese 93.9% careful, 84.9% fast (v10: 69.1%, 46.8%); English, French, German
  and Spanish unchanged within noise (95.5% / 87.1%, v10 95.7% / 87.3%).
- With Detect Language on, Prediction Languages takes up to all six.
- The MoE model is still the older 4-language one: it ignores Italian and Portuguese.

## 0.13.0 (build 100), 2026-11-11
Installed on the iPhone 15.
- Fix: with more than two prediction languages and Detect Language on, word suggestions were
  nonsense ("menos", "seiner", "grossen" after "I would like to go to the"). They drew from
  every listed language's words while the model only rates the two it's using. Suggestions
  (next word and completions) now come from those two; corrections still search all of them.

## 0.13.0 (build 99), 2026-11-11
Installed on the iPhone 15.
- With Detect Language on, Prediction Languages takes up to all four: autocorrect knows the
  words of every language listed, and detection picks the two that lead from among them (the
  top two are where it starts). Off, the first two are used, as before.

## 0.13.0 (build 98), 2026-11-11
Installed on the iPhone 15.
- Detect Language follows your recent words across sentences and text fields: each finished
  word adds to a running score per language that fades over ~12 words (only those scores are
  kept, never the words). Build 97 looked at the last 5 words of the field, so one ambiguous
  word could swap in a third language (French words in DE+EN typing; phone bench DE+EN fast
  79.0 vs 82.8 manual). Offline, starting from the wrong pair (EN+FR): DE+EN 97.5/88.2 (same
  as manual), ES+EN 95.6/84.3 (manual 94.8/83.8).
- UI tests: "-textMode" sets the keyboard's starting mode (it remembers the last one).

## 0.13.0 (build 97), 2026-11-11
Installed on the iPhone 15.
- Detect Language (Languages & Model, on by default): autocorrect searches all four word lists
  (EN, FR, DE, ES), and the model favours the two languages the last five words read as
  (Models/langid.tkl, 3.4 MB memory-mapped, a few µs per word). Needs two words to switch;
  until then the last detected languages stay, from field to field. The space bar shows them.
  The chosen prediction languages are only where it starts. Offline replay of the DE+EN and
  ES+EN benches: same as the matching manual setting (careful 97.5/95.2, fast 86.6/84.7).
- Japanese setting "Unconverted text": Plain (default) types the kana as ordinary text and
  edits it in place; Underlined is the iOS-style marked text. Underlined text breaks clearing
  in SwiftUI text fields (Send, Clear leave the old text on screen); plain doesn't.

## 0.13.0 (build 96), 2026-11-11
Installed on the iPhone 15.
- Faster next-word suggestions with the small model: the 2,000 candidate words are scored as
  matrix products (Accelerate) instead of word by word. Same suggestions (identical top 10),
  about 0.2 ms per keystroke on the iPhone 16 Pro Max instead of 3-10 ms.

## 0.13.0 (build 95), 2026-11-11
Installed on the iPhone 15.
- The long-press grid lists only likely words, not a fixed number: candidates are scored in
  full when the grid opens and kept while within 5 nats of the best (about 1/150 as likely),
  up to 30. The bar's own words always stay in it. Scoring runs only on the long press
  (~0.1 s), so typing costs nothing more (build 94 asked the model for 16 next words on every
  space).
- ⌄ in the bar is back to Japanese conversions only.

## 0.13.0 (build 94), 2026-11-11
Installed on the iPhone 15.
- Long press on any word in the bar opens a grid of alternatives in place of the keys: every
  candidate for the word being typed (or the next word), the pressed one first, up to 30. The
  red Japanese word opens its conversions (or the drop-down, per "More conversions"). ⌄ at
  the end of the bar opens it too when there's more than the bar shows; ⌃, a pick or any edit
  closes it.

## 0.13.0 (build 93), 2026-11-11
Installed on the iPhone 15.
- Japanese in the ABC keyboard: ⌄ at the end of the bar opens the red word's conversions
  (up to 30) in a grid in place of the keys, like the iOS kana keyboard; ⌃ closes it. A long
  press on the word does the same. Setting "More conversions": Grid (default) or Drop-down
  (build 92's list under the word, top 10).

## 0.13.0 (build 92), 2026-11-11
Installed on the iPhone 15.
- The long-press list of Japanese conversions drops down from the red word, over the keys,
  instead of replacing the bar. Tap outside it to close it.

## 0.13.0 (build 91), 2026-11-11
Installed on the iPhone 15.
- Japanese in the ABC keyboard: a long press on the red Japanese word in the bar lists its
  top 10 conversions; tap one to type it. Typing on hides the list.

## 0.13.0 (build 90), 2026-11-11
Installed on the iPhone 15.
- Punctuation after a space ("word .") now waits for your next space or return before
  moving against the word ("word. "). A run of marks stays as typed, so "word ..." keeps
  its space.

## 0.13.0 (build 89), 2026-11-10
Installed on the iPhone 16 Pro Max (benchmark).
- Romaji keyboard: when the keys spell a word of your European languages that isn't natural
  Japanese ("meeting", "file", "email"), that word is the first candidate, as typed. Short
  words that read as Japanese stay Japanese ("made" まで, "kite" きて).

## 0.13.0 (build 88), 2026-11-10
Installed on the iPhone 16 Pro Max (benchmark).
- Fix: Japanese text confirmed in the kana and romaji keyboards is now typed like any other
  text. It used to be committed by unmarking the underlined text, which some apps (SwiftUI
  text fields) never noticed: the app's own copy of the text stayed empty.

## 0.13.0 (build 87), 2026-11-10
Installed on the iPhone 16 Pro Max (benchmark).
- Test-only: the app takes "-japaneseInput kana|romaji" at launch (Japanese benchmark).

## 0.12.0 (build 86), 2026-11-10
Installed on the iPhone 16 Pro Max (benchmark).
- Korean autocorrection now knows where each Hangul key sits, so it reads where the finger
  landed (build 85 only knew which key was hit).

## 0.12.0 (build 85), 2026-11-10
Installed on the iPhone 16 Pro Max (benchmark).
- Korean autocorrection on the Dubeolsik keyboard: taps are read like on the ABC keyboard
  (where the finger landed, not just the key), against a 250,000-word Korean list filed
  under each word's keys. Fixes on space or punctuation; backspace right after restores
  what was typed and keeps it from then on. The bar shows the fix in bold, like ABC.
- English (and the other European languages) on the Hangul keyboard: the keys under the
  Latin letters spell words too (ㅗㄷㅣㅣㅐ = hello), and the bar offers the word; tap it to
  swap.

## 0.13.0 (build 84), 2026-11-10
Installed on the iPhone 15.
- Emoji in the suggestion bar: a word that names one ("pizza", "dog", "merci", "hund") offers
  it in the last slot while you type it and just after; a tap adds it after the word
  ("pizza 🍕 "), in the chosen skin tone. On by default; Suggestion Bar → Emoji turns it off.
- The emoji list's keywords come from a newer Unicode CLDR release (more everyday words,
  such as "hello" and "bye" for 👋).

## 0.12.0 (build 83), 2026-11-09
Installed on the iPhone 15.
- The Korean work (builds 75-81) together with 0.11.3's fix for sideloaded installs.

## 0.11.3 (build 82), 2026-11-09
Release build (GitHub release, sideloading). Builds 75-81 are the Korean work on its own branch.
- Fix for sideloaded installs (SideStore, AltStore): the keyboard ignored the app's settings
  (prediction languages, colours…) and used its defaults, even with Full Access on. These
  tools rename the shared App Group per Apple ID and note the new name in the app's
  Info.plist, but not always in the keyboard's; the keyboard now also reads the app's, and
  uses the first App Group it can actually open.
## 0.12.0 (build 81), 2026-11-09
Installed on the iPhone 15.
- Korean in ABC: romanised Korean typed on the Latin keyboard offers the Hangul in the red
  chip, like Japanese romaji (annyeong / annyong → 안녕, gamsahamnida / kamsahamnida →
  감사합니다, saranghae → 사랑해, chingu → 친구, jinjja → 진짜); a tap swaps it and adds a
  space. Every word of the Korean list is romanised letter by letter and as pronounced,
  and spelling is matched loosely (g/k, b/p, r/l, eo/o, doubled letters). On by default
  when Korean is the other alphabet (Layouts → Korean in ABC).
- Romaja on keys (Layouts, off by default): each Hangul key shows its sound in the corner
  (ㄱ g, ㅓ eo, ㅇ ng; on Cheonjiin ㄱㅋ g k), for learning the layout.

## 0.12.0 (build 80), 2026-11-09
Installed on the iPhone 15.
- Korean completions on both Hangul keyboards: the bar offers the three most common words
  that start with what you typed (안녕하 → 안녕하세요, 감사 → 감사합니다, 괜 → 괜찮아), matched
  jamo by jamo so a syllable still being typed counts (안 also finds 아니). A tap replaces
  the word and adds a space. 40,000 words from OpenSubtitles 2018 (FrequencyWords,
  CC BY-SA 4.0), loaded only while a Hangul keyboard is up. No next-word prediction yet.

## 0.12.0 (build 79), 2026-11-09
Installed on the iPhone 15.
- Other Alphabets moved from Languages & Model to the Layouts page, under the Latin layouts:
  Other alphabet, its keyboard (かな / ローマ字, 두벌식 / 천지인) and Japanese in ABC. The
  Layouts row on the main page reads e.g. "QWERTY, Colemak, AZERTY · 한국어"; Languages &
  Model is back to prediction only.

## 0.12.0 (build 78), 2026-11-09
Installed on the iPhone 15.
- Korean keyboard 천지인 (Cheonjiin), the 12-key pad (Languages & Model → Korean keyboard):
  ㅣ ㆍ ㅡ build every vowel (ㅣㆍ → ㅏ, ㆍㅡ → ㅗ, ㅡㆍㆍ → ㅠ, ㅡㆍㆍㅣ → ㅝ), a consonant key
  cycles on repeated taps (ㄱ → ㅋ → ㄲ, ㅅ → ㅎ → ㅆ), → separates two taps of the same key
  (각기), and .,?! cycles the punctuation. Syllables form exactly as on 두벌식.

## 0.12.0 (build 77), 2026-11-09
Installed on the iPhone 15.
- Hangul keyboard follows the letter colours like the Latin one: by row, by thumb, all keys,
  and the vowel colour on the vowel keys (ㅏ ㅓ ㅗ ㅜ ㅡ ㅣ…).

## 0.12.0 (build 76), 2026-11-09
Installed on the iPhone 15.
- "Asian Language" is now called "Other Alphabets" in the app (Other alphabet: None, 日本語,
  한국어).

## 0.12.0 (build 75), 2026-11-09
Installed on the iPhone 15.
- Korean keyboard: 두벌식 (Dubeolsik), the standard Hangul layout. Jamo join into syllables
  as you type (ㅎㅏㄴㄱㅡㄹ → 한글), a final consonant moves on when a vowel follows (값 + ㅣ → 값이), compound vowels (ㅗ + ㅏ → ㅘ); shift or long-press for ㄲ ㄸ ㅃ ㅆ ㅉ ㅒ ㅖ;
  backspace takes off one jamo at a time. No Korean suggestions yet.
- Languages & Model → Other Alphabets: None, 日本語 or 한국어, paired with the prediction
  languages. Its keyboard is in the ⚙︎ menu and a tap on ⚙︎ switches to it (한 on the key for
  Korean, あ for Japanese). Japanese keeps its かな / ローマ字 choice and Japanese in ABC.
  Build 74's "Japanese keyboard: Off" becomes Other alphabet: None.

## 0.11.2 (build 74), 2026-11-09
Installed on the iPhone 15.
- Japanese keyboard can be turned off (Languages & Model → Japanese keyboard → Off): かな and
  ローマ字 leave the ⚙︎ menu, the key loses its あ, and a tap on it switches to the next
  layout in the menu instead. Japanese in ABC is a separate switch and stays as set.

## 0.11.2 (build 73), 2026-11-09
Installed on the iPhone 15.
- Settings: Japanese (keyboard choice, Japanese in ABC) moved into Languages & Model, below
  the prediction languages and model; the main page loses its Japanese row and the Languages
  & Model summary lists 日本語.

## 0.11.2 (build 72), 2026-11-09
Installed on the iPhone 15 and the iPhone 16 Pro Max.
- Next-word suggestions are about 6x faster with the built-in small model (3 ms instead of
  18 ms per suggestion on a Mac), with the same suggestions (PR #1).

## 0.11.1 (build 71), 2026-11-09
Installed on the iPhone 15 and the iPhone 16 Pro Max.
- Debug code removed before open-sourcing: the keystroke and memory log (touch.log), the
  memory probe and the -bench mode. Nothing the keyboard does changes.

## 0.11.1 (build 70), 2026-11-09
Installed on the iPhone 15 and the iPhone 16 Pro Max.
- Swapped letters are fixed: "wrold" → world, "teh" → the, "tiem" → time. A swap's taps
  hit the right keys in the wrong order, so it now costs one slip (3 nats) instead of two
  far misses; before, "hello wrold" became "Hello would".
- Rare words in the word list (web misspellings like "teh", "recieved", zipf below 3) need
  a smaller margin to be replaced (2 nats instead of 4.5).
- French accents on one-letter words: "a" → "à" now happens while typing. The late fix
  skipped one-letter words, so only the bar's slower path could ever add the accent (the
  iOS keyboard comparison showed 35/45 accents restored vs 41/42).
- App icon: the first design (keycap "a") back, with a red 紡 in the corner instead of "à".

## 0.11.0 (build 69), 2026-11-09
Installed on the iPhone 15 and the iPhone 16 Pro Max.
- Look page: a live keyboard preview on top, in the layout in use, the chosen theme and the
  letter colours (rows, thumbs, vowels), drawn with the keyboard's own colours (Palette
  moved to Shared).

## 0.11.0 (build 68), 2026-11-09
Installed on the iPhone 15 and the iPhone 16 Pro Max.
- Layouts page: the key pictures no longer fill a section at the bottom. Holding a layout
  shows its keys in a pop-up (iOS context menu), with Make Default / Remove for layouts in
  use and Add for the others.

## 0.11.0 (build 67), 2026-11-09
Installed on the iPhone 15.
- Main settings page doesn't scroll or bounce when it fits on the screen; it still scrolls
  when it doesn't (small phones, large text, the Full Access card).

## 0.11.0 (build 66), 2026-11-09
Installed on the iPhone 15.
- "Try it here" moved to the Advanced page only. UI tests (-autofocus) open Advanced first.

## 0.11.0 (build 65), 2026-11-09
Installed on the iPhone 15.
- Haptic feedback settings: on/off (also silences the flick and cursor ticks), feel
  (Soft, Light, Medium, Heavy, Rigid; iOS doesn't let a keyboard set the vibration length,
  these styles are the closest) and strength. Changing feel or strength plays a sample.
  Default unchanged: Light at full strength.
- "Delete Key" page renamed Advanced: haptics, key height, hide-keyboard button, and the
  delete key timings.

## 0.11.0 (build 64), 2026-11-09
Installed on the iPhone 15.
- Settings reorganised like iOS Settings: the main page is a short list of rows with
  coloured icons and a one-line summary (Layouts, Languages & Model; Typing, Suggestion
  Bar, Japanese, Keys, Look, Delete Key; Set Up), each opening its own page. "Try it here"
  stays pinned on every page. The Full Access card still shows on top when it's off.
- The Suggestion Bar page shows the date of the saved exchange rates.

## 0.11.0 (build 63), 2026-11-09
Installed on the iPhone 15.
- Currency conversion without "=": an amount with a currency symbol at the end of the text
  ("100€", "€100", "12,50 $", "5000円") fills the bar's three slots with the main
  conversions; a tap replaces the amount with that one.
  € → $ £ ¥; ¥/円 → $ € £; $ → € £ ¥; £ → $ € ¥.

## 0.11.0 (build 62), 2026-11-09
Installed on the iPhone 15.
- Currency conversion (off by default): "100$ in €=", "100 usd to jpy =", "12,50 € en $="
  show the converted amount in the bar; a tap types it. Symbols $ € £ ¥ 円 ₹ ₩ ₺, words
  (dollars, euros, yen, pounds) and the ECB's 3-letter codes; "in", "to", "en", "a", "à",
  "nach", "zu" between. Rates older than 3 days show their date in the bar.
- Rates: the app fetches the European Central Bank's daily reference rates (one XML file,
  nothing sent with it) when the setting is turned on, when the app comes to the front with
  rates over 12 hours old, and from a daily background refresh. The keyboard reads the
  saved copy and stays offline. Turning the setting off deletes the saved rates.

## 0.11.0 (build 61), 2026-11-09
Installed on the iPhone 15.
- The last two iOS keyboard settings, both on by default:
  - Smart punctuation: straight quotes become curly (opening after a space or bracket,
    closing otherwise, so "don't" gets ’) and "--" becomes "—". Off in Japanese and in
    text fields that ask for straight quotes or plain dashes.
  - Show maths results: text ending in a sum and "=" ("12*3=", "(4+5)/2 =", "1,5+2,25=")
    shows the result alone in the bar; a tap types it. + - * / × ÷ ^ % and brackets; a
    decimal comma gives a comma result. Own parser (NSExpression crashes on bad input).

## 0.11.0 (build 60), 2026-11-09
Installed on the iPhone 15.
- New settings, matching the iOS keyboard settings (iOS doesn't share its own with other
  keyboards), all on by default: Auto-capitalisation, Caps lock (double-tap shift),
  "." shortcut (double-tap space), Character preview (the letter above a pressed key).
- Autocorrect stays off in text fields that ask for none (URLs, email addresses, code).
- Memory safety net: when iOS warns and less than 25 MB is left (was 15 MB), the model and
  the kana dictionary are dropped and reloaded fresh, at most once a minute, instead of
  waiting for iOS to kill the keyboard near 76 MB and fall back to the previous keyboard.
  On the 16 Pro Max the growth didn't reproduce: 20 opens stayed at 25 MB, the 70 bench
  sentences at 29-31 MB, switching between five apps at 35 MB.

## 0.10.0 (build 59), 2026-11-09
Installed on the iPhone 15.
- Suggestion bar letter animation a touch slower: 0.25 s instead of 0.2 s.

## 0.10.0 (build 58), 2026-11-09
Installed on the iPhone 15.
- Suggestion bar words change like the iOS keyboard's, letter by letter: letters the old
  and new word share slide to their new place, the others fade out or in (0.2 s). Build 56's
  system morph melted the glyphs; build 57's whole-word crossfade didn't look like iOS.

## 0.10.0 (build 57), 2026-11-09
Installed on the iPhone 15.
- Suggestion bar words crossfade (old word fades out as the new one fades in, 0.2 s)
  instead of morphing letter by letter, which looked like melting.
- Settings change notifications reach the keyboard through a weak box, so they no longer
  hold a closed keyboard alive (part of the memory hunt: the keyboard grows 1-4 MB per
  opening until iOS kills it at about 76 MB; not fixed yet).

## 0.10.0 (build 56), 2026-11-08
Installed on the iPhone 15.
- Suggestion bar words morph like the iOS keyboard's: letters the old and new word share
  slide into place, the others fade, in about 0.2 s (matched to a 60 fps screen recording
  of the iOS bar). Before, words swapped instantly.

## 0.10.0 (build 55), 2026-11-08
Installed on the iPhone 15.
- Layouts page: a "What they look like" section draws every layout's three letter rows as
  small keys, laid out like the keyboard (short rows centred, shift and delete beside the
  bottom row).
- The letter rows moved from the keyboard's Layouts.swift to LetterLayout.rows (Shared), so
  the app can draw them.

## 0.10.0 (build 54), 2026-11-08
Installed on the iPhone 15.
- Bépo layout, in its letter order with É and À on their own keys; È, Ê and Ç are on
  long-press (e, c). Its bottom row has 9 keys, so they are a little narrower. É and À
  count as e and a for corrections (the accent fix from build 53).

## 0.10.0 (build 53), 2026-11-08
Installed on the iPhone 15.
- Three more layouts: Workman, Norman and Maltron.
  - Workman and Norman: ";" becomes an apostrophe, as in Colemak.
  - Maltron's E is a thumb key on hardware; here it sits in the bottom row.
- Accented letters picked by long-press now count as their plain letter
  for corrections; before, an é mid-word counted as a typo against the corrector.

## 0.9.0 (build 52), 2026-11-08
Installed on the iPhone 15.
- Emoji skin tones: a default "Emoji skin tone" setting (Keyboard section) applies to the
  emoji panel and search results; long-press an emoji with tones (305 of them, e.g. 🤷‍♂️)
  for the default yellow and all five tones. emoji.tsv gains a column with each emoji's five
  tone versions (only versions with one tone throughout).
- English "i", "i'm", "i'll", "i've", "i'd" are always capitalized. The rule existed but was
  skipped for learned words; most likely undoing the fix once had taught the keyboard "i"
  (not confirmed: the learned list isn't readable from the Mac).

## 0.8.0 (build 51), 2026-11-08
Installed on the iPhone 15.
- Emoji search: a "Search emoji" pill on the emoji panel brings up the letter keys; letters,
  space and delete edit the query (not the document), and the suggestion bar shows the query
  and the matches. Keywords in English, French, German, Spanish and Japanese (CLDR), so
  "heart", "cœur", "herz", "corazón" all find ❤️. ✕, return or ABC go back to the panel.
- Emoji by category, in Unicode's order: Recently used, Smileys, People, Animals, Food,
  Travel, Activities, Objects, Symbols, Flags. A category bar between ABC and delete jumps to
  each; the current one is highlighted as you scroll.
- Data: Keyboard/emoji.tsv (1,870 emoji, Unicode 15.0 for iOS 17, no skin-tone variants,
  419 KB).

## 0.7.0 (build 50), 2026-11-08
Installed on the iPhone 15.
- Explanations moved behind an ⓘ on each section header (Set up, Prediction Model, Keyboard,
  Look, Delete key) and on the Layouts and Prediction Languages pages; tapping it opens a
  system alert with OK, like the mobile-data question (build 48 used a half-height
  sheet, 49 a popover bubble). Footers keep only what needs attention: download errors, "Gemma isn't
  downloaded yet", "Remove one to add another", the swipe hint, and the version. The Full
  Access card keeps its title, one line and Open Settings.

## 0.6.1 (build 47), 2026-11-07
Installed on the iPhone 15.
- "Correction model" is now "Prediction Model": the same model corrects typos and suggests
  words (while typing and after a space). Prediction Languages moved into that section, above
  the model picker; the footer says what the model does. Stored settings are unchanged.

## 0.6.0 (build 46), 2026-11-07
Installed on the iPhone 15. Same app as build 45; the version is written 0.6.0 under the
rules above.


## 0.6 (build 45), 2026-11-07
Installed on the iPhone 15 (build 44 had a "Replace which?" swap, dropped). New version for what changed since 0.5 (build 21):
- Corrections and suggestions come from the small model (now v10, 2L × 4H, 4.3M params),
  built in, about 10× faster than Gemma and better at corrections. Gemma 3 is an optional
  download.
- Models download from Hugging Face on request, with versions, updates, cancel, and a
  question before using mobile data. The keyboard never goes online.
- One prediction language works as well as two.
- Settings apply to an open keyboard right away; the app shows a Full Access card until the
  keyboard confirms it's on (iOS can't ask for it).
- "Try it here" is pinned above the settings; optional hide-keyboard button; keys reach the
  screen edge like Gboard.
- The version moved to the bottom of the settings, as a footer.
- Layouts and Prediction Languages are one page each, no Edit mode: in use on top (swipe left
  to remove, right to make default / move to top), the rest below (tap to add; greyed out
  when the list is full).
- Removed the keyboard's debug line under "Set up" (build, Full Access, settings, layout); the
  report behind it still drives the Full Access card.

## 0.5 (build 43), 2026-11-07
Installed on the iPhone 15.
- Build 42's mobile-data question never showed. Likely causes, both changed: the alert hung off
  the list Section (now off the "Check for models" row), and it relied on NWPathMonitor's
  isExpensive arriving through a published flag (now the current path is read at the tap:
  not Wi-Fi or Ethernet = ask).
- A download in progress can be cancelled (✕ next to its progress bar); nothing is kept.

## 0.5 (build 42), 2026-11-07
Installed on the iPhone 15 (superseded by 43: the question didn't show).
- Model downloads work on mobile data again, but ask first: on an expensive network (mobile
  data or a hotspot, NWPathMonitor) Download/Update shows "Download on mobile data?" with the
  size. iOS lists Mobile Data for any app that has used the network, so Wi-Fi-only (build 35)
  didn't remove the switch, it just blocked downloads. If Mobile Data is off for the app, the
  error says where to turn it on. Checking the model list (a few hundred bytes) doesn't ask.

## 0.5 (build 41), 2026-11-07
Installed on the iPhone 15.
- Built-in small model updated to v10: better suggestions when only one language is on.
- Build 31's one-language workaround is removed from Ranker.predict: every model the keyboard
  can use is now v10 or newer (a download is only used when newer than the built-in one).

## 0.5 (build 40), 2026-11-07
Installed on the iPhone 15.
- The hide-keyboard button moves to the far right of the suggestion bar (the left is the
  paste button's place), and a "Hide-keyboard button" setting (off by default) shows it in
  every app. It still always shows in the app's own test field.

## 0.5 (build 39), 2026-11-07
Installed on the iPhone 15.
- Hide-keyboard button at the left of the suggestion bar, only while typing in the app's own
  "Try it here" field. iOS doesn't tell a keyboard which app it's in, so the app sets a flag
  in the App Group (plus a Darwin notification) while its field is focused, and clears it when
  the field loses focus or the app leaves the foreground.

## 0.5 (build 38), 2026-11-07
Installed on the iPhone 15.
- Build 37's fix broke scrolling with the field focused (stuck under the keyboard); reverted.
  Instead the "Try it here" field is pinned above the settings list instead of inside it, so
  a keyboard resize has no focused field in the list to scroll back to. Normal keyboard
  avoidance is back. The key height slider still applies on release.

## 0.5 (build 37), 2026-11-07
Installed on the iPhone 15.
- Changing key height or the number row with the keyboard open no longer scrolls the app
  back to the "Try it here" field: the settings list ignores keyboard avoidance (which
  re-scrolled to the focused field on every keyboard resize) and keeps room for the
  keyboard itself. The key height slider applies when released, not on every step.

## 0.5 (build 36), 2026-11-07
Installed on the iPhone 15.
- Settings apply to an open keyboard right away (for example in the app's "Try it here"
  field): saving a setting posts a Darwin notification (com.tsumukey.settingsChanged, no
  data), and the keyboard rereads its settings. Before, it only reread them when it appeared.

## 0.5 (build 35), 2026-11-07
Installed on the iPhone 15.
- Cause of build 33's "settings don't work": Full Access was off. The removed named pasteboard
  had been carrying settings without it. iOS has no API to request Full Access, so:
  - the app shows a "Turn on Full Access" card with Open Settings until the keyboard reports
    it on (the keyboard's report from build 34);
  - the keyboard's empty suggestion bar says "Turn on Full Access in Settings to use your
    TsumuKey settings" when it's off.
- Network: the app no longer fetches the model list on launch, only on "Check for models";
  the list and downloads use Wi-Fi only (allowsCellularAccess off). The Models footer says
  what goes online and that the keyboard never connects.

## 0.5 (build 34), 2026-11-07
Installed on the iPhone 15.
- Settings reported not reaching the keyboard after build 33. The keyboard now writes what it
  saw (build, time, Full Access, settings found, layout) into the App Group each time it
  opens, and the app shows it under "Set up".
- Letter keys run to the screen edge: the row's extra 3 pt margin is gone, so a key face
  starts 3 pt from the edge (Gboard: ~3 pt; it was 6 pt). Gaps between keys unchanged (6 pt).

## 0.5 (build 33), 2026-11-07
Installed on the iPhone 15.
- Settings reach the keyboard through the App Group only. The named pasteboard
  (com.tsumukey.settings) was a workaround from before the app had an App Group; it is no
  longer written or read. Full Access is still needed for the keyboard to read settings.

## 0.5 (build 32), 2026-11-07
Installed on the iPhone 15.
- Model updates are visible: the small model's name carries its version ("Small v9 (...)",
  the training round), in the picker and in the Hugging Face list. A newer version than the
  one in use shows "Update from vN" and an Update button instead of a plain Download, and
  updating deletes the older downloaded file.

## 0.5 (build 31), 2026-11-07
Installed on the iPhone 15.
- Fix: with one prediction language, suggestions were nearly useless: the one-language word
  list holds ~800 words the model had never seen as candidates, and they got wild scores
  ("thomas", "budget"). Ranker.predict now runs a lone language as a pair (English+French,
  French+English, German+French, Spanish+English) and keeps only that language's words, so
  suggestions are as good as with two languages. Two-language results unchanged.

## 0.5 (build 30), 2026-11-07
Installed on the iPhone 15.
- Built-in small model updated to round 9: slightly better corrections and suggestions,
  same size and speed.

## 0.5 (build 29), 2026-11-07
Installed on the iPhone 15.
- Built-in small model updated to round 8: better next-word suggestions, corrections
  unchanged.
- A downloaded ranker is used only when its round is newer than the built-in one.
- azooKey comes from a patched fork as a Swift package; llama.cpp is a submodule built by
  Tools/build_llama_ios.sh (b12063, same as before).

## 0.5 (build 28), 2026-11-07
Installed on the iPhone 15.
- Models are named by architecture: "Small (Transformer 2L × 4H, 4.3M params)", read from
  the .rank file's header, and "Gemma 3 (Transformer 18L × 4H, 141M params)". Same names in
  the Hugging Face models.json.

## 0.5 (build 27), 2026-11-07
Installed on the iPhone 15. First build with the real TsumuKey IDs (com.tsumukey,
com.tsumukey.keyboard) and the App Group group.com.tsumukey, so it installs as a new
app next to the old BetterKeys-ID one.
- Models download on request from the public Hugging Face repo iito-sama/tsumukey-models
  (models.json lists file, size, SHA-256, minimum build). The app downloads into the App
  Group folder and checks the checksum; the keyboard loads from there (Shared/ModelStore.swift,
  App/ModelsSection.swift). A downloaded ranker-rN.rank replaces the built-in one.
- Gemma is no longer bundled: app 171 MB -> 74 MB. Choosing Gemma before it's downloaded
  keeps the small model.
- Settings: "Correction model" section with the picker (Small, round 7 / Gemma), the model
  list with Download / Delete, and progress.

## 0.5 (build 26), 2026-11-07
Installed on the iPhone 15.
- "Correction model" picker in the app's settings, naming the bundled model and its
  training round: Small, round 7 (4.5 MB) or Gemma 270M (100 MB). MoE stays bench-only.
- Built-in small model updated to round 7 (Models/ranker-dense.rank): better corrections.

## 0.5 (build 25), 2026-11-07
Installed on the iPhone 15.
- Correction model now defaults to the small dense ranker (round 6, Models/ranker-dense.rank),
  which also gives next-word suggestions (Ranker.predict: ranks the 2000 most frequent
  words of the enabled languages). Gemma stays bundled as an option.

## 0.5 (build 24), 2026-11-07
Bench build, installed on the iPhone 16 Pro Max.
- Round-5 rankers bundled (Models/ranker-dense.rank, ranker-moe.rank).
- On-phone bench, iPhone 16 Pro Max, Colemak, 606 words (careful / fast): r5 dense
  90.8% / 68.6%, r5 MoE 90.6% / 69.1%, Gemma 90.4% / 66.7% (Gemma re-run on this build).
  Default stays Gemma.

## 0.5 (build 23), 2026-11-07
Installed on the iPhone 15, then on the iPhone 16 Pro Max by the lock-phone test run.
- New app icon: a keycap whose "t" runs off the key as thread (Tools/make_icon.swift).

## 0.5 (build 22), 2026-11-07
Bench build, installed on the iPhone 16 Pro Max (on-phone typing bench) and the iPhone 15.
- Correction model setting (Gemma 270M, or a ~4.6 MB candidate ranker with a dense or
  mixture-of-experts head, Tools/rank). "-model gemma|dense|moe" launch argument; the
  UI bench passes it with BENCH_MODEL. Default stays Gemma.
- On-phone bench, iPhone 16 Pro Max, Colemak, 606 words (careful / fast words right):
  Gemma 90.4% / 66.8%, dense ranker 90.6% / 67.7%, MoE ranker 90.3% / 67.5%.
- UI test testLockPhone locks the phone after a bench run.

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
  Gemma 3 270M covering all four, and the word list stores
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
