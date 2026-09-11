#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

@MainActor
@Suite("Mac selection survives terminal output", .serialized)
struct MacSelectionLifecycleTests {
    @Test(arguments: [false, true], [false, true])
    func outputPreservesSelection(reporting: Bool, bytes: Bool) {
        let view = makeView()
        view.allowMouseReporting = reporting
        selectWord(in: view)

        // Neither cursor/SGR updates nor a linefeed elsewhere changes this word.
        let output = "\u{1b}[?25h\u{1b}[4;1H\u{1b}[32mstatus update\u{1b}[0m\r\n"
        if bytes {
            // Exercise the real streaming API, including split escape sequences.
            for byte in output.utf8 { view.feed(byteArray: [byte][...]) }
        } else {
            view.feed(text: output)
        }

        #expect(view.getSelection() == "alpha")
        #expect(view.terminal.getLine(row: 3)?.translateToString(trimRight: true) == "status update")
        #expect(view.allowMouseReporting == reporting)
        #expect(view.terminal.mouseMode == .off)
    }

    @Test(arguments: [false, true])
    func linefeedCallbackDoesNotClearSelection(reporting: Bool) {
        let view = makeView()
        view.allowMouseReporting = reporting
        selectWord(in: view)

        // Isolate the second cancellation path from feedPrepare().
        view.terminal.feed(text: "\u{1b}[4;1H\r\n")

        #expect(view.getSelection() == "alpha")
    }

    @Test
    func layoutWithoutGridChangePreservesSelection() {
        let view = makeView()
        selectWord(in: view)
        view.resizeSubviews(withOldSize: view.frame.size)
        view.setFrameOrigin(CGPoint(x: 10, y: 20))

        #expect(view.getSelection() == "alpha")
    }

    @Test
    func realGridChangeClearsSelection() {
        let view = makeView()
        selectWord(in: view)
        view.setFrameSize(CGSize(width: view.frame.width + 50, height: view.frame.height))

        #expect(!view.selectionActive)
    }

    @Test(arguments: [1, 2, 3])
    func newClicksStillReplaceSelection(clickCount: Int) throws {
        let view = makeView()
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        defer { withExtendedLifetime(window) { } }
        selectWord(in: view)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: view.cellDimension.width * 7, y: view.frame.height - view.cellDimension.height / 2),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1
        ))
        view.mouseDown(with: event)

        switch clickCount {
        case 1: #expect(!view.selectionActive)
        case 2: #expect(view.getSelection() == "bravo")
        default: #expect(view.getSelection()?.trimmingCharacters(in: .whitespacesAndNewlines) == "alpha bravo charlie")
        }
    }

    @Test
    func keyDownStillClearsSelection() throws {
        let view = makeView()
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        defer { withExtendedLifetime(window) { } }
        selectWord(in: view)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
        view.keyDown(with: event)

        #expect(!view.selectionActive)
    }

    @Test
    func selectionFollowsOutputScrollAndClearsWhenEvicted() {
        let view = makeView()
        view.feed(text: "\u{1b}[2;1Hsecond\u{1b}[3;1Hthird\u{1b}[4;1Hfourth")
        view.selection.setSelection(start: Position(col: 0, row: 2), end: Position(col: 5, row: 2))

        view.feed(text: "\u{1b}[2;4r\u{1b}[4;1H\r\n")
        #expect(view.getSelection() == "third")
        #expect(view.selection.start.row == 1)

        view.feed(text: "\r\n")
        #expect(!view.selectionActive)
    }

    @Test(arguments: [false, true])
    func committedTextAndPasteStillClearSelection(isPaste: Bool) {
        let view = makeView()
        selectWord(in: view)
        view.insertText("hello", replacementRange: NSRange(location: NSNotFound, length: 0), isPaste: isPaste)

        #expect(!view.selectionActive)
    }

    @Test
    func applicationMousePressClearsPreviousLocalSelection() throws {
        let view = makeView()
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        defer { withExtendedLifetime(window) { } }
        view.feed(text: "\u{1b}[?1002h\u{1b}[?1006h")
        selectWord(in: view)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: CGPoint(x: 20, y: 20),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        view.mouseDown(with: event)

        #expect(!view.selectionActive)
    }

    private func makeView() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        view.feed(text: "alpha bravo charlie\r\nsecond row\r\n")
        return view
    }

    private func selectWord(in view: TerminalView) {
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 5, row: 0))
    }
}
#endif
