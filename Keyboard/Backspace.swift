import Foundation

/// The delete key's gestures:
/// - tap: one character (every tap, however fast)
/// - hold: characters, repeating
/// - tap, then hold: the previous word, once
/// - double tap, then hold: word after word, repeating
final class Backspace {
    var timing = DeleteTiming.load()

    private let deleteChar: () -> Void
    private let deleteWord: () -> Void

    private var pressCount = 0
    private var lastRelease = Date.distantPast
    private var holdFired = false
    private var holdWork: DispatchWorkItem?
    private var repeatTimer: Timer?

    init(deleteChar: @escaping () -> Void, deleteWord: @escaping () -> Void) {
        self.deleteChar = deleteChar
        self.deleteWord = deleteWord
    }

    func down() {
        let chained = Date().timeIntervalSince(lastRelease) < timing.multiTapWindow
        pressCount = chained ? pressCount + 1 : 1
        holdFired = false

        // The first press deletes right away so single taps feel instant.
        // Later presses in a chain wait for release: they might turn into a
        // word delete, and deleting a character first would eat one too many.
        if pressCount == 1 { deleteChar() }

        let work = DispatchWorkItem { [weak self] in self?.holdStarted() }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.holdDelay, execute: work)
    }

    func up() {
        holdWork?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        if !holdFired && pressCount >= 2 { deleteChar() }
        // A hold ends the chain, so the next press starts fresh.
        lastRelease = holdFired ? .distantPast : Date()
    }

    private func holdStarted() {
        holdFired = true
        switch pressCount {
        case 1:
            deleteChar()
            startRepeating(every: timing.charRepeat, deleteChar)
        case 2:
            deleteWord()
        default:
            deleteWord()
            startRepeating(every: timing.wordRepeat, deleteWord)
        }
    }

    private func startRepeating(every interval: TimeInterval, _ action: @escaping () -> Void) {
        repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in action() }
    }
}
