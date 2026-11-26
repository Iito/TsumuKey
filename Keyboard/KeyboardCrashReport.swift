import Darwin
import Foundation

/// Saves a crash report for the keyboard into the app group's CrashReports
/// folder, so it can be pulled off the phone after a crash.
///
/// - Uncaught Objective-C exceptions and fatal signals (abort, traps, bad
///   memory access) are written at the moment they happen.
/// - A kill by iOS, such as for memory, sends no signal the keyboard can see.
///   So each time the keyboard appears it writes an "open" marker, and clears
///   it when it goes away. A marker still there on the next start means the
///   previous run died while open; the report says so.
enum KeyboardCrashReport {
    private static let fm = FileManager.default
    private static var checked = false
    /// Read by the signal handler, so it is prepared up front: the handler must not allocate.
    private static var signalPath: UnsafeMutablePointer<CChar>?

    private static var folder: URL? {
        fm.containerURL(forSecurityApplicationGroupIdentifier: SharedSettings.appGroup)?
            .appendingPathComponent("CrashReports", isDirectory: true)
    }
    private static func file(_ name: String) -> URL? { folder?.appendingPathComponent(name) }

    /// Once per process: reports the previous run if it died while open, then arms the signal handlers.
    static func checkPrevious() {
        guard !checked, let folder else { return }
        checked = true
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let marker = file("open.marker"), fm.fileExists(atPath: marker.path) {
            writeReport(in: folder)
        }
        signalPath = strdup(file("signal.bin")?.path ?? "/dev/null")
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGTRAP, SIGFPE] {
            signal(sig, handleSignal)
        }
    }

    /// The keyboard is on screen: a marker that a crash will leave behind.
    static func opened() {
        guard let marker = file("open.marker") else { return }
        let text = "\(Date()) build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")"
        try? text.write(to: marker, atomically: true, encoding: .utf8)
    }

    /// The keyboard went away normally.
    static func closed() {
        if let marker = file("open.marker") { try? fm.removeItem(at: marker) }
    }

    /// Called from the uncaught-exception hook, outside any signal.
    static func recordException(_ exception: NSException) {
        let text = """
        \(exception.name.rawValue): \(exception.reason ?? "no reason")
        \(exception.callStackSymbols.joined(separator: "\n"))
        """
        if let url = file("exception.txt") { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }

    private static let handleSignal: @convention(c) (Int32) -> Void = { sig in
        // Only open, write and close here: they are safe inside a signal handler.
        if let path = signalPath {
            let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd >= 0 {
                var number = sig
                _ = write(fd, &number, MemoryLayout<Int32>.size)
                close(fd)
            }
        }
        signal(sig, SIG_DFL)
        raise(sig)
    }

    /// Builds the report from whatever the last run left behind, then clears those files.
    private static func writeReport(in folder: URL) {
        let names = [SIGABRT: "SIGABRT", SIGILL: "SIGILL", SIGSEGV: "SIGSEGV",
                     SIGBUS: "SIGBUS", SIGTRAP: "SIGTRAP", SIGFPE: "SIGFPE"]
        var reason = "no signal recorded: iOS ended the keyboard (for example, for memory), or it was force-quit"
        if let url = file("exception.txt"), let text = try? String(contentsOf: url, encoding: .utf8) {
            reason = "uncaught exception:\n" + text
        } else if let url = file("signal.bin"), let data = try? Data(contentsOf: url), data.count == 4 {
            let sig = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
            reason = "signal \(names[sig] ?? String(sig)) (\(sig))"
        }
        let marker = file("open.marker").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "unknown"
        let recent = KeyboardLog.recent(80).joined(separator: "\n")
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let report = """
        TsumuKey keyboard crash report, written \(Date())
        Last open: \(marker)

        Reason: \(reason)

        Last keyboard log lines:
        \(recent)
        """
        try? report.write(to: folder.appendingPathComponent("crash-\(stamp).txt"), atomically: true, encoding: .utf8)
        for name in ["open.marker", "exception.txt", "signal.bin"] {
            if let url = file(name) { try? fm.removeItem(at: url) }
        }
        pruneOld(in: folder)
    }

    /// Keeps the newest 20 reports.
    private static func pruneOld(in folder: URL) {
        let reports = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix("crash-") }.sorted()
        for name in reports.dropLast(20) { try? fm.removeItem(at: folder.appendingPathComponent(name)) }
    }
}
