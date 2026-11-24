import Foundation

/// A short on-device log of keyboard openings, memory and engine loads, kept
/// in the app group. Events are written as they happen, so they survive a
/// crash. Pull it with devicectl to see what led up to one.
enum KeyboardLog {
    private static let key = "keyboardLog"
    private static let maxLines = 300
    private static let stamp: ISO8601DateFormatter = ISO8601DateFormatter()

    static func note(_ event: String) {
        let line = "\(stamp.string(from: Date())) \(event) footprintMB=\(Memory.footprintMB()) availableMB=\(Memory.availableMB())"
        var lines = SharedSettings.defaults.stringArray(forKey: key) ?? []
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        SharedSettings.defaults.set(lines, forKey: key)
        // Flushed now, not later: an abort right after this would otherwise lose it.
        SharedSettings.defaults.synchronize()
    }

    /// Records an uncaught Objective-C exception (its name and reason, such as
    /// the method that was not found) before the process aborts. The crash
    /// report only shows the abort, not the message.
    static func installExceptionHook() {
        NSSetUncaughtExceptionHandler { exception in
            KeyboardLog.note("UNCAUGHT \(exception.name.rawValue): \(exception.reason ?? "no reason")")
        }
    }
}
