import SwiftUI
import UIKit

/// Where a key sits, in two coordinate spaces: `local` for hit-testing in the
/// touch layer (which covers exactly the key rows), `kb` for placing popups.
struct KeyGeometry: Equatable {
    let id: String
    let key: Key
    let local: CGRect
    let kb: CGRect
}

struct KeyGeometryPreference: PreferenceKey {
    static var defaultValue: [KeyGeometry] = []
    static func reduce(value: inout [KeyGeometry], nextValue: () -> [KeyGeometry]) {
        value += nextValue()
    }
}

/// One UIKit view handles every finger for the key rows. Per-key SwiftUI
/// gestures dropped taps when fast typing made fingers overlap; here each
/// touch is tracked on its own and overlap is resolved like a hardware
/// keyboard ("rollover").
struct TouchLayer: UIViewRepresentable {
    let state: KeyboardState
    let keys: [KeyGeometry]

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.state = state
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.state = state
        view.keys = keys
        state.keyMap = Self.keyMap(keys)
    }

    /// Letter (and apostrophe) key centers, in the same space as the points
    /// TouchView reports.
    private static func keyMap(_ keys: [KeyGeometry]) -> KeyMap {
        var map = KeyMap()
        for geo in keys {
            guard case .text(let s) = geo.key.action, s.count == 1,
                  let letter = s.lowercased().first, letter.isASCII,
                  letter.isLetter || letter == "'" else { continue }
            map.centers[letter] = CGPoint(x: geo.local.midX, y: geo.local.midY)
            map.keySize = geo.local.size
        }
        return map
    }
}

final class TouchView: UIView {
    weak var state: KeyboardState?
    var keys: [KeyGeometry] = []

    /// Fingers land a little below where people aim, so read each touch as
    /// slightly higher than it physically is.
    private static let aimCorrection: CGFloat = -3
    /// Points of sideways slide per character on the space-bar trackpad.
    private static let trackpadStep: CGFloat = 9
    /// How far a finger must slide on a kana key to pick another kana.
    private static let flickDistance: CGFloat = 18

    private final class Session {
        let geo: KeyGeometry
        /// Where the finger landed (aim-corrected), for the word decoder.
        let point: CGPoint
        /// Already typed because another finger came down first.
        var committed = false
        var longPressed = false
        /// Space held: sliding moves the cursor. Last x that moved it.
        var trackpadX: CGFloat?
        var holdWork: DispatchWorkItem?
        /// Kana key: index into `flicks` the finger points at now.
        var flick = 0
        init(_ geo: KeyGeometry, at point: CGPoint) {
            self.geo = geo
            self.point = point
        }
    }

    private var sessions: [ObjectIdentifier: Session] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        // See KeyboardViewController: fully clear pixels get no touches.
        backgroundColor = UIColor(white: 0.5, alpha: 0.01)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // SwiftUI wraps this view in its own host views, which default to
    // single-touch; a second finger would be dropped before reaching us.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        var ancestor = superview
        while let v = ancestor {
            v.isMultipleTouchEnabled = true
            ancestor = v.superview
        }
    }

    /// The key under a point; between keys or in a gap, the nearest one.
    private func key(at p: CGPoint) -> KeyGeometry? {
        if let hit = keys.first(where: { $0.local.contains(p) }) { return hit }
        return keys.min { distance($0.local, p) < distance($1.local, p) }
    }

    private func distance(_ rect: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
        return dx * dx + dy * dy
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state else { return }
        for touch in touches {
            let raw = touch.location(in: self)
            let p = CGPoint(x: raw.x, y: raw.y + Self.aimCorrection)
            guard let geo = key(at: p) else {
                continue
            }

            // Rollover: a new finger types any key still held down, so fast
            // overlapping taps all land, in order.
            for other in sessions.values where !other.committed && !other.longPressed {
                guard other.geo.key.action != .backspace else { continue }
                other.holdWork?.cancel()
                other.committed = true
                state.pressedKeys.remove(other.geo.id)
                if !other.geo.key.flicks.isEmpty { state.popup = nil; state.flickGuide = nil }
                state.tap(Self.typed(other), at: other.point)
            }

            let session = Session(geo, at: p)
            sessions[ObjectIdentifier(touch)] = session
            state.keyDown()
            state.pressedKeys.insert(geo.id)

            switch geo.key.action {
            case .backspace:
                state.backspace.down()
            case .space:
                // Like the system keyboard: hold space, then slide to move
                // the cursor. Longer than letters, since space is tapped constantly.
                schedule(session, after: 0.4) { [weak state] in
                    session.longPressed = true
                    session.trackpadX = p.x
                    state?.keyDown()
                }
            case .toNumpad:
                // Hold: the other number layout (numpad or symbols).
                schedule(session, after: 0.4) { [weak state] in
                    session.longPressed = true
                    state?.openNumbers(held: true)
                }
            case .language:
                schedule(session, after: 0.4) { [weak state] in
                    session.longPressed = true
                    state?.showKeyboardMenu(over: geo.kb)
                }
            case .text where !geo.key.flicks.isEmpty:
                // Held without flicking: show where each flick goes.
                schedule(session, after: 0.3) { [weak state] in
                    state?.popup = nil
                    state?.showFlickGuide(geo.key.flicks, over: geo.kb, selected: session.flick, full: true)
                }
            case .text where !geo.key.alternates.isEmpty || !geo.key.actions.isEmpty:
                schedule(session, after: 0.3) { [weak state] in
                    session.longPressed = true
                    state?.showPopup(for: geo.key, over: geo.kb)
                }
            default:
                break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let session = sessions[ObjectIdentifier(touch)] else { continue }
            let p = touch.location(in: self)
            if !session.geo.key.flicks.isEmpty, !session.committed {
                updateFlick(session, to: CGPoint(x: p.x, y: p.y + Self.aimCorrection))
                continue
            }
            guard session.longPressed else { continue }
            if let lastX = session.trackpadX {
                // One character per few points, so small slides are precise.
                let steps = Int((p.x - lastX) / Self.trackpadStep)
                if steps != 0 {
                    session.trackpadX = lastX + CGFloat(steps) * Self.trackpadStep
                    state?.moveCursor(by: steps)
                }
                continue
            }
            // Popup positions are in keyboard space; shift from this view's space.
            state?.movePopupSelection(to: CGPoint(x: p.x + session.geo.kb.minX - session.geo.local.minX,
                                                  y: p.y + session.geo.kb.minY - session.geo.local.minY))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: true)
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        guard let state else { return }
        for touch in touches {
            guard let session = sessions.removeValue(forKey: ObjectIdentifier(touch)) else {
                continue
            }
            session.holdWork?.cancel()
            state.pressedKeys.remove(session.geo.id)

            if session.geo.key.action == .backspace {
                state.backspace.up()
            } else if session.longPressed {
                if cancelled { state.popup = nil } else { state.commitPopup() }
            } else if !session.committed && !cancelled {
                // Typed on release, like the system keyboard, so a long-press
                // can still become a popup choice.
                if !session.geo.key.flicks.isEmpty { state.popup = nil; state.flickGuide = nil }
                state.tap(Self.typed(session), at: session.point)
            } else if !session.geo.key.flicks.isEmpty {
                state.popup = nil
                state.flickGuide = nil
            }
        }
    }

    /// What a key types: for a kana key, the kana the finger flicked to.
    private static func typed(_ session: Session) -> Key {
        var key = session.geo.key
        if !key.flicks.isEmpty, session.flick < key.flicks.count, !key.flicks[session.flick].isEmpty {
            key.action = .text(key.flicks[session.flick])
        }
        return key
    }

    /// Flick direction from where the finger landed: 0 tap, 1 left, 2 up,
    /// 3 right, 4 down. Shows the kana it'll type above the key.
    private func updateFlick(_ session: Session, to p: CGPoint) {
        let dx = p.x - session.point.x, dy = p.y - session.point.y
        let flick: Int
        if hypot(dx, dy) < Self.flickDistance {
            flick = 0
        } else if abs(dx) > abs(dy) {
            flick = dx < 0 ? 1 : 3
        } else {
            flick = dy < 0 ? 2 : 4
        }
        guard flick != session.flick else { return }
        session.flick = flick
        let flicks = session.geo.key.flicks
        // Flicked before the hold: no guide, just the preview.
        if flick != 0 { session.holdWork?.cancel() }
        let full = state?.flickGuide?.full == true
        let valid = flick < flicks.count && !flicks[flick].isEmpty
        if !full && !valid {
            state?.flickGuide = nil
        } else {
            state?.showFlickGuide(flicks, over: session.geo.kb, selected: valid ? flick : 0, full: full)
        }
    }

    private func schedule(_ session: Session, after delay: TimeInterval, _ work: @escaping () -> Void) {
        let item = DispatchWorkItem(block: work)
        session.holdWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
