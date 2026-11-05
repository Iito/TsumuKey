import XCTest

/// Drives the TsumuKey keyboard by screen position. Keyboard extensions are
/// invisible to XCUITest's element tree, so keys are found from the layout grid.
/// Geometry is for iPhone 18 Pro (402pt wide), QWERTY, keyboard enabled as the
/// default input mode.
final class KeyboardTests: XCTestCase {
    private var app: XCUIApplication!

    // Measured from a screenshot: center of the number row, and row pitch.
    private let firstRowY: CGFloat = 601.3
    private let rowHeight: CGFloat = 44 // matches -rowHeight 44 below
    private let unit: CGFloat = (402 - 6) / 10

    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-autofocus", "-chainWindow", "2.0", "-rowHeight", "44"]
        app.launch()
        sleep(2)
    }

    private var field: XCUIElement { app.textFields["testField"] }
    private var text: String {
        // An empty field reports its placeholder as the value.
        let value = (field.value as? String) ?? ""
        return value == field.placeholderValue ? "" : value
    }

    private func point(x: CGFloat, row: Int) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: firstRowY + CGFloat(row) * rowHeight))
    }

    private func letterKey(_ c: Character) -> XCUICoordinate {
        for (r, row) in rows.enumerated() {
            if let i = row.firstIndex(of: c) {
                let col = CGFloat(row.distance(from: row.startIndex, to: i))
                let indent: CGFloat = [0, 0.5, 1.5][r]
                return point(x: 3 + (indent + col + 0.5) * unit, row: r + 1)
            }
        }
        fatalError("no key for \(c)")
    }

    private var space: XCUICoordinate { point(x: 211, row: 4) }
    private var backspace: XCUICoordinate { point(x: 3 + 9.25 * unit, row: 3) }

    private func type(_ s: String) {
        for c in s { (c == " " ? space : letterKey(c)).tap() }
    }

    private func screenshot(_ name: String) {
        // Simulator tests run on the Mac, so they can also drop a PNG on its disk.
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: NSHomeDirectory().components(separatedBy: "/Library/")[0] + "/bk-shots/\(name).png"))
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testTypingAndAutoCapital() {
        type("hello world")
        XCTAssertEqual(text, "Hello world")
        screenshot("typed")
    }

    func testLongPressAccent() {
        type("caf")
        // "e" popup: [hint "|", é, è, ...]; cells are 34pt, popup clamped to x=4.
        letterKey("e").press(forDuration: 0.6, thenDragTo: point(x: 4 + 4 + 34 + 17, row: 1))
        XCTAssertEqual(text, "Café")
    }

    func testDeleteGestures() {
        type("one two three four five")
        sleep(3) // let any chain from typing expire

        backspace.tap()
        XCTAssertEqual(text, "One two three four fiv", "tap: one character")
        sleep(3)

        // Tap then hold: the tap eats "v", the hold eats the rest of the word.
        backspace.tap()
        backspace.press(forDuration: 1.0)
        XCTAssertEqual(text, "One two three four ", "tap then hold: one word")
        sleep(3)

        // Double tap then hold: word after word.
        backspace.tap()
        backspace.tap()
        backspace.press(forDuration: 1.3)
        print("AFTER_WORD_REPEAT: '\(text)'")
        XCTAssertTrue(text.count < "One two three".count, "double tap then hold: several words")
        sleep(3)

        // Plain hold: characters, repeating.
        let before = text.count
        backspace.press(forDuration: 1.0)
        print("AFTER_CHAR_HOLD: '\(text)' (was \(before) chars)")
        XCTAssertTrue(text.count < before - 3 || text.isEmpty, "hold: repeating characters")
    }

    func testEmojiPanel() {
        type("hi ")
        point(x: 3 + 1.75 * unit, row: 4).tap() // emoji key, right of "123"
        sleep(1)
        screenshot("emoji")
        // First emoji in the grid.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 30, dy: firstRowY)).tap()
        XCTAssertEqual(text.count, "Hi ".count + 1, "one emoji inserted")
        point(x: 40, row: 4).tap() // ABC
        sleep(1)
        screenshot("letters")
    }
}
