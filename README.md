# TsumuKey

An iOS keyboard for people who type in several languages at once.
*Tsumugi* (紡ぎ) is Japanese for weaving thread: TsumuKey weaves your
languages into one keyboard, with no switching.

Everything runs on the phone. No text leaves the device.

## Features

- **Multilingual prediction and autocorrect.** Pick any two of English,
  French, German and Spanish; suggestions mix them as you type. An on-device
  language model (Gemma 3 270M, vocabulary pruned to these four languages)
  scores every candidate.
- **Tap-aware corrections.** A tap is a point, not a letter: candidates are
  scored on where your finger actually landed plus how likely the word is
  in context, so slips like "wrold" become "world".
- **Learns your words.** Undo an autocorrection with backspace, or pick the
  word as typed, and it is never corrected again ("mcp" stays "mcp").
- **Japanese.** A kana flick pad or romaji input, converted with azooKey. In
  the Latin keyboard, romaji you type (watashi) is offered as 私 in the bar.
- **Layouts.** QWERTY, Colemak, AZERTY, QWERTZ and Dvorak. Keep up to three
  in the ⚙︎ menu; the first one is the default.
- **Symbols where your fingers are.** Every key carries a symbol in its
  corner; long-press puts it right above your finger. Tap 123 for a numpad,
  hold it for symbols with digits on top.
- **Looks.** Day, Night (Gboard-like colours) or Match iPhone; colour letters
  by row, by thumb, or vowels. Custom colours brighten automatically in
  dark mode.
- **Small touches.** Punctuation sticks to the word ("word ." → "word."),
  Gboard-style key popups, a delete key with word-by-word repeat.

## Building

Requirements: macOS with Xcode 16, [XcodeGen](https://github.com/yonaskolb/XcodeGen),
an Apple developer team for signing.

```sh
xcodegen generate                 # creates TsumuKey.xcodeproj from project.yml
open TsumuKey.xcodeproj           # set your team, then build and run on an iPhone
```

Then on the phone: Settings → General → Keyboard → Keyboards → Add New
Keyboard → TsumuKey, and turn on **Allow Full Access** so the keyboard can
read the app's settings.

Install Release builds: the decoder is about five times slower unoptimized.

### Regenerating the model and word list

The repository ships the files the keyboard uses
(`Models/gemma-3-270m-enfrdees64k-Q4_0.gguf`, `Models/lexicon-enfrdees.bin`).
To rebuild them:

- `Tools/prune_vocab.py`: cuts Gemma 3 270M's 262k-token vocabulary down to
  the tokens a corpus uses (64k for the four languages), so it fits an iOS
  keyboard's memory limit.
- `Tools/build_lexicon.py`: builds the word list from
  [wordfreq](https://github.com/rspeer/wordfreq), with one frequency per
  language.
- `Tools/build_llama_ios.sh`: builds llama.cpp as CPU-only static libraries
  into `Vendor/llama-cpu`.

## Project layout

| Folder | What's in it |
|---|---|
| `App/` | The container app: settings, the "Try it here" field |
| `Keyboard/` | The keyboard extension: layouts, touch handling, decoder, model |
| `Shared/` | Settings shared by the app and the keyboard |
| `UITests/` | On-device tests, typing benchmark, screenshot and demo runs |
| `Models/` | Language model and word list |
| `Tools/` | Scripts that build the model, word list and llama.cpp |
| `Vendor/` | llama.cpp static libraries, azooKey |

See `CHANGELOG.md` for what changed in each build.

## Third-party components

| Component | Licence |
|---|---|
| [llama.cpp](https://github.com/ggml-org/llama.cpp) (`Vendor/llama-cpu`) | MIT |
| [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) (`Vendor/AzooKeyKanaKanjiConverter`) | MIT |
| azooKey's dictionary (inside the converter) | Apache 2.0 |
| [Gemma 3 270M](https://ai.google.dev/gemma) (`Models/*.gguf`, pruned) | [Gemma Terms of Use](https://ai.google.dev/gemma/terms) |
| Word frequencies from [wordfreq](https://github.com/rspeer/wordfreq) (`Models/lexicon-*.bin`) | Apache 2.0 (code); data under CC BY-SA 4.0 |

## Licence

TsumuKey's own code is under the MIT licence; see [LICENSE](LICENSE). Bundled third-party code, data and the model keep their own licences (table above).
