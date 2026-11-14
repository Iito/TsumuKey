import SwiftUI

/// About: version, the project on GitHub, and what's new in this version,
/// told for the person typing.
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
            Section {
                ForEach(WhatsNew.changes, id: \.self) { change in
                    Text(LocalizedStringKey(change)).font(.callout)
                }
            } header: {
                Text("What's new in \(WhatsNew.version)")
            }
        }
    }

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
}

/// User-facing changes in this version; replace them when a new version
/// reaches main (CHANGELOG.md is the build-by-build log).
enum WhatsNew {
    static let version = "0.14.0"
    static let changes = [
        "Tapping the emoji in the bar now replaces its word: \"pizza\" becomes 🍕.",
        "**About** (main settings page): what's new in this version and a link to the project on GitHub.",
        "**Swipe typing**: slide across a word's letters without lifting. The bar offers the next guesses; backspace removes the whole word. Turn it off in Typing.",
        "Acronyms and brands come out spelled right (API, PhD, iPhone, YouTube), and are no longer corrected into other words.",
        "Web address fields get a **www.** key and **.com** and your country's endings on the period's long-press; email fields get **@** and common providers.",
    ]
}
