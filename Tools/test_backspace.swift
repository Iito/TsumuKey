// swiftc -O Keyboard/Backspace.swift Tools/test_backspace.swift -o <binary>
import Foundation

// Standalone settings double; the tests set every timing explicitly.
struct DeleteTiming {
    var holdDelay = 0.4
    var charRepeat = 0.06
    var wordRepeat = 0.35
    var multiTapWindow = 0.3
    static func load() -> Self { .init() }
}

@main struct TestBackspace {
    static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func main() {
        for (presses, interval) in [(1, 0.06), (1, 0.15), (3, 0.06), (3, 0.35)] {
            var events: [(word: Bool, interval: TimeInterval?)] = []
            weak var active: Backspace?
            let key = Backspace(
                deleteChar: { events.append((false, active?.repeatInterval)) },
                deleteWord: { events.append((true, active?.repeatInterval)) })
            active = key
            key.timing = DeleteTiming(holdDelay: 0.025, charRepeat: interval,
                                      wordRepeat: interval, multiTapWindow: 0.3)
            for _ in 1..<presses { key.down(); key.up() }
            key.down()
            let beforeHold = events.count
            pump(0.025 + interval * 2.5)
            precondition(events.count > beforeHold && events[beforeHold].interval == nil,
                         "The first hold action must refresh immediately")
            let repeats = events.filter { $0.interval != nil }
            precondition(repeats.count >= 2, "Missing repeat callbacks")
            precondition(repeats.allSatisfy { $0.interval == interval && $0.word == (presses == 3) },
                         "Wrong repeat kind or interval")
            precondition(events.first?.interval == nil, "Initial tap must refresh immediately")
            precondition(key.repeatInterval == nil, "Other keys must not inherit the repeat phase")
            key.up()
            let stopped = events.count
            pump(interval * 1.2)
            precondition(events.count == stopped && key.repeatInterval == nil, "Release must stop repeats")
        }

        var chars = 0, words = 0
        let key = Backspace(deleteChar: { chars += 1 }, deleteWord: { words += 1 })
        key.timing = DeleteTiming(holdDelay: 0.025, charRepeat: 0.01,
                                  wordRepeat: 0.02, multiTapWindow: 0.3)
        // Releasing before the hold deadline also covers touch cancellation.
        for _ in 0..<3 { key.down(); key.up() }
        pump(0.08)
        precondition(chars == 3 && words == 0 && key.repeatInterval == nil, "Fast taps or cancellation changed")
        // A third-or-later press in a chain holds to repeat whole words.
        key.down()
        pump(0.08)
        key.up()
        precondition(words >= 2, "Chained repeating word delete stopped working")
        pump(0.35)
        key.down(); key.up()
        let beforeWord = words
        key.down()
        pump(0.08)
        key.up()
        let once = words
        pump(0.08)
        precondition(once == beforeWord + 1 && words == once && key.repeatInterval == nil,
                     "A second-press hold must delete exactly one word without repeating")
        var orphanCalls = 0
        var owner: Backspace? = Backspace(deleteChar: { orphanCalls += 1 }, deleteWord: {})
        weak var released: Backspace?
        released = owner
        owner?.timing = DeleteTiming(holdDelay: 0.025, charRepeat: 0.01,
                                     wordRepeat: 0.02, multiTapWindow: 0.3)
        owner?.down()
        pump(0.08)
        let beforeRelease = orphanCalls
        precondition(beforeRelease >= 3, "Owner-release check requires an active repeat timer")
        owner = nil
        precondition(released == nil, "The repeat timer must not retain its owner")
        pump(0.08)
        precondition(orphanCalls == beforeRelease, "A timer without an owner must stop calling back")
        print("PASS fast/slow character and word repeats, callback scope, release, cancellation, tap chains and owner deallocation")
    }
}
