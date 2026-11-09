import SwiftUI

@main
struct TsumuKeyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .backgroundTask(.appRefresh(RatesFetcher.taskID)) {
                await RatesFetcher.refreshIfNeeded()
            }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var timing = DeleteTiming.load()
    @State private var settings = KeyboardSettings.load()
    @State private var report = KeyboardReport.load()
    @FocusState private var fieldFocused: Bool
    @State private var advancedOpen = false

    var body: some View {
        NavigationStack {
            Form {

                if report?.fullAccess != true {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(report == nil ? "Turn on Full Access" : "Full Access is off")
                                .font(.headline)
                            Text(report == nil
                                 ? "Add the TsumuKey keyboard, turn on Allow Full Access, then open the keyboard once (in any app, or Advanced → Try it here). Until then it uses default settings."
                                 : "The keyboard can't read your settings or downloaded models. Settings → General → Keyboard → Keyboards → TsumuKey → Allow Full Access.")
                                .font(.callout)
                        }
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }

                Section {
                    row("Layouts", "keyboard", .blue, settings.menuLayouts.map(\.name).joined(separator: ", ")
                        + (settings.asianLanguage == .none ? "" : " · " + settings.asianLanguage.name)) { layoutsPage }
                    row("Languages & Model", "globe", .indigo, settings.predictionLanguages.map(\.name).joined(separator: ", ")) { modelPage }
                }
                Section {
                    row("Typing", "character.cursor.ibeam", .gray, typingSummary) { typingPage }
                    row("Suggestion Bar", "sparkles", .orange, barSummary) { barPage }
                    row("Keys", "square.grid.3x3", .teal, settings.numberRow ? "Number row" : "No number row") { keysPage }
                    row("Look", "paintpalette", .pink, settings.theme.name) { lookPage }
                    row("Advanced", "gearshape.2", .gray, settings.haptics ? "Haptics \(settings.hapticStyle.name.lowercased())" : "Haptics off") { advancedPageFramed }
                }
                Section {
                    row("Set Up", "checkmark.shield", .green,
                        report?.fullAccess == true ? "Full Access on" : "Full Access off") { setUpPage }
                }

                // Version at the very bottom; matches the entries in CHANGELOG.md.
                Section {} footer: {
                    let info = Bundle.main.infoDictionary
                    Text("TsumuKey \(info?["CFBundleShortVersionString"] as? String ?? "?") (build \(info?["CFBundleVersion"] as? String ?? "?"))")
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("TsumuKey")
            // Fits on one screen: no scrolling or bounce. It still scrolls when it
            // doesn't fit (small phones, large text, the Full Access card).
            .scrollBounceBehavior(.basedOnSize)
            // The keyboard reports each time it opens (drives the Full Access card).
            .task {
                while !Task.isCancelled {
                    report = KeyboardReport.load()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            // UI tests (-autofocus) start on Advanced, where the test field is.
            .navigationDestination(isPresented: $advancedOpen) { advancedPageFramed }
            .onChange(of: timing) { _, new in new.save() }
            .onChange(of: settings) { old, new in
                new.save()
                guard old.currencyConversion != new.currencyConversion else { return }
                if new.currencyConversion {
                    Task { await RatesFetcher.fetch(); RatesFetcher.schedule() }
                } else {
                    CurrencyRates.clear()
                    RatesFetcher.schedule()
                }
            }
            // The keyboard can change the layout too (long-press its settings key), so
            // re-read whenever the app comes back to the front.
            .onChange(of: fieldFocused) { _, focused in SharedSettings.setInAppField(focused) }
            .onChange(of: scenePhase) { _, phase in
                // Leaving the app: the keyboard must not offer "hide" elsewhere.
                SharedSettings.setInAppField(phase == .active && fieldFocused)
                guard phase == .active else { return }
                let latest = KeyboardSettings.load()
                if latest != settings { settings = latest }
                Task { await RatesFetcher.refreshIfNeeded() }
            }
            // Lets simulator runs and UI tests open the keyboard without a tap.
            .task {
                // UI tests pass "-chainWindow <seconds>": the test runner pauses
                // between gestures, longer than a human would between taps.
                let chain = UserDefaults.standard.double(forKey: "chainWindow")
                if chain > 0 { timing.multiTapWindow = chain; timing.save() }
                let rowHeight = UserDefaults.standard.double(forKey: "rowHeight")
                if rowHeight > 0 { settings.rowHeight = rowHeight; settings.save() }
                // UI tests: "-prefill <text>" starts the field with that text,
                // as if just typed (the keyboard reads the word before the cursor).
                if let prefill = UserDefaults.standard.string(forKey: "prefill") { text = prefill }
                // UI tests: "-layout dvorak" switches the letter layout.
                if let name = UserDefaults.standard.string(forKey: "layout"),
                   let layout = LetterLayout(rawValue: name) { settings.layout = layout; settings.save() }
                // UI tests: "-numberRow 0|1" and "-symbolHints 0|1" (README screenshots).
                let args = UserDefaults.standard
                if args.object(forKey: "numberRow") != nil { settings.numberRow = args.bool(forKey: "numberRow"); settings.save() }
                if args.object(forKey: "symbolHints") != nil { settings.showSymbolHints = args.bool(forKey: "symbolHints"); settings.save() }
                // UI tests: "-languages de,en" picks the prediction languages.
                if let codes = UserDefaults.standard.string(forKey: "languages") {
                    let picked = codes.split(separator: ",").compactMap { PredictionLanguage(rawValue: String($0)) }
                    if !picked.isEmpty { settings.predictionLanguages = picked; settings.save() }
                }
                // UI tests: "-model gemma|dense|moe" picks the correction model.
                if let name = UserDefaults.standard.string(forKey: "model"),
                   let m = CorrectionModel(rawValue: name) { settings.correctionModel = m; settings.save() }
                guard ProcessInfo.processInfo.arguments.contains("-autofocus") else { return }
                advancedOpen = true
                // Focusing during the first layout pass is ignored; wait a moment.
                try? await Task.sleep(for: .milliseconds(500))
                fieldFocused = true
            }
        }
    }
}

/// One page for an ordered pick list: what's in use on top (first = default),
/// everything else below. Tap to add (greyed out when full). Swipe left to
/// remove, right to move to the top. At least 1 item, at most `limit`.
struct OrderedListPage<Item: Identifiable & Hashable>: View {
    let title: String
    @Binding var items: [Item]
    let all: [Item]
    let name: KeyPath<Item, String>
    let limit: Int
    /// Shown under the first row ("Default"), or nil.
    let firstNote: String?
    let topAction: String
    let info: [String]
    /// Optional picture of an item (a layout's keys), shown when its row is held.
    var preview: ((Item) -> AnyView)? = nil
    /// Shown after the list (the Layouts page's other alphabet).
    var extraSection: AnyView? = nil

    private var rest: [Item] { all.filter { !items.contains($0) } }

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item[keyPath: name])
                        if let firstNote, item == items.first {
                            Text(firstNote).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if items.count > 1 {
                            Button("Remove", role: .destructive) { items.removeAll { $0 == item } }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if item != items.first {
                            Button(topAction) { moveToTop(item) }
                                .tint(.blue)
                        }
                    }
                    .modifier(HoldPreview(preview: preview.map { p in { previewCard(item, p) } }) {
                        if item != items.first {
                            Button(topAction, systemImage: "arrow.up.to.line") { moveToTop(item) }
                        }
                        if items.count > 1 {
                            Button("Remove", systemImage: "minus.circle", role: .destructive) { items.removeAll { $0 == item } }
                        }
                    })
                }
            } header: {
                Text("In use")
            } footer: {
                Text("Swipe left to remove, right to \(topAction.lowercased()).\(preview == nil ? "" : " Hold one to see it.")")
            }

            if !rest.isEmpty {
                Section {
                    ForEach(rest) { item in
                        Button {
                            items.append(item)
                        } label: {
                            HStack {
                                Text(item[keyPath: name])
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                        .disabled(items.count >= limit)
                        .modifier(HoldPreview(preview: preview.map { p in { previewCard(item, p) } }) {
                            Button("Add", systemImage: "plus.circle") { items.append(item) }
                                .disabled(items.count >= limit)
                        })
                    }
                } header: {
                    Text("Add")
                } footer: {
                    if items.count >= limit { Text("Up to \(limit). Remove one to add another.") }
                }
            }

            if let extraSection { extraSection }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { InfoButton(title: title, info: info) }
    }

    private func moveToTop(_ item: Item) {
        items.removeAll { $0 == item }
        items.insert(item, at: 0)
    }

    /// What a held row shows: its name over the picture, at a fixed width
    /// (the context menu preview has no width of its own).
    private func previewCard(_ item: Item, _ preview: (Item) -> AnyView) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 10) {
            Text(item[keyPath: name]).font(.headline)
            preview(item)
        }
        .padding(16)
        .frame(width: 340))
    }
}

/// Long-press menu with a preview, only when there's a preview to show.
private struct HoldPreview<Actions: View>: ViewModifier {
    let preview: (() -> AnyView)?
    @ViewBuilder let actions: () -> Actions

    func body(content: Content) -> some View {
        if let preview {
            content.contextMenu { actions() } preview: { preview() }
        } else {
            content
        }
    }
}

/// Section header with an ⓘ that opens the section's explanation, so the
/// settings list itself stays short.
struct InfoHeader: View {
    let title: String
    let info: [String]
    init(_ title: String, info: [String]) { self.title = title; self.info = info }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            InfoButton(title: title, info: info).textCase(nil)
        }
    }
}

struct InfoButton: View {
    let title: String
    let info: [String]
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "info.circle").imageScale(.large)
        }
        .accessibilityLabel("About \(title)")
        // A system alert, like the mobile-data question. Attached to the button
        // itself: an alert on a whole list Section is never shown.
        .alert(title, isPresented: $shown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(info.joined(separator: "\n\n"))
        }
    }
}

/// One label colour.
private struct ColorRow: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        ColorPicker(title, selection: Binding(
            get: { Color(UIColor(hex: hex) ?? .label) },
            set: { hex = UIColor($0).hex }), supportsOpacity: false)
    }
}

extension ContentView {
    private var tryItHere: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Try it here").font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                // Lets the typing benchmark (UI test) reset the field between sentences.
                Button("Clear") { text = "" }
                    .font(.callout)
                    .accessibilityIdentifier("clearField")
            }
            TextField("Type something…", text: $text, axis: .vertical)
                .lineLimit(2...4)
                .focused($fieldFocused)
                .accessibilityIdentifier("testField")
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: Settings pages
// Each group of settings is its own page, like iOS Settings, so the main page
// stays a short list. The "Try it here" field is on Advanced only.
extension ContentView {
    /// A main-page row: coloured icon, title, a short summary, and its page.
    private func row<Page: View>(_ title: String, _ symbol: String, _ color: Color, _ summary: String,
                                 @ViewBuilder page: @escaping () -> Page) -> some View {
        NavigationLink {
            page()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            Label {
                LabeledContent(title, value: summary)
            } icon: {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var typingSummary: String {
        let toggles = [settings.autocorrect, settings.autoCapitalize, settings.capsLock,
                       settings.periodShortcut, settings.smartPunctuation, settings.characterPreview]
        let off = toggles.filter { !$0 }.count
        return off == 0 ? "All on" : "\(off) off"
    }

    private var barSummary: String {
        let on = [settings.mathResults ? "Maths" : nil, settings.currencyConversion ? "Currency" : nil].compactMap { $0 }
        return on.isEmpty ? "Words only" : on.joined(separator: ", ")
    }

    private var layoutsPage: some View {
        OrderedListPage(title: "Layouts",
                        items: $settings.menuLayouts, all: LetterLayout.allCases,
                        name: \.name, limit: KeyboardSettings.maxMenuLayouts, firstNote: "Default",
                        topAction: "Make Default",
                        info: ["Up to \(KeyboardSettings.maxMenuLayouts) layouts. The first one is the default: the keyboard opens on it.",
                               "Hold the ⚙︎ key on the keyboard to switch between them. The Japanese keyboard is always in that menu too.",
                               "Hold a layout here to see its keys."],
                        preview: { AnyView(LayoutPreview(layout: $0)) },
                        extraSection: AnyView(otherAlphabetSection))
            .onChange(of: settings.menuLayouts) { _, list in
                // The keyboard opens on the top layout.
                if let first = list.first, first != settings.layout { settings.layout = first }
            }
    }

    private var modelPage: some View {
        Form { ModelsSection(settings: $settings) }
    }

    /// Layouts page, second part: the one keyboard for another alphabet
    /// (kana, Hangul) next to the Latin layouts.
    private var otherAlphabetSection: some View {
        Section {
            Picker("Other alphabet", selection: $settings.asianLanguage) {
                ForEach(AsianLanguage.allCases) { Text($0.name).tag($0) }
            }
            switch settings.asianLanguage {
            case .japanese:
                Picker("Japanese keyboard", selection: $settings.japaneseInput) {
                    ForEach(JapaneseInput.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Japanese in ABC", isOn: $settings.japaneseInLatin)
            case .korean:
                Picker("Korean keyboard", selection: $settings.koreanInput) {
                    ForEach(KoreanInput.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Korean in ABC", isOn: $settings.koreanInLatin)
                Toggle("Romaja on keys", isOn: $settings.hangulRomaja)
            case .none:
                EmptyView()
            }
        } header: {
            InfoHeader("Other Alphabets", info: [
                "One language with its own alphabet, next to your prediction languages. Its keyboard is in the ⚙︎ menu, and a tap on ⚙︎ switches to it.",
                "Japanese keyboard: かな is the flick pad; ローマ字 types romaji on the letter keys.",
                "Japanese in ABC: typing romaji (watashi, arigatou) offers 私, ありがとう in the bar; tap it to swap.",
                "Korean: 두벌식 (Dubeolsik), the standard Hangul layout; shift or long-press for ㄲ ㄸ ㅃ ㅆ ㅉ ㅒ ㅖ. 천지인 (Cheonjiin), the 12-key pad: ㅣ ㆍ ㅡ build the vowels, tap a consonant again for the next one (ㄱ → ㅋ → ㄲ), and → to type the same consonant twice.",
                "Korean in ABC: typing romanised Korean (annyeong, gamsahamnida) offers 안녕, 감사합니다 in the bar; tap it to swap.",
                "Romaja on keys: each Hangul key shows its sound (ㄱ g, ㅓ eo), for learning the layout.",
                "None: the ⚙︎ key switches between your layouts instead.",
            ])
        }
    }

    private var typingPage: some View {
        Form {
            Section {
                Toggle("Auto-correct", isOn: $settings.autocorrect)
                Toggle("Auto-capitalisation", isOn: $settings.autoCapitalize)
                Toggle("Caps lock", isOn: $settings.capsLock)
                Toggle("\u{201C}.\u{201D} shortcut", isOn: $settings.periodShortcut)
                Toggle("Smart punctuation", isOn: $settings.smartPunctuation)
                Toggle("Character preview", isOn: $settings.characterPreview)
            } header: {
                InfoHeader("Typing", info: [
                    "Like the iOS keyboard settings, which iOS doesn't share with other keyboards.",
                    "Auto-correct stays off in fields that ask for none (web addresses, email, code).",
                    "Caps lock: double-tap shift.",
                    "\u{201C}.\u{201D} shortcut: double-tap space after a word types a full stop and a space.",
                    "Smart punctuation: curly quotes and apostrophes (don\u{2019}t), and -- becomes \u{2014}.",
                    "Character preview: the letter shows above the key you press.",
                ])
            }
        }
    }

    private var barPage: some View {
        Form {
            Section {
                Toggle("Maths results", isOn: $settings.mathResults)
                Toggle("Currency conversion", isOn: $settings.currencyConversion)
            } header: {
                InfoHeader("In the Suggestion Bar", info: [
                    "Maths results: type a sum and = (12*3=, (4+5)/2 =) and the result shows in the bar; tap it to type it.",
                    "Currency conversion: an amount with $ \u{20AC} \u{00A3} \u{00A5} (100\u{20AC}, $20) shows it in the three main other currencies; tap one to swap. \u{201C}100 usd in chf=\u{201D} converts to any currency the European Central Bank lists.",
                    "Rates: the app fetches the European Central Bank's daily rates, about once a day, only while this is on. The keyboard stays offline. Turning it off deletes the rates.",
                ])
            } footer: {
                if settings.currencyConversion, let rates = CurrencyRates.load() {
                    Text("Rates from \(rates.date.formatted(date: .abbreviated, time: .omitted)).")
                } else if settings.currencyConversion {
                    Text("No rates yet: they download when you're online.")
                }
            }
        }
    }

    private var keysPage: some View {
        Form {
            Section {
                Toggle("Number row", isOn: $settings.numberRow)
                Picker("Tap 123 for", selection: $settings.numberKeyTap) {
                    ForEach(NumberKeyTap.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Show symbols on keys", isOn: $settings.showSymbolHints)
                Picker("Quick currency", selection: $settings.currency) {
                    ForEach(KeyboardSettings.currencies, id: \.self) { Text($0).tag($0) }
                }
                Picker("Emoji skin tone", selection: $settings.emojiSkinTone) {
                    ForEach(0..<6) { t in Text(["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"][t]).tag(t) }
                }
            } header: {
                InfoHeader("Keys", info: [
                    "Holding 123 opens the other number layout.",
                    "Long-press still shows symbols when they're hidden on the keys.",
                    "Quick currency sits on the third key of the middle row (D on QWERTY, S on Colemak, E on Dvorak); long-press it for the others.",
                    "Emoji skin tone applies to the emoji panel and search; long-press an emoji there for the other tones.",
                ])
            }
        }
    }

    private var lookPage: some View {
        Form {
            Section {
                LookPreview(settings: settings)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(KeyboardTheme.allCases) { Text($0.name).tag($0) }
                }
                Picker("Letter colours", selection: $settings.letterColors.scheme) {
                    ForEach(LetterScheme.allCases) { Text($0.name).tag($0) }
                }
                switch settings.letterColors.scheme {
                case .none:
                    EmptyView()
                case .all:
                    ColorRow(title: "All keys", hex: $settings.letterColors.all)
                case .rows:
                    ColorRow(title: "Top row", hex: $settings.letterColors.topRow)
                    ColorRow(title: "Middle row", hex: $settings.letterColors.middleRow)
                    ColorRow(title: "Bottom row", hex: $settings.letterColors.bottomRow)
                case .thumbs:
                    ColorRow(title: "Left thumb", hex: $settings.letterColors.leftThumb)
                    ColorRow(title: "Right thumb", hex: $settings.letterColors.rightThumb)
                }
                HStack {
                    Toggle("Vowels", isOn: $settings.letterColors.vowelsOn)
                    if settings.letterColors.vowelsOn {
                        ColorRow(title: "Vowels", hex: $settings.letterColors.vowels).labelsHidden()
                    }
                }
            } header: {
                InfoHeader("Look", info: [
                    "Pick one letter colour scheme: all keys, by row, or by thumb.",
                    "Vowels can be coloured on top of any scheme.",
                ])
            }
        }
    }

    /// The test field is pinned above the list, not inside it: iOS scrolls a
    /// list back to its focused field whenever the keyboard changes height
    /// (key height, number row), which jumped away from the setting being changed.
    private var advancedPageFramed: some View {
        advancedPage
            .navigationTitle("Advanced")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { tryItHere }
    }

    private var advancedPage: some View {
        Form {
            Section {
                Toggle("Haptic feedback", isOn: $settings.haptics)
                if settings.haptics {
                    Picker("Feel", selection: $settings.hapticStyle) {
                        ForEach(HapticStyle.allCases) { Text($0.name).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Strength")
                        Slider(value: $settings.hapticStrength, in: 0.2...1) { editing in
                            if !editing { playHaptic() }
                        }
                    }
                }
            } header: {
                InfoHeader("Haptics", info: [
                    "A small vibration on every key tap, and a tick for flick and cursor moves.",
                    "Feel: Soft is a long gentle thud, Rigid a short sharp click; iOS doesn't let keyboards set the length directly.",
                    "Haptics need Full Access, and follow iPhone's System Haptics setting (Settings → Sounds & Haptics).",
                ])
            }
            .onChange(of: settings.hapticStyle) { _, _ in playHaptic() }

            Section {
                RowHeightSlider(rowHeight: $settings.rowHeight)
                Toggle("Hide-keyboard button", isOn: $settings.hideKeyboardButton)
            } header: {
                InfoHeader("Keyboard", info: [
                    "Key height: the height of one row of keys.",
                    "Hide-keyboard button: a ⌄ at the right end of the suggestion bar, in every app. It always shows in this app's test field.",
                ])
            }

            Section {
                TimingSlider(title: "Hold before repeating", value: $timing.holdDelay, range: 0.2...0.8)
                TimingSlider(title: "Character repeat speed", value: $timing.charRepeat, range: 0.02...0.15)
                TimingSlider(title: "Word repeat speed", value: $timing.wordRepeat, range: 0.15...0.7)
                TimingSlider(title: "Time to chain taps", value: $timing.multiTapWindow, range: 0.15...0.6)
                Button("Reset to defaults") { timing = DeleteTiming() }
            } header: {
                InfoHeader("Delete Key", info: [
                    "Tap: one character.",
                    "Hold: characters, repeating.",
                    "Tap then hold: one word.",
                    "Double tap then hold: word after word.",
                    "Lower numbers are faster.",
                ])
            }
        }
    }

    /// Lets you feel the chosen style and strength in the app.
    private func playHaptic() {
        let g = UIImpactFeedbackGenerator(style: settings.hapticStyle.impact)
        g.impactOccurred(intensity: settings.hapticStrength)
    }

    private var setUpPage: some View {
        Form {
            Section {
                Text("1. Settings → General → Keyboard → Keyboards → Add New Keyboard → TsumuKey")
                Text("2. Tap TsumuKey in that list and turn on **Allow Full Access**.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } header: {
                InfoHeader("Set up", info: [
                    "Full Access lets the keyboard read the settings and models this app keeps for it. Without it, the keyboard uses default settings and the built-in model.",
                    "iOS shows a warning for every keyboard with Full Access. TsumuKey's keyboard never goes online, and nothing you type leaves your phone.",
                    "iOS doesn't let apps ask for Full Access; it can only be turned on in Settings.",
                ])
            }
            .font(.callout)
        }
    }
}

/// Key height applies when the slider is let go, not on every step: each
/// change resizes an open keyboard.
private struct RowHeightSlider: View {
    @Binding var rowHeight: Double
    @State private var draft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Key height")
                Spacer()
                Text("\(Int(draft ?? rowHeight)) pt").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { draft ?? rowHeight }, set: { draft = $0 }),
                   in: KeyboardSettings.rowHeightRange, step: 1) { editing in
                if !editing, let d = draft { rowHeight = d; draft = nil }
            }
        }
    }
}

private struct TimingSlider: View {
    let title: String
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value * 1000).rounded())) ms")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: 0.01)
        }
    }
}

/// A layout's three letter rows drawn as small keys, laid out like the
/// keyboard: 10 units wide, short rows centred, shift and delete beside the
/// bottom row.
struct LayoutPreview: View {
    let layout: LetterLayout

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 10
            VStack(spacing: 4) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { index, row in
                    let letters = row.map { String($0).uppercased() }
                    if index < 2 {
                        HStack(spacing: 0) {
                            ForEach(Array(letters.enumerated()), id: \.offset) { _, l in key(l, width: unit) }
                        }
                    } else {
                        // Same rule as the keyboard: 1.5-unit shift and delete, or
                        // 1 unit when the row has more than 7 letters.
                        let edge: CGFloat = letters.count > 7 ? 1 : 1.5
                        let width = min(1, (10 - 2 * edge) / CGFloat(letters.count)) * unit
                        HStack(spacing: 0) {
                            key("⇧", width: edge * unit, dim: true)
                            Spacer(minLength: 0)
                            ForEach(Array(letters.enumerated()), id: \.offset) { _, l in key(l, width: width) }
                            Spacer(minLength: 0)
                            key("⌫", width: edge * unit, dim: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 3 * 30 + 2 * 4)
        .accessibilityElement()
        .accessibilityLabel(layout.rows.joined(separator: ", "))
    }

    private func key(_ label: String, width: CGFloat, dim: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .frame(width: max(width - 3, 0), height: 30)
            .background(dim ? Color(.systemGray4) : Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(.separator), lineWidth: 0.5))
            .frame(width: width)
    }
}

/// The Look page's keyboard: the layout in use, in the chosen theme and letter
/// colours, drawn with the keyboard's own palette.
private struct LookPreview: View {
    let settings: KeyboardSettings

    var body: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - 6) / 10
            let rows = settings.layout.rows
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    let letters = Array(row)
                    HStack(spacing: 0) {
                        if r == 2 { key("⇧", width: edge(letters) * unit, functional: true) }
                        Spacer(minLength: 0)
                        ForEach(Array(letters.enumerated()), id: \.offset) { i, c in
                            key(String(c).uppercased(), width: width(r, letters) * unit,
                                color: color(c, LetterSpot(row: r, x: center(r, i, letters))))
                        }
                        Spacer(minLength: 0)
                        if r == 2 { key("⌫", width: edge(letters) * unit, functional: true) }
                    }
                }
                HStack(spacing: 0) {
                    key("123", width: 1.5 * unit, functional: true)
                    key("⚙︎", width: 1 * unit, functional: true)
                    key(",", width: 1 * unit)
                    key("", width: 4 * unit)
                    key(".", width: 1 * unit)
                    key("⏎", width: 1.5 * unit, functional: true)
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 8)
        }
        .frame(height: 4 * 40 + 3 * 8 + 16)
        .background(Palette.background)
        .environment(\.colorScheme, scheme ?? colorScheme)
        .accessibilityElement()
        .accessibilityLabel("Keyboard preview")
    }

    @Environment(\.colorScheme) private var colorScheme
    private var scheme: ColorScheme? {
        switch settings.theme {
        case .system: return nil
        case .day: return .light
        case .night: return .dark
        }
    }

    // Same widths as the keyboard: the bottom letter row sits between shift and
    // delete (1.5 units each, or 1 when it has more than 7 letters).
    private func edge(_ letters: [Character]) -> CGFloat { letters.count > 7 ? 1 : 1.5 }
    private func width(_ r: Int, _ letters: [Character]) -> CGFloat {
        r < 2 ? 1 : min(1, (10 - 2 * edge(letters)) / CGFloat(letters.count))
    }
    /// Key centre in the 10-unit grid (for the left/right thumb split).
    private func center(_ r: Int, _ i: Int, _ letters: [Character]) -> Double {
        let w = width(r, letters)
        let start = (10 - CGFloat(letters.count) * w) / 2
        return Double(start + (CGFloat(i) + 0.5) * w)
    }

    private func color(_ c: Character, _ spot: LetterSpot) -> Color {
        guard let hex = settings.letterColors.hex(letter: Character(c.lowercased()), spot: spot),
              let ui = UIColor(hex: hex) else { return .primary }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui.readableOnDarkKeys : ui })
    }

    private func key(_ label: String, width: CGFloat, functional: Bool = false, color: Color = .primary) -> some View {
        Text(label)
            .font(.system(size: label.count > 1 ? 14 : 20))
            .foregroundStyle(functional ? .primary : color)
            .frame(width: max(width - 5, 0), height: 40)
            .background(functional ? Palette.functional : Palette.key, in: RoundedRectangle(cornerRadius: 6))
            .frame(width: width)
    }
}
