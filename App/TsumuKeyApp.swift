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
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Try it here") {
                    // Lets the typing benchmark (UI test) reset the field between
                    // sentences. Above the field, so a long text can't push it off screen.
                    Button("Clear") { text = "" }
                        .accessibilityIdentifier("clearField")
                    TextField("Type something…", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($fieldFocused)
                        .accessibilityIdentifier("testField")
                }

                Section {
                    Text("1. Settings → General → Keyboard → Keyboards → Add New Keyboard → TsumuKey")
                    Text("2. Tap TsumuKey in that list and turn on **Allow Full Access**, so the keyboard can read the settings below.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Set up")
                } footer: {
                    // Matches the entries in CHANGELOG.md.
                    let info = Bundle.main.infoDictionary
                    Text("Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (build \(info?["CFBundleVersion"] as? String ?? "?"))")
                }
                .font(.callout)

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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Key height")
                            Spacer()
                            Text("\(Int(settings.rowHeight)) pt").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.rowHeight, in: KeyboardSettings.rowHeightRange, step: 1)
                    }
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
                        OrderedListPage(title: "Prediction Languages", addTitle: "Add New Language",
                                        items: $settings.predictionLanguages, all: PredictionLanguage.allCases,
                                        name: \.name, limit: KeyboardSettings.maxPredictionLanguages,
                                        firstNote: nil,
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
                    Text("Tap: one character. Hold: characters, repeating. Tap then hold: one word. Double tap then hold: word after word. Lower numbers are faster. Changes apply the next time the keyboard opens.")
                }

            }
            .navigationTitle("TsumuKey")
            .onChange(of: timing) { _, new in new.save() }
            .onChange(of: settings) { _, new in new.save() }
            // The keyboard can change the layout too (long-press its settings key), so
            // re-read whenever the app comes back to the front.
            .onChange(of: scenePhase) { _, phase in
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
                OrderedListPage(title: "Layouts", addTitle: "Add New Layout",
                                items: $settings.menuLayouts, all: LetterLayout.allCases,
                                name: \.name, limit: KeyboardSettings.maxMenuLayouts, firstNote: "Default",
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

/// An ordered pick list like iOS's Settings → Keyboards → Keyboards: Edit
/// shows delete buttons and drag handles (only then can rows move or go),
/// "Add New…" picks from the rest. At least 1 item, at most `limit`.
private struct OrderedListPage<Item: Identifiable & Hashable>: View {
    let title: String
    let addTitle: String
    @Binding var items: [Item]
    let all: [Item]
    let name: KeyPath<Item, String>
    let limit: Int
    /// Shown under the first row ("Default"), or nil.
    let firstNote: String?
    let footer: String
    @State private var editMode: EditMode = .inactive

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
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { rows in
                    guard items.count > rows.count else { return }
                    items.remove(atOffsets: rows)
                }
                .deleteDisabled(!editMode.isEditing || items.count <= 1)
                .moveDisabled(!editMode.isEditing)
            } footer: {
                Text(footer)
            }

            if !editMode.isEditing {
                Section {
                    NavigationLink(addTitle) {
                        AddItemPage(title: addTitle, items: $items, all: all, name: name, limit: limit)
                    }
                    .disabled(items.count >= limit)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .environment(\.editMode, $editMode)
    }
}

private struct AddItemPage<Item: Identifiable & Hashable>: View {
    let title: String
    @Binding var items: [Item]
    let all: [Item]
    let name: KeyPath<Item, String>
    let limit: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(all.filter { !items.contains($0) }) { item in
            Button(item[keyPath: name]) {
                if items.count < limit { items.append(item) }
                dismiss()
            }
            .foregroundStyle(Color.primary)
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
