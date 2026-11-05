import Foundation
import QuartzCore
import UIKit

/// Diagnostic log (temporary): every touch and every insertion, with
/// millisecond timestamps, to find out why taps go missing. Written to the
/// keyboard's Documents/touch.log and read from the Mac with devicectl.
enum TouchLog {
    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("touch.log")
    private static let queue = DispatchQueue(label: "touchlog")
    private static var pending: [String] = []
    private static let start = CACurrentMediaTime()

    /// Marks a new keyboard session. Appends rather than truncating: the
    /// session worth reading is usually not the latest one.
    static func reset() {
        queue.async {
            if (try? url.checkResourceIsReachable()) != true { try? Data().write(to: url) }
            pending.append("--- keyboard opened \(Date())\n")
            flushLocked()
        }
    }

    static func log(_ event: String) {
        let ms = Int((CACurrentMediaTime() - start) * 1000)
        let line = "\(ms) \(event)\n"
        // Buffered and written off the main thread so logging itself
        // can't cause the stalls we're looking for.
        queue.async {
            pending.append(line)
            // Small batches: if iOS kills the keyboard, at most a few lines are lost.
            guard pending.count >= 4 else { return }
            flushLocked()
        }
    }

    static func flush() { queue.async { flushLocked() } }

    private static func flushLocked() {
        guard !pending.isEmpty, let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(pending.joined().utf8))
        try? handle.close()
        pending.removeAll()
    }
}

extension Key {
    var logLabel: String {
        switch action {
        case .text(let s): return s == " " ? "␣" : s
        case .shift: return "⇧"
        case .backspace: return "⌫"
        case .space: return "space"
        case .returnKey: return "⏎"
        case .toNumpad: return "123"
        case .symbolPage: return "#+="
        case .toLetters: return "ABC"
        case .globe: return "🌐"
        case .language: return "lang"
        case .emoji: return "emoji"
        case .cursor(let n): return n < 0 ? "←" : "→"
        case .kanaModifier: return "゛゜"
        }
    }
}

/// Watches every touch iOS delivers anywhere in the keyboard, without
/// interfering, and logs which view it was routed to. Comparing these with
/// TouchView's own BEGIN lines shows whether a missing tap never reached the
/// keyboard (iOS) or reached it but went to the wrong view (our layout).
final class TouchSpy: UIGestureRecognizer, UIGestureRecognizerDelegate {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            let p = touch.location(in: view)
            let hit = touch.view.map { String(describing: type(of: $0)) } ?? "nil"
            TouchLog.log("ROOT \(Int(p.x)),\(Int(p.y)) view=\(hit) down=\(event.allTouches?.count ?? 0)")
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finishIfIdle(event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finishIfIdle(event) }

    private func finishIfIdle(_ event: UIEvent) {
        // Never recognise: just let go once no finger is down.
        let stillDown = event.allTouches?.contains { $0.phase != .ended && $0.phase != .cancelled } ?? false
        if !stillDown { state = .failed }
    }

    override func reset() { super.reset() }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
