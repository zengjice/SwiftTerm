import Testing
@testable import SwiftTerm

@Suite("Explicit Shift key sequences")
struct ShiftKeySequenceTests {
    @Test("Each chord is one modified key, without an appended Return")
    func sequences() {
        let chords: [([UInt8], String)] = [
            (EscapeSequences.moveLeftShift, "\u{1b}[1;2D"),
            (EscapeSequences.moveRightShift, "\u{1b}[1;2C"),
            (EscapeSequences.moveUpShift, "\u{1b}[1;2A"),
            (EscapeSequences.moveDownShift, "\u{1b}[1;2B"),
            (EscapeSequences.cmdBackTab, "\u{1b}[Z"),
            (EscapeSequences.cmdShiftRet, "\u{1b}[13;2u")
        ]
        for (bytes, expected) in chords {
            #expect(bytes == Array(expected.utf8))
            #expect(!bytes.contains(13))
            #expect(!bytes.contains(10))
        }
    }
}
