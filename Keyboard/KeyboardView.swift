import SwiftUI
import UIKit

enum Metrics {
    static let suggestionBarHeight: CGFloat = 40

    static func totalHeight(_ settings: KeyboardSettings) -> CGFloat {
        suggestionBarHeight + CGFloat(settings.rowHeight) * (settings.numberRow ? 5 : 4)
    }
}

private enum Palette {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    // Dark colours are Gboard's night theme, measured from a screenshot:
    // keys #424242, function keys #303030 on #212121.
    static let key = dynamic(light: .white, dark: UIColor(white: 0x42 / 255, alpha: 1))
    static let functional = dynamic(light: UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1),
                                    dark: UIColor(white: 0x30 / 255, alpha: 1))
    /// Flick guide cells: tinted so they stand apart from the keys they cover.
    static let flick = dynamic(light: UIColor(red: 0.84, green: 0.89, blue: 0.98, alpha: 1),
                               dark: UIColor(red: 0.20, green: 0.27, blue: 0.40, alpha: 1))
    /// Symbols in the keys' corners: white on the dark keys, like Gboard.
    static let hint = dynamic(light: UIColor(white: 0.35, alpha: 1), dark: UIColor(white: 1, alpha: 0.9))
    static let pressed = dynamic(light: UIColor(white: 0.80, alpha: 1), dark: UIColor(white: 0.40, alpha: 1))
    /// Behind the keys, painted in every theme: iOS's own backdrop is a
    /// frosted blur that tints the dark keyboard blue-grey with the app behind.
    static let background = dynamic(light: UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1),
                                    dark: UIColor(white: 0x21 / 255, alpha: 1))
}

struct KeyboardView: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        VStack(spacing: 0) {
            SuggestionBar(state: state)
                .frame(height: Metrics.suggestionBarHeight)
            keys
        }
        .frame(height: Metrics.totalHeight(state.settings))
        .background(Palette.background)
    }

    private var keys: some View {
        GeometryReader { geo in
            Group {
                if state.mode == .emoji {
                    EmojiPanel(state: state, size: geo.size)
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
        case .letters: base = Layouts.letters(state.settings, showGlobe: state.showGlobe)
        case .romaji: base = Layouts.letters(state.settings, showGlobe: state.showGlobe, romaji: true)
        case .kana: base = Layouts.kana(showGlobe: state.showGlobe)
        case .symbols: base = Layouts.symbols(state.settings, page: 1, showGlobe: state.showGlobe)
        case .symbols2: base = Layouts.symbols(state.settings, page: 2, showGlobe: state.showGlobe)
        default: base = Layouts.numpad
        }
        // Keys run to the screen edge; each key's own 3 pt padding is the
        // margin (like Gboard), so edge keys get the full cell to tap.
        let unit = width / 10
        let rowHeight = height / CGFloat(base.count)
        let rows = Self.placeLetters(base, numberRow: state.settings.numberRow,
                                     latin: state.mode == .letters || state.mode == .romaji)

        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        switch rows[r][i] {
                        case .gap(let units):
                            Color.clear.frame(width: units * unit, height: rowHeight)
                        case .key(let key):
                            let id = "\(r)-\(i)"
                            KeyView(key: key, state: state, large: state.mode == .kana || state.mode == .numpad,
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

extension UIColor {
    /// The user's colour, mixed with white just enough to read on the dark
    /// #424242 keys (relative luminance >= 0.4, about 4:1 contrast). Light
    /// colours come back unchanged; #007AFF becomes #66AFFF, #FF3B30 #FF8983.
    var readableOnDarkKeys: UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
            func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        var t: CGFloat = 0
        while t < 1, luminance(r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t) < 0.4 { t += 0.05 }
        return UIColor(red: r + (1 - r) * t, green: g + (1 - g) * t, blue: b + (1 - b) * t, alpha: a)
    }
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
            if state.popup == nil && state.flickGuide == nil {
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
            Text(state.display(s)).font(.system(size: large ? 26 : 21))
        case .shift:
            Image(systemName: state.shift == .locked ? "capslock.fill" : (state.shift == .on ? "shift.fill" : "shift"))
        case .backspace:
            Image(systemName: "delete.left")
        case .space:
            // Labelled on the numpad, where the space key isn't obvious, and
            // in romaji mode, which otherwise looks just like Latin.
            if state.mode == .romaji {
                Text("ローマ字").font(.system(size: 14)).foregroundStyle(.secondary)
            } else if large {
                Text("space").font(.system(size: 15))
            } else if state.mode == .letters {
                // The prediction languages, like Gboard's "EN · FR".
                Text(state.settings.predictionLanguages.map { $0.rawValue.uppercased() }.joined(separator: " · "))
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
        case .returnKey:
            Image(systemName: "return")
        case .toNumpad:
            Text("123").font(.system(size: 15))
        case .symbolPage:
            Text(state.mode == .symbols2 ? "123" : "#+=").font(.system(size: 15))
        case .toLetters:
            Text(state.textMode == .kana ? "かな" : state.textMode == .romaji ? "ローマ字" : "ABC")
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

/// Basic emoji picker: recently used first, then everything else.
/// Apple's emoji keyboard can't be opened from a custom keyboard.
private struct EmojiPanel: View {
    @ObservedObject var state: KeyboardState
    let size: CGSize

    private let cell: CGFloat = 40

    var body: some View {
        let bottomBar = CGFloat(state.settings.rowHeight)
        let gridRows = max(1, Int((size.height - bottomBar) / cell))
        let items = state.recentEmoji + EmojiData.all

        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(cell), spacing: 0), count: gridRows), spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, emoji in
                        Text(emoji)
                            .font(.system(size: 30))
                            .frame(width: cell + 4, height: cell)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.keyDown()
                                state.insertEmoji(emoji)
                            }
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(height: size.height - bottomBar)

            HStack(spacing: 0) {
                KeyView(key: Key(action: .toLetters), state: state, large: false)
                    .frame(width: 70, height: bottomBar)
                Spacer()
                KeyView(key: Key(action: .backspace), state: state, large: false)
                    .frame(width: 70, height: bottomBar)
            }
            .padding(.horizontal, 3)
        }
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
                        case .text(let s): Text(s)
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
        var list = items.map { ($0.label, $0.word, $0.isCorrection, false) }
        guard let chip = state.japaneseChip else { return list }
        if list.count >= 3 {
            // Never drop the pending fix or the "as typed" word.
            if let i = list.lastIndex(where: { !$0.2 && $0.0 == $0.1 }) { list.remove(at: i) } else { list.removeLast() }
        }
        let entry = (chip.text, chip.text, false, true)
        if state.japaneseChipFirst && state.pendingCorrection == nil { list.insert(entry, at: 0) } else { list.append(entry) }
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
            if entries.isEmpty, let note = state.setupNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider().frame(height: 22) }
                Button {
                    if item.isJapanese { state.pickJapanese() } else { state.pick(suggestion: item.word) }
                } label: {
                    Text(item.label)
                        .font(.system(size: item.isJapanese ? 17 : 16,
                                      weight: item.isCorrection ? .semibold : .regular))
                        .foregroundStyle(item.isJapanese ? Color.red : Color.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
