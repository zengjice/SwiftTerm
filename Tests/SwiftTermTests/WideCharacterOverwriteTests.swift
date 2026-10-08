import Testing
@testable import SwiftTerm

struct WideCharacterOverwriteTests {
    private let esc = "\u{1b}"

    @Test(arguments: ["中", "😀"], ["", "\u{1b}[31;44;1m", "\u{1b}[7m"])
    func continuationInheritsCharacterAttributes(character: String, sgr: String) {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 12, rows: 3)
        terminal.feed(text: sgr + character)
        let line = terminal.buffer.lines[0]
        #expect(line[0].width == 2)
        #expect(line[1].width == 0)
        #expect(line[1].code == 0)
        #expect(line[1].attribute == line[0].attribute)
    }

    @Test(arguments: [" ", "X", "λ"], [0, 1])
    func narrowOverwriteClearsTheOtherHalf(replacement: String, column: Int) {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 12, rows: 3)
        terminal.feed(text: "\(esc)[31;44m中文ABC\(esc)[0m\(esc)[1;\(column + 1)H" + replacement)
        let line = terminal.buffer.lines[0]
        let cleared = line[1 - column]
        #expect(line[column].width == 1)
        #expect(terminal.getCharacter(for: line[column]) == Character(replacement))
        #expect(cleared.width == 1)
        #expect(cleared.code == 0)
        #expect(cleared.attribute == CharData.defaultAttr)
        #expect(terminal.getCharacter(for: line[2]) == "文")
        #expect(line[3].width == 0)
        #expect(terminal.buffer.x == column + 1)
    }

    @Test(arguments: [1, 2, 3, 4])
    func asciiRunCleansOnlyItsBoundaries(length: Int) {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 12, rows: 3)
        terminal.feed(text: "中文测试Z\(esc)[1;2H" + String(repeating: "x", count: length))
        let line = terminal.buffer.lines[0]
        #expect(line[0].code == 0)
        #expect(line[0].width == 1)
        for column in 1...length {
            #expect(terminal.getCharacter(for: line[column]) == "x")
            #expect(line[column].width == 1)
        }
        let next = length + 1
        if next % 2 == 1 {
            #expect(line[next].code == 0)
            #expect(line[next].width == 1)
        } else {
            #expect(line[next].width == 2)
        }
        #expect(terminal.getCharacter(for: line[8]) == "Z")
    }

    @Test func wideOverwriteClearsBothIntersectedCharacters() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 12, rows: 3)
        terminal.feed(text: "中文ABC\(esc)[1;2H\(esc)[32;45m国")
        let line = terminal.buffer.lines[0]
        #expect(line[0].code == 0 && line[0].width == 1)
        #expect(terminal.getCharacter(for: line[1]) == "国")
        #expect(line[1].width == 2)
        #expect(line[2].code == 0 && line[2].width == 0)
        #expect(line[2].attribute == line[1].attribute)
        #expect(line[3].code == 0 && line[3].width == 1)
        #expect(line[0].attribute.bg == .ansi256(code: 5))
        #expect(line[3].attribute.bg == .ansi256(code: 5))
        #expect(line[0].attribute.style == .none)
        #expect(terminal.getCharacter(for: line[4]) == "A")
    }

    @Test func overwriteAtRightEdgeAndWrapKeepsAdjacentLinesIntact() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 6, rows: 3)
        terminal.feed(text: "abcd中\(esc)[1;6HXyz")
        TerminalTestHarness.assertLineText(terminal.buffer, terminal: terminal, row: 0, equals: "abcd X")
        TerminalTestHarness.assertLineText(terminal.buffer, terminal: terminal, row: 1, equals: "yz")
        #expect(terminal.buffer.lines[0][4].width == 1)
        #expect(terminal.buffer.lines[1][0].width == 1)
    }

    @Test func insertInsideWideCharacterDoesNotLeaveSplitGlyph() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 8, rows: 3)
        terminal.feed(text: "中文AB\(esc)[1;2H\(esc)[4hX\(esc)[4l")
        TerminalTestHarness.assertLineText(terminal.buffer, terminal: terminal, row: 0, equals: " X 文AB")
        #expect(terminal.buffer.lines[0][0].width == 1)
        #expect(terminal.buffer.lines[0][2].width == 1)
    }

    @Test func insertBeforeWideCharacterPreservesShiftedGlyph() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 8, rows: 3)
        terminal.feed(text: "中文AB\(esc)[1;1H\(esc)[4hX\(esc)[4l")
        TerminalTestHarness.assertLineText(terminal.buffer, terminal: terminal, row: 0, equals: "X中文AB")
        #expect(terminal.buffer.lines[0][1].width == 2)
        #expect(terminal.buffer.lines[0][2].width == 0)
    }

    @Test func insertTrimsWideCharacterAtRightMargin() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 8, rows: 3)
        terminal.feed(text: "abcd中文\(esc)[?69h\(esc)[1;6s\(esc)[1;1H\(esc)[4hX\(esc)[4l")
        let line = terminal.buffer.lines[0]
        #expect(terminal.buffer.marginRight == 5)
        #expect(line[5].width == 1 && line[5].code == 0)
        #expect(line[5].attribute == CharData.defaultAttr)
        #expect(terminal.getCharacter(for: line[6]) == "文")
        #expect(line[6].width == 2 && line[7].width == 0)
    }

    @Test(arguments: [false, true])
    func sparseTableUpdatesAreIndependentOfFeedBoundaries(bytewise: Bool) {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 4)
        let initial = "\(esc)[?1049h\(esc)[?25l\(esc)[1;1H中文测试 | A\(esc)[2;1H😀示例   | B"
        let update = "\(esc)[1;1H \(esc)[1;3H \(esc)[1;5H \(esc)[1;7H \(esc)[2;1H \(esc)[2;3H \(esc)[2;5H "
        let bytes = Array((initial + update).utf8)
        if bytewise {
            for byte in bytes { terminal.feed(buffer: [byte][...]) }
        } else {
            terminal.feed(buffer: bytes[...])
        }
        TerminalTestHarness.assertLineText(terminal.buffer, terminal: terminal, row: 0, equals: "         | A")
        TerminalTestHarness.assertLineText(terminal.buffer, terminal: terminal, row: 1, equals: "         | B")
        for row in 0...1 {
            for column in 0..<8 {
                let cell = terminal.buffer.lines[row][column]
                #expect(cell.width == 1)
                #expect(cell.attribute == CharData.defaultAttr)
            }
        }
    }
}
