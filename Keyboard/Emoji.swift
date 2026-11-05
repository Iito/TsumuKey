import Foundation

enum EmojiData {
    /// Emoji the system font can draw on iOS 17+ (Unicode 15.0 and older),
    /// roughly grouped: faces, people, nature/objects, travel, symbols.
    static let all: [String] = {
        // Common emoji whose default style is text, so the scan below skips them.
        let extras = ["❤️", "☺️", "✌️", "☝️", "✍️", "☀️", "☁️", "❄️", "✈️", "☕️", "⚽️", "✔️", "✨"]
        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F, 0x1F910...0x1F9FF, 0x1F440...0x1F4FF, 0x1F300...0x1F43F,
            0x1F500...0x1F5FF, 0x1F680...0x1F6FF, 0x1FA70...0x1FAFF, 0x2600...0x27BF, 0x2B00...0x2BFF,
        ]
        var seen = Set(extras)
        var result = extras
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value),
                      scalar.properties.isEmojiPresentation,
                      let age = scalar.properties.age,
                      age.major < 15 || (age.major == 15 && age.minor == 0) else { continue }
                let emoji = String(scalar)
                if seen.insert(emoji).inserted { result.append(emoji) }
            }
        }
        return result
    }()
}
