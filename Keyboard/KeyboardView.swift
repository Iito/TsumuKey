import SwiftUI
import UIKit

enum Metrics {
    static let suggestionBarHeight: CGFloat = 40

    static func totalHeight(_ settings: KeyboardSettings) -> CGFloat {
        suggestionBarHeight + CGFloat(settings.rowHeight) * (settings.numberRow ? 5 : 4)
    }
}


struct KeyboardView: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if state.emojiSearch != nil {
                    EmojiSearchBar(state: state)
                } else {
                    SuggestionBar(state: state)
                }
            }
            .frame(height: Metrics.suggestionBarHeight)
            keys
        }
        .frame(height: Metrics.totalHeight(state.settings))
        .background(Palette.background)
        .coordinateSpace(name: "root")
        .onPreferenceChange(ChipFramePreference.self) { chipFrame = $0 }
        .overlay(alignment: .topLeading) {
            if !state.choices.isEmpty, state.choicesDropDown {
                JapaneseChoiceMenu(state: state, chip: chipFrame)
            }
        }
    }

    /// Where the Japanese chip sits, for the long-press menu.
    @State private var chipFrame: CGRect = .zero

    private var keys: some View {
        GeometryReader { geo in
            Group {
                if state.mode == .emoji {
                    EmojiPanel(state: state, size: geo.size)
                } else if !state.choices.isEmpty, !state.choicesDropDown {
                    ChoiceGrid(state: state)
                } else {
                    grid(size: geo.size)
                }
            }
            .onAppear {
                state.keyboardWidth = geo.size.width
                state.keyboardHeight = geo.size.height
            }
            .onChange(of: geo.size) { _, size in
                state.keyboardWidth = size.width
                state.keyboardHeight = size.height
            }
        }
        .coordinateSpace(name: "kb")
        .overlay(alignment: .topLeading) { PopupView(state: state) }
        .overlay(alignment: .topLeading) { FlickGuideView(state: state) }
    }

    @ViewBuilder private func grid(size: CGSize) -> some View {
        if let side = state.oneHand {
            let keysWidth = (size.width * 0.82).rounded()
            HStack(spacing: 0) {
                if side == .right { oneHandStrip(side: side) }
                rows(width: keysWidth, height: size.height)
                if side == .left { oneHandStrip(side: side) }
            }
        } else {
            rows(width: size.width, height: size.height)
        }
    }

    /// The empty side in one-handed mode: move the keys across, or go back to full width.
    private func oneHandStrip(side: OneHandSide) -> some View {
        VStack(spacing: 28) {
            Button { state.oneHand = side == .left ? .right : .left } label: {
                Image(systemName: side == .left ? "chevron.right" : "chevron.left")
            }
            Button { state.oneHand = nil } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
        .font(.system(size: 20))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rows(width: CGFloat, height: CGFloat) -> some View {
        let base: [[RowItem]]
        switch state.mode {
        case .letters: base = Layouts.letters(state.settings, showGlobe: state.showGlobe, field: state.field)
        case .romaji: base = Layouts.letters(state.settings, showGlobe: state.showGlobe, romaji: true, field: state.field)
        case .kana: base = Layouts.kana(showGlobe: state.showGlobe)
        case .hangul:
            base = state.settings.koreanInput == .cheonjiin
                ? Layouts.cheonjiin(state.settings, showGlobe: state.showGlobe)
                : Layouts.hangul(state.settings, showGlobe: state.showGlobe)
        case .symbols: base = Layouts.symbols(state.settings, page: 1, showGlobe: state.showGlobe)
        case .symbols2: base = Layouts.symbols(state.settings, page: 2, showGlobe: state.showGlobe)
        default: base = Layouts.numpad
        }
        // Keys run to the screen edge; each key's own 3 pt padding is the
        // margin (like Gboard), so edge keys get the full cell to tap.
        let unit = width / 10
        let rowHeight = height / CGFloat(base.count)
        let rows = Self.placeLetters(base, numberRow: state.settings.numberRow,
                                     latin: state.mode == .letters || state.mode == .romaji || state.mode == .hangul)

        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        switch rows[r][i] {
                        case .gap(let units):
                            Color.clear.frame(width: units * unit, height: rowHeight)
                        case .key(let key):
                            let id = "\(r)-\(i)"
                            KeyView(key: key, state: state, large: state.mode == .kana || state.mode == .numpad
                                         || (state.mode == .hangul && state.settings.koreanInput == .cheonjiin),
                                    pressedID: id)
                                .frame(width: key.units * unit, height: rowHeight)
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: KeyGeometryPreference.self, value: [
                                        KeyGeometry(id: id, key: key,
                                                    local: g.frame(in: .named("rows")),
                                                    kb: g.frame(in: .named("kb"))),
                                    ])
                                })
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: "rows")
        // Touches for the whole grid go through one view (see TouchLayer).
        .overlayPreferenceValue(KeyGeometryPreference.self) { keys in
            ZStack(alignment: .topLeading) {
                TouchLayer(state: state, keys: keys)
                KeyPreviews(state: state, keys: keys)
            }
        }
    }
}

extension KeyboardView {
    /// Tags each letter key with its letter row and x position, so label
    /// colours can follow rows, halves and vowels.
    static func placeLetters(_ rows: [[RowItem]], numberRow: Bool, latin: Bool) -> [[RowItem]] {
        guard latin else { return rows }
        let first = numberRow ? 1 : 0
        return rows.enumerated().map { r, row in
            guard r >= first && r < first + 3 else { return row }
            var x: CGFloat = 0
            return row.map { item in
                switch item {
                case .gap(let units):
                    x += units
                    return item
                case .key(var key):
                    if case .text(let s) = key.action, s.count == 1, s.first!.isLetter {
                        key.spot = LetterSpot(row: r - first, x: Double(x + key.units / 2))
                    }
                    x += key.units
                    return .key(key)
                }
            }
        }
    }
}

/// Label colour from the settings: whole keyboard, or a group of letters.
func labelColor(for key: Key, settings: KeyboardSettings) -> Color {
    var letter: Character?
    if case .text(let s) = key.action, s.count == 1, let c = s.lowercased().first, c.isLetter { letter = c }
    guard let hex = settings.letterColors.hex(letter: letter, spot: key.spot),
          let color = UIColor(hex: hex) else { return .primary }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? color.readableOnDarkKeys : color })
}


/// Gboard-style key popups: the letter under each finger, enlarged in a
/// bubble above the key, so a thumb covering the key doesn't hide it.
private struct KeyPreviews: View {
    @ObservedObject var state: KeyboardState
    let keys: [KeyGeometry]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            // A long-press menu or flick guide already shows what's selected.
            if state.settings.characterPreview && state.popup == nil && state.flickGuide == nil {
                ForEach(keys.filter { state.pressedKeys.contains($0.id) }, id: \.id) { geo in
                    if case .text(let s) = geo.key.action, geo.key.flicks.isEmpty, geo.key.units <= 1 {
                        bubble(state.display(s), color: labelColor(for: geo.key, settings: state.settings),
                               over: geo.local.insetBy(dx: 3, dy: 5))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func bubble(_ text: String, color: Color, over key: CGRect) -> some View {
        let width = key.width + 20, height = key.height + 14
        // The extension can't draw outside its view: on the top row the
        // bubble stops at the suggestion bar's top edge and overlaps the key.
        let y = max(key.minY - height - 6, -Metrics.suggestionBarHeight)
        let x = min(max(key.midX - width / 2, 0), state.keyboardWidth - width)
        return Text(text)
            .font(.system(size: 36))
            .foregroundStyle(color)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.key)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1))
            .offset(x: x, y: y)
    }
}

struct KeyView: View {
    let key: Key
    @ObservedObject var state: KeyboardState
    let large: Bool
    /// Set for keys in the main grid: TouchLayer handles their touches and
    /// this view only draws. Nil for standalone keys that handle their own.
    var pressedID: String? = nil

    @State private var pressed = false
    @State private var longPressed = false
    @State private var holdWork: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("kb"))
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isPressed ? Palette.pressed : (isFunctional ? Palette.functional : Palette.key))
                    .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
                label
                    .foregroundStyle(labelColor(for: key, settings: state.settings))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let icon = key.hintIcon {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.hint)
                        .padding(.top, 3)
                        .padding(.trailing, 3)
                } else if let hint = key.hint, key.alwaysShowHint || state.settings.showSymbolHints {
                    Text(hint)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.hint)
                        .padding(.top, 2)
                        .padding(.trailing, 3)
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 5)
            // The whole cell, gaps included, is the touch target: no dead zones between keys.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("kb"))
                    .onChanged { value in
                        if !pressed {
                            pressed = true
                            state.keyDown()
                            began(over: frame)
                        }
                        if longPressed { state.movePopupSelection(to: value.location) }
                    }
                    .onEnded { _ in ended() },
                // Grid keys get their touches from TouchLayer instead.
                including: pressedID == nil ? .all : .none
            )
        }
    }

    private var isPressed: Bool {
        pressedID.map { state.pressedKeys.contains($0) } ?? pressed
    }

    private var isFunctional: Bool {
        switch key.action {
        case .text, .space, .kanaModifier: return false
        default: return true
        }
    }

    @ViewBuilder private var label: some View {
        switch key.action {
        case .text(let s):
            // "www." fits a key in a smaller size.
            Text(state.display(s)).font(.system(size: s.count > 1 ? 16 : large ? 26 : 21))
                .lineLimit(1).minimumScaleFactor(0.6)
        case .shift:
            Image(systemName: state.shift == .locked ? "capslock.fill" : (state.shift == .on ? "shift.fill" : "shift"))
        case .backspace:
            Image(systemName: "delete.left")
        case .space:
            // Labelled on the numpad, where the space key isn't obvious, and
            // in romaji mode, which otherwise looks just like Latin.
            if state.mode == .romaji {
                Text("ローマ字").font(.system(size: 14)).foregroundStyle(.secondary)
            } else if state.mode == .hangul {
                Text("스페이스").font(.system(size: 14)).foregroundStyle(.secondary)
            } else if large {
                Text("space").font(.system(size: 15))
            } else if state.mode == .letters {
                // The prediction languages, like Gboard's "EN · FR".
                Text((state.settings.autoLanguages ? state.activeLanguages : state.settings.manualLanguages)
                    .map { $0.rawValue.uppercased() }.joined(separator: " · "))
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
        case .returnKey:
            Image(systemName: "return")
        case .toNumpad:
            Text("123").font(.system(size: 15))
        case .symbolPage:
            Text(state.mode == .symbols2 ? "123" : "#+=").font(.system(size: 15))
        case .toLetters:
            Text(state.textMode == .kana ? "かな" : state.textMode == .romaji ? "ローマ字"
                 : state.textMode == .hangul ? "한글" : "ABC")
                .font(.system(size: 15))
        case .globe:
            Image(systemName: "globe")
        case .language:
            Image(systemName: "gearshape")
        case .emoji:
            Image(systemName: "face.smiling")
        case .cursor(let n):
            Image(systemName: n < 0 ? "arrow.left" : "arrow.right")
        case .kanaModifier:
            Text("゛゜小").font(.system(size: 17))
        }
    }

    private func began(over frame: CGRect) {
        switch key.action {
        case .backspace:
            state.backspace.down()
        case .language:
            schedule(after: 0.4) {
                longPressed = true
                state.showKeyboardMenu(over: frame)
            }
        case .text where !key.alternates.isEmpty || !key.actions.isEmpty:
            schedule(after: 0.3) {
                longPressed = true
                state.showPopup(for: key, over: frame)
            }
        default:
            break
        }
    }

    private func ended() {
        holdWork?.cancel()
        if key.action == .backspace {
            state.backspace.up()
        } else if longPressed {
            state.commitPopup()
        } else {
            state.tap(key)
        }
        pressed = false
        longPressed = false
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        let item = DispatchWorkItem(block: work)
        holdWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

}

/// Emoji picker: a search pill, the emoji by category (recently used first),
/// and a category bar to jump between them. Apple's emoji keyboard can't be
/// opened from a custom keyboard.
private struct EmojiPanel: View {
    @ObservedObject var state: KeyboardState
    let size: CGSize

    private let cell: CGFloat = 40
    private let searchHeight: CGFloat = 36
    @State private var current: EmojiData.Category = .smileys
    @State private var visible: Set<Int> = []

    private struct Item { let emoji: String; let base: String; let category: EmojiData.Category }

    private var items: [Item] {
        state.recentEmoji.map { Item(emoji: $0, base: $0, category: .recents) }
            + EmojiData.entries.map { Item(emoji: EmojiData.toned($0.emoji, state.settings.emojiSkinTone),
                                           base: $0.emoji, category: $0.category) }
    }

    var body: some View {
        let bottomBar = CGFloat(state.settings.rowHeight)
        let gridHeight = size.height - bottomBar - searchHeight
        let gridRows = max(1, Int(gridHeight / cell))
        let items = self.items
        let firsts = Dictionary(items.indices.map { (items[$0].category, $0) }, uniquingKeysWith: min)

        VStack(spacing: 0) {
            if let choices = state.tonePicker {
                TonePickerRow(state: state, choices: choices)
                    .frame(height: searchHeight)
            } else {
            Button {
                state.keyDown()
                state.startEmojiSearch()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Search emoji")
                    Spacer()
                }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: searchHeight - 8)
                .background(Palette.key, in: Capsule())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(cell), spacing: 0), count: gridRows), spacing: 0) {
                        ForEach(items.indices, id: \.self) { i in
                            Text(items[i].emoji)
                                .font(.system(size: 30))
                                .frame(width: cell + 4, height: cell)
                                .contentShape(Rectangle())
                                .id(i)
                                .onTapGesture {
                                    state.keyDown()
                                    state.tonePicker = nil
                                    state.insertEmoji(items[i].emoji)
                                }
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    if let choices = EmojiData.toneChoices(items[i].base) {
                                        state.keyDown()
                                        state.tonePicker = choices
                                    }
                                }
                                // The category of the leftmost visible emoji is the current one.
                                .onAppear { visible.insert(i); updateCurrent(items) }
                                .onDisappear { visible.remove(i); updateCurrent(items) }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: gridHeight)

                HStack(spacing: 0) {
                    KeyView(key: Key(action: .toLetters), state: state, large: false)
                        .frame(width: 56, height: bottomBar)
                    ForEach(EmojiData.Category.allCases) { c in
                        if let first = firsts[c] {
                            Button {
                                state.keyDown()
                                current = c
                                proxy.scrollTo(first, anchor: .leading)
                            } label: {
                                Image(systemName: c.symbol)
                                    .font(.system(size: 15))
                                    .foregroundStyle(current == c ? Color.primary : Color.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(c.name)
                        }
                    }
                    KeyView(key: Key(action: .backspace), state: state, large: false)
                        .frame(width: 56, height: bottomBar)
                }
                .frame(height: bottomBar)
            }
        }
    }

    private func updateCurrent(_ items: [Item]) {
        guard let first = visible.min(), first < items.count else { return }
        let c = items[first].category
        if c != current { current = c }
    }
}

/// The long-pressed emoji in its default yellow and five skin tones; tap one
/// to type it, ✕ to close.
private struct TonePickerRow: View {
    @ObservedObject var state: KeyboardState
    let choices: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(choices, id: \.self) { emoji in
                Text(emoji)
                    .font(.system(size: 26))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.keyDown()
                        state.tonePicker = nil
                        state.insertEmoji(emoji)
                    }
            }
            Button {
                state.keyDown()
                state.tonePicker = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                    .frame(width: 36).frame(maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close skin tones")
        }
        .background(Palette.key.opacity(0.6), in: Capsule())
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

/// Emoji search: the query (typed on the letter keys below) and the matches,
/// in the suggestion bar's place. ✕ goes back to the emoji panel.
private struct EmojiSearchBar: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        let query = state.emojiSearch ?? ""
        let results = EmojiData.search(query)
        let tone = state.settings.emojiSkinTone
        HStack(spacing: 6) {
            Button {
                state.keyDown()
                state.endEmojiSearch()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close search")
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(query.isEmpty ? "Search emoji" : query)
                    .foregroundStyle(query.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }
            .font(.system(size: 15))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(Palette.key, in: Capsule())
            .fixedSize()
            if let choices = state.tonePicker {
                TonePickerRow(state: state, choices: choices)
            } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(results, id: \.self) { base in
                        Text(EmojiData.toned(base, tone))
                            .font(.system(size: 26))
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.keyDown()
                                state.insertEmoji(EmojiData.toned(base, tone))
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                if let choices = EmojiData.toneChoices(base) {
                                    state.keyDown()
                                    state.tonePicker = choices
                                }
                            }
                    }
                }
            }
            }
        }
        .padding(.horizontal, 6)
    }
}

private struct PopupView: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        if let p = state.popup, p.menu {
            MenuPanel(popup: p)
        } else if let p = state.popup {
            let layout = p.vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(p.options.indices, id: \.self) { i in
                    Group {
                        switch p.options[i] {
                        case .text(let s): Text(s).font(.system(size: s.count > 2 ? 17 : 20))
                        case .action(let a):
                            if let title = a.title {
                                Text(title).font(.system(size: 15, weight: .medium))
                            } else {
                                Image(systemName: a.symbol)
                            }
                        }
                    }
                        .font(.system(size: 20))
                        .foregroundStyle(i == p.selected ? Color.white : Color.primary)
                        .frame(width: p.cellWidth, height: p.vertical ? p.cellHeight : p.frame.height - 8)
                        .background(i == p.selected ? Color.blue : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.key).shadow(radius: 3))
            .offset(x: p.frame.minX, y: p.frame.minY)
            .allowsHitTesting(false)
        }
    }
}

/// The settings key's menu, drawn like the iPhone's globe-key menu: a
/// rounded panel of left-aligned rows split by thin lines, a checkmark on
/// the keyboard in use, and a grey highlight under the finger.
private struct MenuPanel: View {
    let popup: Popup

    var body: some View {
        VStack(spacing: 0) {
            ForEach(popup.options.indices, id: \.self) { i in
                if i > 0 { Divider().padding(.leading, 14) }
                HStack(spacing: 8) {
                    if case .action(let a) = popup.options[i], let title = a.title {
                        Text(title).font(.system(size: 17)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 4)
                    if popup.checked == i {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .frame(width: popup.cellWidth + 8, height: popup.cellHeight)
                .background(i == popup.selected ? Color.primary.opacity(0.12) : Color.clear)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 2)
        .frame(width: popup.frame.width, height: popup.frame.height)
        .offset(x: popup.frame.minX, y: popup.frame.minY)
        .allowsHitTesting(false)
    }
}

/// Flick kana drawn on the key's sides (left, up, right, down), each the
/// size of a key, covering the neighbours like the iPhone's guide.
private struct FlickGuideView: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        if let g = state.flickGuide {
            // Index 1-4: left, up, right, down.
            let directions: [CGSize] = [.zero, CGSize(width: -1, height: 0), CGSize(width: 0, height: -1),
                                        CGSize(width: 1, height: 0), CGSize(width: 0, height: 1)]
            ZStack(alignment: .topLeading) {
                ForEach(1..<min(g.options.count, directions.count), id: \.self) { i in
                    if !g.options[i].isEmpty, g.full || i == g.selected {
                        let selected = i == g.selected
                        let frame = cellFrame(g.key, directions[i])
                        Text(g.options[i])
                            .font(.system(size: 26))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .frame(width: frame.width - 6, height: frame.height - 10)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Color.blue : Palette.flick)
                                .shadow(radius: 2))
                            .offset(x: frame.minX + 3, y: frame.minY + 5)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// The key's neighbour in that direction. The extension can't draw
    /// outside its own view, so near an edge the cell is cut short rather
    /// than shifted, keeping it lined up with the key.
    private func cellFrame(_ key: CGRect, _ d: CGSize) -> CGRect {
        let r = key.offsetBy(dx: d.width * key.width, dy: d.height * key.height)
        let bounds = CGRect(x: 0, y: -Metrics.suggestionBarHeight, width: state.keyboardWidth,
                            height: state.keyboardHeight + Metrics.suggestionBarHeight)
        return r.intersection(bounds)
    }
}

private struct SuggestionBar: View {
    @ObservedObject var state: KeyboardState

    /// With a pending fix, iOS-style: "as typed" in quotes, then the fix in bold.
    private var items: [(label: String, word: String, isCorrection: Bool)] {
        guard let fix = state.pendingCorrection else {
            return state.suggestions.map { ($0, $0, false) }
        }
        let typed = state.typedWord
        var result = [("\u{201C}\(typed)\u{201D}", typed, false), (fix, fix, true)]
        if let extra = state.suggestions.first { result.append((extra, extra, false)) }
        return result
    }

    /// The words, plus the Japanese chip in place of one of them: first when
    /// the typed word isn't English or French, else last.
    private var entries: [(label: String, word: String, isCorrection: Bool, isJapanese: Bool)] {
        // A sum's result replaces the words: they're about the text before "=".
        if !state.mathResults.isEmpty {
            return state.mathResults.enumerated().map { ($0.element.label, $0.element.text, $0.offset == 0, false) }
        }
        var list = items.map { ($0.label, $0.word, $0.isCorrection, false) }
        guard let chip = state.chipText else { return list }
        if list.count >= 3 {
            // Never drop the pending fix or the "as typed" word.
            if let i = list.lastIndex(where: { !$0.2 && $0.0 == $0.1 }) { list.remove(at: i) } else { list.removeLast() }
        }
        let entry = (chip, chip, false, true)
        if state.japaneseChipFirst && state.pendingCorrection == nil { list.insert(entry, at: 0) } else { list.append(entry) }
        return list
    }

    /// `entries` with the emoji in the last slot, in place of a plain word
    /// (never the pending fix, the word as typed or the Japanese chip).
    private var entriesWithEmoji: [(label: String, word: String, isCorrection: Bool, isJapanese: Bool)] {
        var list = entries
        guard state.mathResults.isEmpty, let emoji = state.emojiSuggestion else { return list }
        if list.count >= 3 {
            guard let i = list.lastIndex(where: { !$0.2 && !$0.3 && $0.0 == $0.1 }) else { return list }
            list.remove(at: i)
        }
        list.append((emoji, emoji, false, false))
        return list
    }

    var body: some View {
        if state.mode.isJapanese && !state.kanaCandidates.isEmpty {
            kanaRow
        } else {
            suggestionRow
        }
    }

    /// Conversion candidates: as many as fit, scroll for more.
    private var kanaRow: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(state.kanaCandidates.enumerated()), id: \.offset) { index, text in
                        if index > 0 { Divider().frame(height: 22) }
                        let selected = index == state.kanaSelected
                        Button {
                            state.keyDown()
                            state.commitCandidate(at: index)
                        } label: {
                            Text(text)
                                .font(.system(size: 18, weight: index == 0 ? .semibold : .regular))
                                .lineLimit(1)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .frame(minWidth: 44, maxHeight: .infinity)
                                .background(selected ? Color.blue : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .onChange(of: state.kanaSelected) { _, i in
                if let i { withAnimation { scroller.scrollTo(i, anchor: .center) } }
            }
        }
    }

    private var suggestionRow: some View {
        HStack(spacing: 0) {
            if state.canPaste {
                Button {
                    state.keyDown()
                    state.paste()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 17))
                        .frame(width: 44)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !state.suggestions.isEmpty { Divider().frame(height: 22) }
            }
            if entriesWithEmoji.isEmpty, let note = state.setupNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(entriesWithEmoji.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider().frame(height: 22) }
                // Tap picks; a long press opens the grid of alternatives (the
                // Japanese chip: its conversions).
                let isEmoji = !item.isCorrection && item.word == state.emojiSuggestion
                let math = state.mathResults.first(where: { $0.text == item.word })
                MorphText(text: item.label)
                    .font(.system(size: item.isJapanese ? 17 : 16, weight: item.isCorrection ? .semibold : .regular))
                    .foregroundStyle(item.isJapanese ? Color.red : Color.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if item.isJapanese { state.pickJapanese() }
                        else if isEmoji { state.pickEmoji() }
                        else if let math { state.pickMath(math) }
                        else { state.pick(suggestion: item.word) }
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        if item.isJapanese { state.showJapaneseChoices() }
                        else if !isEmoji, math == nil { state.showWordChoices(pressed: item.word) }
                    }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ChipFramePreference.self,
                                               value: item.isJapanese ? g.frame(in: .named("root")) : .zero)
                    })
            }
            // ⌄ for the Japanese conversions (grid style); ⌃ closes any grid.
            if !state.choices.isEmpty && !state.choicesDropDown
                || state.choices.isEmpty && state.hasJapaneseChoices && state.settings.japaneseChoices == .grid {
                Button {
                    state.keyDown()
                    state.toggleChoices()
                } label: {
                    Image(systemName: state.choices.isEmpty ? "chevron.down" : "chevron.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More conversions")
            }
            if state.inAppField || state.settings.hideKeyboardButton {
                Divider().frame(height: 22)
                Button {
                    state.keyDown()
                    state.controller?.dismissKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 17))
                        .frame(width: 44)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide keyboard")
            }
        }
        .padding(.horizontal, 6)
    }
}

/// A word that changes like the iOS suggestion bar's: letters the old and new
/// word share (in order) slide to their new place, the others fade out or in,
/// in about 0.25 s (iOS measured 0.2 s in a 60 fps recording; a touch slower felt better).
/// Too wide for its slot, it falls back to a plain truncated Text.
private struct MorphText: View {
    let text: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Letters(text: text).fixedSize()
            Text(text).lineLimit(1)
        }
    }

    private struct Letters: View {
        let text: String
        @State private var letters: [Letter] = []
        @State private var nextID = 0

        struct Letter: Identifiable { let id: Int; let char: Character }

        var body: some View {
            HStack(spacing: 0) {
                ForEach(letters) { letter in
                    Text(String(letter.char))
                        .transition(.opacity)
                }
            }
            .onAppear { letters = fresh(Array(text)) }
            .onChange(of: text) { _, new in
                withAnimation(.smooth(duration: 0.25)) { letters = morph(to: Array(new)) }
            }
        }

        private func fresh(_ chars: [Character]) -> [Letter] {
            defer { nextID += chars.count }
            return chars.enumerated().map { Letter(id: nextID + $0.offset, char: $0.element) }
        }

        /// New letters keep the identity of the old letters they match in a
        /// longest common subsequence, so SwiftUI slides them instead of fading.
        private func morph(to new: [Character]) -> [Letter] {
            let old = letters
            let n = old.count, m = new.count
            var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = old[i].char == new[j]
                        ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
            var result: [Letter] = []
            var i = 0, j = 0, id = nextID
            while j < m {
                if i < n, old[i].char == new[j], lcs[i][j] == lcs[i + 1][j + 1] + 1 {
                    result.append(old[i]); i += 1; j += 1
                } else if i < n, lcs[i + 1][j] >= lcs[i][j + 1] {
                    i += 1
                } else {
                    result.append(Letter(id: id, char: new[j])); id += 1; j += 1
                }
            }
            nextID = id
            return result
        }
    }
}

struct ChipFramePreference: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Long press on the Japanese chip in the ABC keyboard: its top 10
/// conversions, dropping down from the chip over the keys. A tap outside
/// closes it; typing never reaches the keys while it's open.
private struct JapaneseChoiceMenu: View {
    @ObservedObject var state: KeyboardState
    let chip: CGRect
    private let rowHeight: CGFloat = 42

    var body: some View {
        GeometryReader { geo in
            let width = min(max(chip.width, 170), geo.size.width - 12)
            let x = min(max(chip.midX - width / 2, 6), geo.size.width - width - 6)
            let top = Metrics.suggestionBarHeight
            let height = min(CGFloat(state.choices.count) * rowHeight, geo.size.height - top - 6)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .onTapGesture { state.hideChoices() }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(state.choices.enumerated()), id: \.offset) { index, text in
                            if index > 0 { Divider() }
                            Button {
                                state.keyDown()
                                state.pickChoice(index)
                            } label: {
                                Text(text)
                                    .font(.system(size: 18, weight: index == 0 ? .semibold : .regular))
                                    .lineLimit(1)
                                    .foregroundStyle(Color.red)
                                    .frame(maxWidth: .infinity, minHeight: rowHeight)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: width, height: height)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                .offset(x: x, y: top)
            }
        }
    }
}

/// The long-press grid: the bar word's alternatives (or the Japanese
/// conversions) in place of the keys, four to a row, like the iOS kana
/// keyboard's expanded candidates. ⌃ in the bar or picking one brings the
/// keys back.
private struct ChoiceGrid: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 0) {
                ForEach(Array(state.choices.enumerated()), id: \.offset) { index, text in
                    Button {
                        state.keyDown()
                        state.pickChoice(index)
                    } label: {
                        Text(text)
                            .font(.system(size: 21, weight: index == 0 ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
        }
    }
}
