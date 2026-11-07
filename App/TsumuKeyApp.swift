import SwiftUI

@main
struct TsumuKeyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var timing = DeleteTiming.load()
    @State private var settings = KeyboardSettings.load()
    @State private var report = KeyboardReport.load()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {

                if report?.fullAccess != true {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(report == nil ? "Turn on Full Access" : "Full Access is off")
                                .font(.headline)
                            Text(report == nil
                                 ? "Add the TsumuKey keyboard, turn on Allow Full Access, then open the keyboard once (in the field above). Until then it uses default settings."
                                 : "The keyboard can't read your settings or downloaded models. Settings → General → Keyboard → Keyboards → TsumuKey → Allow Full Access.")
                                .font(.callout)
                            Text("iOS doesn't let apps ask for this; it's only switched on in Settings. TsumuKey uses it to share settings and models with the keyboard. The keyboard never goes online.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }

                Section {
                    Text("1. Settings → General → Keyboard → Keyboards → Add New Keyboard → TsumuKey")
                    Text("2. Tap TsumuKey in that list and turn on **Allow Full Access**, so the keyboard can read the settings below. iOS shows a warning for every keyboard with Full Access; TsumuKey's keyboard has no network access and nothing you type leaves your phone.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Set up")
                }
                .font(.callout)
                // The keyboard reports each time it opens (drives the Full Access card).
                .task {
                    while !Task.isCancelled {
                        report = KeyboardReport.load()
                        try? await Task.sleep(for: .seconds(2))
                    }
                }

                LayoutList(settings: $settings)

                ModelsSection(settings: $settings)

                Section {
                    Toggle("Auto-correct", isOn: $settings.autocorrect)
                    Picker("Japanese keyboard", selection: $settings.japaneseInput) {
                        ForEach(JapaneseInput.allCases) { Text($0.name).tag($0) }
                    }
                    Toggle("Japanese in ABC", isOn: $settings.japaneseInLatin)
                    Toggle("Number row", isOn: $settings.numberRow)
                    Picker("Tap 123 for", selection: $settings.numberKeyTap) {
                        ForEach(NumberKeyTap.allCases) { Text($0.name).tag($0) }
                    }
                    Toggle("Show symbols on keys", isOn: $settings.showSymbolHints)
                    Toggle("Hide-keyboard button", isOn: $settings.hideKeyboardButton)
                    RowHeightSlider(rowHeight: $settings.rowHeight)
                    Picker("Quick currency", selection: $settings.currency) {
                        ForEach(KeyboardSettings.currencies, id: \.self) { Text($0).tag($0) }
                    }
                } header: {
                    Text("Keyboard")
                } footer: {
                    Text("Japanese keyboard: かな is the flick pad, ローマ字 types romaji on the letter keys. Japanese in ABC: typing romaji (watashi, arigatou) offers 私, ありがとう in the bar; tap it to swap. Holding 123 opens the other number layout. Long-press still shows symbols when they're hidden. The quick currency sits on the third key of the middle row (D on QWERTY, S on Colemak, E on Dvorak); long-press it for the others.")
                }

                Section {
                    NavigationLink {
                        OrderedListPage(title: "Prediction Languages",
                                        items: $settings.predictionLanguages, all: PredictionLanguage.allCases,
                                        name: \.name, limit: KeyboardSettings.maxPredictionLanguages,
                                        firstNote: nil, topAction: "Move to Top",
                                        footer: "Up to \(KeyboardSettings.maxPredictionLanguages). Suggestions and autocorrect mix them; more would make autocorrect swap right words for look-alikes in another language.")
                    } label: {
                        LabeledContent("Prediction Languages",
                                       value: settings.predictionLanguages.map(\.name).joined(separator: ", "))
                    }
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
                    Text("Look")
                } footer: {
                    Text("Pick one colour scheme. Vowels can be coloured on top of any of them. Changes apply the next time the keyboard opens.")
                }

                Section {
                    TimingSlider(title: "Hold before repeating", value: $timing.holdDelay, range: 0.2...0.8)
                    TimingSlider(title: "Character repeat speed", value: $timing.charRepeat, range: 0.02...0.15)
                    TimingSlider(title: "Word repeat speed", value: $timing.wordRepeat, range: 0.15...0.7)
                    TimingSlider(title: "Time to chain taps", value: $timing.multiTapWindow, range: 0.15...0.6)
                    Button("Reset to defaults") { timing = DeleteTiming() }
                } header: {
                    Text("Delete key")
                } footer: {
                    Text("Tap: one character. Hold: characters, repeating. Tap then hold: one word. Double tap then hold: word after word. Lower numbers are faster.")
                }

                // Version at the very bottom; matches the entries in CHANGELOG.md.
                Section {} footer: {
                    let info = Bundle.main.infoDictionary
                    Text("TsumuKey \(info?["CFBundleShortVersionString"] as? String ?? "?") (build \(info?["CFBundleVersion"] as? String ?? "?"))")
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("TsumuKey")
            // The test field is pinned above the list, not inside it: iOS scrolls a
            // list back to its focused field whenever the keyboard changes height
            // (key height, number row), which jumped away from the setting being changed.
            .safeAreaInset(edge: .top, spacing: 0) { tryItHere }
            .onChange(of: timing) { _, new in new.save() }
            .onChange(of: settings) { _, new in new.save() }
            // The keyboard can change the layout too (long-press its settings key), so
            // re-read whenever the app comes back to the front.
            .onChange(of: fieldFocused) { _, focused in SharedSettings.setInAppField(focused) }
            .onChange(of: scenePhase) { _, phase in
                // Leaving the app: the keyboard must not offer "hide" elsewhere.
                SharedSettings.setInAppField(phase == .active && fieldFocused)
                guard phase == .active else { return }
                let latest = KeyboardSettings.load()
                if latest != settings { settings = latest }
            }
            // Lets simulator runs and UI tests open the keyboard without a tap.
            .task {
                // UI tests pass "-chainWindow <seconds>": the test runner pauses
                // between gestures, longer than a human would between taps.
                let chain = UserDefaults.standard.double(forKey: "chainWindow")
                if chain > 0 { timing.multiTapWindow = chain; timing.save() }
                let rowHeight = UserDefaults.standard.double(forKey: "rowHeight")
                if rowHeight > 0 { settings.rowHeight = rowHeight; settings.save() }
                // Temporary: "-memProbe 1" asks the keyboard to measure the
                // Japanese dictionary's memory cost the next time it opens.
                if UserDefaults.standard.bool(forKey: "memProbe") { text = "memprobe" }
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
                Bench.runIfRequested()
                guard ProcessInfo.processInfo.arguments.contains("-autofocus") else { return }
                // Focusing during the first layout pass is ignored; wait a moment.
                try? await Task.sleep(for: .milliseconds(500))
                fieldFocused = true
            }
        }
    }
}

/// Row in the main settings that opens the layout list, like iOS's
/// Settings → Keyboards → Keyboards.
private struct LayoutList: View {
    @Binding var settings: KeyboardSettings

    var body: some View {
        Section {
            NavigationLink {
                OrderedListPage(title: "Layouts",
                                items: $settings.menuLayouts, all: LetterLayout.allCases,
                                name: \.name, limit: KeyboardSettings.maxMenuLayouts, firstNote: "Default",
                                topAction: "Make Default",
                                footer: "Up to \(KeyboardSettings.maxMenuLayouts). The first one is the default.")
                    .onChange(of: settings.menuLayouts) { _, list in
                        // The keyboard opens on the top layout.
                        if let first = list.first, first != settings.layout { settings.layout = first }
                    }
            } label: {
                LabeledContent("Layouts", value: settings.menuLayouts.map(\.name).joined(separator: ", "))
            }
        } footer: {
            Text("The first layout is the default. Hold the ⚙︎ key to switch between them; the Japanese keyboard is always in that menu too.")
        }
    }
}

/// One page for an ordered pick list: what's in use on top (first = default),
/// everything else below. Tap to add (greyed out when full). Swipe left to
/// remove, right to move to the top. At least 1 item, at most `limit`.
private struct OrderedListPage<Item: Identifiable & Hashable>: View {
    let title: String
    @Binding var items: [Item]
    let all: [Item]
    let name: KeyPath<Item, String>
    let limit: Int
    /// Shown under the first row ("Default"), or nil.
    let firstNote: String?
    let topAction: String
    let footer: String

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
                            Button(topAction) {
                                items.removeAll { $0 == item }
                                items.insert(item, at: 0)
                            }
                            .tint(.blue)
                        }
                    }
                }
            } header: {
                Text("In use")
            } footer: {
                Text(footer + " Swipe left to remove, right to \(topAction.lowercased()).")
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
                    }
                } header: {
                    Text("Add")
                } footer: {
                    if items.count >= limit { Text("Up to \(limit). Remove one to add another.") }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
