// swiftc -O Keyboard/Lexicon.swift Tools/test_lexicon_walk.swift -o <binary>
// Run with the European and Korean lexicon paths as arguments.
import Foundation

@main struct TestLexiconWalk {
    static func main() throws {
        precondition(CommandLine.arguments.count > 1, "Pass one or more lexicon paths")
        for path in CommandLine.arguments.dropFirst() {
            guard let lexicon = Lexicon(url: URL(fileURLWithPath: path)) else { fatalError("Cannot load \(path)") }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let count = data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
            var all: [(index: Int, bytes: [UInt8])] = []
            for index in 0..<count {
                let bytes = Array(lexicon.key(at: index).utf8)
                if all.last?.bytes != bytes { all.append((index, bytes)) }
            }
            precondition(!all.isEmpty, "Empty lexicon: \(path)")
            func check(_ accepts: (Int, UInt8) -> Bool) {
                let expected = all.filter { entry in
                    entry.bytes.enumerated().allSatisfy { accepts($0.offset, $0.element) }
                }.map(\.index)
                var found: [Int] = []
                lexicon.walk(step: accepts, found: { length, index in
                    precondition(length == lexicon.key(at: index).utf8.count, "Incorrect key length")
                    found.append(index)
                })
                precondition(found == expected, "Pruned walk differs from full scan: \(path)")
            }
            check { _, _ in true }
            check { _, _ in false }
            for limit in [1, 3, 8] { check { depth, _ in depth < limit } }
            for first in [UInt8(ascii: "a"), UInt8(ascii: "z")] {
                check { depth, byte in depth != 0 || byte == first }
            }
            var seed: UInt64 = 812739
            for _ in 0..<24 {
                var masks: [UInt32] = []
                for _ in 0..<12 {
                    seed = seed &* 6364136223846793005 &+ 1
                    masks.append(UInt32(truncatingIfNeeded: seed >> 16) & 0x03ff_ffff)
                }
                func accepts(_ depth: Int, _ byte: UInt8) -> Bool {
                    guard depth < masks.count, byte >= 97, byte <= 122 else { return false }
                    return masks[depth] & (UInt32(1) << (byte - 97)) != 0
                }
                check(accepts)
            }
            print("PASS \(path): \(all.count) distinct keys, 31 full-scan comparisons")
        }
    }
}
