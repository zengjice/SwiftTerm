import Testing
@testable import SwiftTerm

struct SelectionLifecycleTests {
    @Test(arguments: [47, 1047, 1049])
    func switchingBuffersClearsSelection(mode: Int) {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        let selection = SelectionService(terminal: terminal)
        terminal.feed(text: "normal")
        selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 6, row: 0))

        terminal.feed(text: "\u{1b}[?\(mode)h")
        #expect(!selection.active)
        terminal.feed(text: "alternate")
        selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 6, row: 0))

        // Reasserting the already active buffer is not a content replacement.
        terminal.feed(text: "\u{1b}[?\(mode)h")
        #expect(selection.active)
        terminal.feed(text: "\u{1b}[?\(mode)l")
        #expect(!selection.active)
    }

    @Test(arguments: [false, true])
    func fullResetClearsSelection(programmatic: Bool) {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        let selection = SelectionService(terminal: terminal)
        terminal.feed(text: "old text")
        selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 3, row: 0))

        if programmatic { terminal.resetToInitialState() }
        else { terminal.feed(text: "\u{1b}c") }

        #expect(!selection.active)
    }

    @Test
    func onlyActualGridChangesClearSelection() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        let selection = SelectionService(terminal: terminal)
        terminal.feed(text: "old text")
        selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 3, row: 0))

        terminal.resize(cols: terminal.cols, rows: terminal.rows)
        #expect(selection.active)
        terminal.resize(cols: terminal.cols + 1, rows: terminal.rows)
        #expect(!selection.active)
    }
}
