import XCTest

/// Types the simulated typist's taps (UITests/Bench/taps-*.json, made by the
/// scratchpad gen.py) on whatever keyboard is active: Gboard or TsumuKey.
/// Same taps, same phone, so the two keyboards' corrections compare directly.
///
/// Geometry comes from the runner's environment (xcodebuild passes
/// TEST_RUNNER_<NAME> through as <NAME>):
///   BENCH_GEOM  "left,unit,row0Y,rowPitch,spaceX,spaceY" in points
///   BENCH_LEVEL careful | fast       BENCH_LIMIT  sentences to run (default all)
/// Output lines start with "BENCHOUT|" and are read back from the xcodebuild log.
final class TypingBench: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-autofocus"]
        // BENCH_MODEL gemma|dense|moe picks the correction model; BENCH_LAYOUT the letter layout.
        let env = ProcessInfo.processInfo.environment
        if let m = env["BENCH_MODEL"] { app.launchArguments += ["-model", m] }
        if let l = env["BENCH_LAYOUT"] { app.launchArguments += ["-layout", l] }
        // BENCH_ALPHABET korean|japanese|none picks the other alphabet.
        if let a = env["BENCH_ALPHABET"] { app.launchArguments += ["-alphabet", a] }
        // BENCH_NUMBERROW 1|0 turns the number row on or off (it stays that way).
        if let n = env["BENCH_NUMBERROW"] { app.launchArguments += ["-numberRow", n] }
        app.launch()
        sleep(2)
    }

    private var field: XCUIElement { app.textFields["testField"] }
    private var text: String {
        let value = (field.value as? String) ?? ""
        return value == field.placeholderValue ? "" : value
    }

    private func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    /// Locks the phone after a bench run (the side button; XCUIDevice has no
    /// public call for it).
    func testLockPhone() {
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
    }

    /// Screenshot of the keyboard for measuring key positions.
    func testCalibrate() {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "keyboard"
        shot.lifetime = .keepAlways
        add(shot)
        print("BENCHINFO|window \(app.windows.firstMatch.frame) keyboards \(app.keyboards.count)")
        for key in app.keyboards.keys.allElementsBoundByIndex.prefix(40) {
            print("BENCHINFO|key \(key.label) \(key.frame)")
        }
    }

    func testType() throws {
        let env = ProcessInfo.processInfo.environment
        let g = (env["BENCH_GEOM"] ?? "").split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
        guard g.count == 6 else { XCTFail("BENCH_GEOM missing"); return }
        let (left, unit, row0Y, pitch, spaceX, spaceY) = (g[0], g[1], g[2], g[3], g[4], g[5])
        let level = env["BENCH_LEVEL"] ?? "careful"
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "taps-\(level)", withExtension: "json"))
        let sentences = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let limit = Int(env["BENCH_LIMIT"] ?? "") ?? sentences.count
        let start = Int(env["BENCH_START"] ?? "") ?? 0
        let gap = Double(env["BENCH_GAP"] ?? "") ?? 0.15

        // BENCH_LANGKEY "x,y": tapped once before typing (⚙︎: to the Hangul
        // keyboard) and once after (back to ABC).
        let langKey = (env["BENCH_LANGKEY"] ?? "").split(separator: ",").compactMap { Double($0) }
        var langKeyTapped = false
        defer {
            if langKeyTapped { at(CGFloat(langKey[0]), CGFloat(langKey[1])).tap(); sleep(1) }
        }

        for (i, s) in sentences.enumerated() where i >= start && i < start + limit {
            app.buttons["clearField"].tap()
            field.tap()
            usleep(400_000)
            if langKey.count == 2 && !langKeyTapped {
                at(CGFloat(langKey[0]), CGFloat(langKey[1])).tap()
                langKeyTapped = true
                sleep(2)  // the Korean word list loads
            }
            // One synthesized tap at a time on a fixed beat (BENCH_GAP, default
            // 0.15 s, ~70 wpm). A whole sentence in one event record played
            // back at the wrong pace and lost touches.
            // BENCH_BATCH=1 plays each word as one event record (no round
            // trip per tap); otherwise one tap per call.
            let batch = env["BENCH_BATCH"] == "1"
            var points: [NSValue] = [], times: [NSNumber] = []
            func tap(_ x: CGFloat, _ y: CGFloat) throws {
                if batch {
                    points.append(NSValue(cgPoint: CGPoint(x: x, y: y)))
                    times.append(NSNumber(value: Double(times.count) * gap))
                    return
                }
                let started = Date()
                try FastTaps.tapPoints([NSValue(cgPoint: CGPoint(x: x, y: y))], atTimes: [0], hold: 0.05)
                let rest = gap - Date().timeIntervalSince(started)
                if rest > 0 { usleep(UInt32(rest * 1_000_000)) }
            }
            for w in s["words"] as! [[String: Any]] {
                for t in w["taps"] as! [[Any]] {
                    // Key units -> points: x from the left edge of the key grid,
                    // y from the top of the first letter row. Kept inside the
                    // letter rows: above them Gboard has its search button and
                    // TsumuKey its number row, so a stray tap there isn't a
                    // like-for-like slip.
                    let y = min(max(t[2] as! Double, 0.05), 2.95)
                    try tap(left + CGFloat(t[1] as! Double) * unit, row0Y + CGFloat(y) * pitch)
                }
                try tap(spaceX, spaceY)
                if batch {
                    try FastTaps.tapPoints(points, atTimes: times, hold: 0.05)
                    points = []; times = []
                }
            }
            usleep(600_000) // corrections land on space, sometimes a beat later
            print("BENCHOUT|\(i)|\(text)")
        }
    }

    /// Screenshots of the 123 layouts: hold 123 (symbols by default), then
    /// the "#+=" page. SHOT_123 and SHOT_PAGE are "x,y" in points.
    func testSymbolsShots() throws {
        let env = ProcessInfo.processInfo.environment
        func point(_ key: String) -> (CGFloat, CGFloat)? {
            let v = (env[key] ?? "").split(separator: ",").compactMap { Double($0) }
            return v.count == 2 ? (CGFloat(v[0]), CGFloat(v[1])) : nil
        }
        field.tap()
        sleep(1)
        if let (x, y) = point("SHOT_123") { at(x, y).press(forDuration: 0.8) }
        sleep(1)
        shot("symbols")
        if let (x, y) = point("SHOT_PAGE") { at(x, y).tap() }
        sleep(1)
        shot("symbols2")
    }

    /// For each ROMAJI word (comma separated): relaunches the app with the
    /// word pre-filled, opens the keyboard and screenshots the bar. With CHIP
    /// "x,y" it then taps there (the Japanese chip) and prints
    /// "ROMAJIOUT|word|field text".
    func testRomaji() throws {
        let env = ProcessInfo.processInfo.environment
        let chip = (env["CHIP"] ?? "").split(separator: ",").compactMap { Double($0) }
        for word in (env["ROMAJI"] ?? "watashi").split(separator: ",") {
            app.terminate()
            app.launchArguments = ["-autofocus", "-prefill", String(word)]
            app.launch()
            sleep(3)
            shot(String(word))
            if chip.count == 2 {
                at(chip[0], chip[1]).tap()
                sleep(1)
                print("ROMAJIOUT|\(word)|\(text)")
            }
        }
    }

    /// Screenshot of each layout in LAYOUTS (comma separated raw names);
    /// the last one is left active.
    func testLayouts() throws {
        for name in (ProcessInfo.processInfo.environment["LAYOUTS"] ?? "qwerty").split(separator: ",") {
            app.terminate()
            app.launchArguments = ["-autofocus", "-layout", String(name)]
            app.launch()
            sleep(3)
            shot(String(name))
        }
    }

    /// Feature demo for a screen recording (16 Pro Max, QWERTY, number row on):
    /// typing with autocorrect and key popups, punctuation sticking to the word,
    /// the Japanese chip, the 123 key, then the other layouts.
    func testDemo() throws {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        let offset: [CGFloat] = [0, 0.5, 1.5]
        func key(_ c: Character) -> (CGFloat, CGFloat)? {
            if c == " " { return (230, 856) }
            for (r, row) in rows.enumerated() {
                if let i = row.firstIndex(of: c) {
                    let col = CGFloat(row.distance(from: row.startIndex, to: i))
                    return (3 + (offset[r] + col + 0.5) * 43.4, 706 + CGFloat(r) * 50)
                }
            }
            return nil
        }
        func type(_ s: String) {
            for c in s { if let (x, y) = key(c) { at(x, y).tap() } }
        }
        app.terminate()
        app.launchArguments = ["-autofocus", "-layout", "qwerty", "-prefill", ""]
        app.launch()
        sleep(2)
        type("hello wrold ")
        sleep(1)
        at(343, 856).tap()   // "." right after "world " takes the space away
        sleep(1)
        type(" watashihanihongowohanasu")
        sleep(1)
        at(77, 610).tap()      // Japanese chip, first in the bar
        sleep(2)
        at(30, 855.5).tap()    // 123: numpad
        sleep(2)
        at(30, 855.5).tap()    // ABC, same spot
        sleep(1)
        at(30, 855.5).press(forDuration: 0.8)
        sleep(2)
        for name in ["colemak", "qwertz", "dvorak", "qwerty"] {
            app.terminate()
            app.launchArguments = ["-autofocus", "-layout", name]
            app.launch()
            sleep(3)
        }
        // Xcode only keeps the screen recording of failed tests.
        if ProcessInfo.processInfo.environment["KEEPVIDEO"] != nil { XCTFail("keep the recording") }
    }

    /// Holds the settings key (menu shows in the screen recording), then for
    /// each LANGCASES entry "langs|text" relaunches with those prediction
    /// languages and that text, and screenshots the bar. Ends on en,fr.
    func testMenuAndLanguages() throws {
        at(79, 856).press(forDuration: 2.5)
        sleep(1)
        // Long-press a left-edge letter and one near the right edge with many options (QWERTY a, o; number row on).
        at(24.7, 756).press(forDuration: 2.0)
        sleep(1)
        at(371.6, 706).press(forDuration: 2.0)   // O: 9 options, opens leftward
        sleep(1)
        shot("longpress")
        let cases = (ProcessInfo.processInfo.environment["LANGCASES"] ?? "").split(separator: ";")
        for (i, c) in cases.enumerated() {
            let parts = c.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            app.terminate()
            app.launchArguments = ["-autofocus", "-languages", parts[0], "-prefill", parts[1]]
            app.launch()
            sleep(4)
            shot("lang\(i)")
        }
        app.terminate()
        app.launchArguments = ["-languages", "en,fr"]
        app.launch()
        sleep(2)
        if ProcessInfo.processInfo.environment["KEEPVIDEO"] != nil { XCTFail("keep the recording") }
    }

    /// README screenshots: the keyboard with and without the number row,
    /// with and without corner symbols. Ends with both on (the defaults).
    func testRowAndHintShots() throws {
        for (row, hints) in [(1, 1), (0, 1), (1, 0), (0, 0)] {
            app.terminate()
            app.launchArguments = ["-autofocus", "-numberRow", "\(row)", "-symbolHints", "\(hints)"]
            app.launch()
            sleep(3)
            shot("row\(row)-hints\(hints)")
        }
        app.terminate()
        app.launchArguments = ["-numberRow", "1", "-symbolHints", "1"]
        app.launch()
        sleep(2)
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
