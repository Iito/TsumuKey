import SwiftUI

/// About: version, the project on GitHub, and what changed in each version,
/// told for the person typing (CHANGELOG.md is the build-by-build log).
struct AboutPage: View {
    static let github = URL(string: "https://github.com/Iito/TsumuKey")!

    var body: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Text("TsumuKey").font(.title2.bold())
                    Text("Version \(Self.version) (build \(Self.build))")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("An open-source keyboard for people who type in several languages at once.")
                        .font(.callout).multilineTextAlignment(.center).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            Section {
                Link(destination: Self.github) {
                    Label("TsumuKey on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.github.appendingPathComponent("releases")) {
                    Label("Releases", systemImage: "shippingbox")
                }
                Link(destination: Self.github.appendingPathComponent("issues")) {
                    Label("Report a problem", systemImage: "exclamationmark.bubble")
                }
            }
            ForEach(WhatsNew.versions, id: \.version) { v in
                Section {
                    ForEach(v.changes, id: \.self) { change in
                        Text(LocalizedStringKey(change)).font(.callout)
                    }
                } header: {
                    Text(v.version == WhatsNew.versions.first?.version ? "What's new in \(v.version)" : v.version)
                }
            }
        }
    }

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
}

/// User-facing changes, newest first. Add a version here when it reaches main.
enum WhatsNew {
    struct Version { let version: String; let changes: [String] }

    static let versions: [Version] = [
        Version(version: "0.14.0", changes: [
            "Tapping the emoji in the bar now replaces its word: \"pizza\" becomes 🍕.",
            "**About** (main settings page): what's new in each version and a link to the project on GitHub.",
        ]),
        Version(version: "0.13.0", changes: [
            "**Italian and Portuguese**: suggestions and autocorrect now in six languages.",
            "**Detect Language** (on by default): list all the languages you write and the keyboard follows the two you're typing. The space bar shows which two.",
            "**Long press a word** in the suggestion bar for a grid of other words that fit.",
            "**Emoji in the bar**: a word like \"pizza\" or \"merci\" offers its emoji; a tap adds it after the word. Suggestion Bar → Emoji turns it off.",
            "Japanese: ⌄ at the end of the bar shows more conversions in a grid.",
            "Japanese romaji keyboard: English words like \"meeting\" or \"email\" come first, as typed.",
            "Japanese setting \"Unconverted text\": plain (default) or underlined like the iOS keyboard.",
            "A period or comma typed after a space moves against the word when you type your next space.",
            "Faster next-word suggestions.",
            "Fix: \"of\" no longer turns into \"Ö\".",
            "Fix: Japanese typed in some apps could disappear.",
        ]),
        Version(version: "0.12.0", changes: [
            "**Korean**: 두벌식 (Dubeolsik) and 천지인 (Cheonjiin) keyboards, with word completions and autocorrect that reads where your finger landed.",
            "Romanised Korean on the Latin keyboard (annyeong, gamsahamnida) offers the Hangul; tap it to swap.",
            "On the Hangul keyboard, English words typed on the same keys are offered too (ㅗㄷㅣㅣㅐ → hello).",
            "Romaja on keys (Layouts): each Hangul key shows its sound, to learn the layout.",
            "Other Alphabets (Layouts): None, 日本語 or 한국어.",
        ]),
        Version(version: "0.11.3", changes: [
            "Fix: installed with AltStore or SideStore, the keyboard ignored the app's settings.",
        ]),
        Version(version: "0.11.2", changes: [
            "The Japanese keyboard can be turned off.",
            "Faster next-word suggestions with the built-in model.",
        ]),
        Version(version: "0.11.1", changes: [
            "Swapped letters are fixed: \"wrold\" → world, \"teh\" → the.",
            "French: \"a\" becomes \"à\" while you type when that's the word.",
            "New app icon.",
        ]),
        Version(version: "0.11.0", changes: [
            "Settings laid out like iOS Settings.",
            "The iOS keyboard settings: auto-capitalisation, caps lock, \".\" shortcut, character preview and smart punctuation.",
            "Maths in the bar: \"12*3=\" shows 36.",
            "Currency conversion (off by default): \"100€\" shows it in dollars, pounds and yen.",
            "Haptics: choose the feel and strength.",
            "Look: a live preview of the keyboard.",
        ]),
        Version(version: "0.10.0", changes: [
            "Bépo, Workman, Norman and Maltron layouts.",
            "Words in the suggestion bar change smoothly, like the iOS keyboard's.",
        ]),
    ]
}
