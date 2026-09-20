#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

@MainActor
@Suite("Mac legacy modified arrows", .serialized)
struct MacModifiedArrowTests {
    // Record AppKit handoff without depending on the machine's active input
    // source or key-binding preferences. Shift+arrows must not get this far.
    private final class InputView: TerminalView {
        var interpretedEvents: [NSEvent] = []
        override func interpretKeyEvents(_ events: [NSEvent]) {
            interpretedEvents.append(contentsOf: events)
        }
    }

    private final class Capture: TerminalViewDelegate {
        var sent: [UInt8] = []
        func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    @Test(arguments: ["A", "B", "C", "D"], [false, true])
    func shiftedArrowsRetainModifiers(direction: String, applicationCursor: Bool) throws {
        let view = InputView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let capture = Capture()
        view.terminalDelegate = capture
        view.optionAsMetaKey = true
        if applicationCursor { view.feed(text: "\u{1b}[?1h") }

        let combinations: [(NSEvent.ModifierFlags, Int)] = [
            (.shift, 2), ([.shift, .option], 4),
            ([.shift, .control], 6), ([.shift, .option, .control], 8),
            ([.shift, .capsLock], 2),
        ]
        for (flags, modifier) in combinations {
            capture.sent = []
            view.keyDown(with: try arrow(direction, flags: flags))
            #expect(capture.sent == Array("\u{1b}[1;\(modifier)\(direction)".utf8))
        }
        #expect(view.interpretedEvents.isEmpty)
    }

    @Test
    func repeatedShiftArrowDoesNotNegotiateKitty() throws {
        let view = InputView(frame: .zero)
        let capture = Capture()
        view.terminalDelegate = capture
        view.keyDown(with: try arrow("D", flags: .shift, isRepeat: true))
        #expect(capture.sent == Array("\u{1b}[1;2D".utf8))
        #expect(view.getTerminal().keyboardEnhancementFlags.isEmpty)
    }

    @Test
    func composingArrowsStayWithInputMethod() throws {
        let view = InputView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let capture = Capture()
        view.terminalDelegate = capture
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        for direction in ["A", "B", "C", "D"] {
            view.keyDown(with: try arrow(direction, flags: .shift))
        }
        #expect(view.hasMarkedText())
        #expect(view.interpretedEvents.count == 4)
        #expect(capture.sent.isEmpty)
    }

    enum CompositionEnd: CaseIterable {
        case commit, emptyCommit, clearPlain, clearAttributed, unmark, bracketedPaste
    }

    @Test("Finished IME composition cannot keep modified arrows in AppKit",
          arguments: CompositionEnd.allCases, [false, true])
    func shiftedArrowsAfterComposition(end: CompositionEnd, kitty: Bool) throws {
        let view = InputView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let capture = Capture()
        view.terminalDelegate = capture
        if kitty { view.feed(text: "\u{1b}[>3u") }
        let replacement = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                           replacementRange: replacement)
        #expect(view.hasMarkedText())

        switch end {
        case .commit:
            view.insertText("中", replacementRange: replacement)
            #expect(capture.sent == Array("中".utf8))
        case .emptyCommit:
            view.insertText("", replacementRange: replacement)
        case .clearPlain:
            view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0),
                               replacementRange: replacement)
        case .clearAttributed:
            view.setMarkedText(NSAttributedString(string: ""), selectedRange: NSRange(location: 0, length: 0),
                               replacementRange: replacement)
        case .unmark:
            view.unmarkText()
        case .bracketedPaste:
            view.feed(text: "\u{1b}[?2004h")
            view.insertText("中", replacementRange: replacement, isPaste: true)
            #expect(capture.sent == Array("\u{1b}[200~中\u{1b}[201~".utf8))
        }

        #expect(!view.hasMarkedText())
        capture.sent = []
        for direction in ["A", "B", "C", "D"] {
            view.keyDown(with: try arrow(direction, flags: .shift))
        }
        #expect(capture.sent == Array("\u{1b}[1;2A\u{1b}[1;2B\u{1b}[1;2C\u{1b}[1;2D".utf8))
        #expect(view.interpretedEvents.isEmpty)

        // Starting another composition must still reserve arrows for the IME.
        capture.sent = []
        view.setMarkedText("wen", selectedRange: NSRange(location: 3, length: 0),
                           replacementRange: replacement)
        view.keyDown(with: try arrow("D", flags: .shift))
        #expect(view.hasMarkedText())
        #expect(view.interpretedEvents.count == 1)
        #expect(capture.sent.isEmpty)
    }

    @Test
    func plainCommandAndComposePathsRemainAppKitOwned() throws {
        let view = InputView(frame: .zero)
        let capture = Capture()
        view.terminalDelegate = capture
        view.optionAsMetaKey = false
        for flags: NSEvent.ModifierFlags in [[], [.shift, .command], [.shift, .option]] {
            view.keyDown(with: try arrow("D", flags: flags))
        }
        #expect(view.interpretedEvents.count == 3)
        #expect(capture.sent.isEmpty)
    }

    @Test
    func optionWordMotionAndControlArrowsRemainUnchanged() throws {
        let view = InputView(frame: .zero)
        let capture = Capture()
        view.terminalDelegate = capture
        view.optionAsMetaKey = true
        view.keyDown(with: try arrow("D", flags: .option))
        view.keyDown(with: try arrow("C", flags: .option))
        view.keyDown(with: try arrow("D", flags: .control))
        view.keyDown(with: try arrow("C", flags: .control))
        #expect(capture.sent == Array("\u{1b}b\u{1b}f\u{1b}[1;5D\u{1b}[1;5C".utf8))
    }

    @Test
    func negotiatedKittyEventsKeepTheirExistingEncoding() throws {
        let view = InputView(frame: .zero)
        let capture = Capture()
        view.terminalDelegate = capture
        view.feed(text: "\u{1b}[>3u") // disambiguate + reportEvents
        view.keyDown(with: try arrow("D", flags: .shift, isRepeat: true))
        #expect(capture.sent == Array("\u{1b}[1;2:2D".utf8))
    }

    private func arrow(_ direction: String, flags: NSEvent.ModifierFlags, isRepeat: Bool = false) throws -> NSEvent {
        let (scalar, code): (Int, UInt16)
        switch direction {
        case "A": (scalar, code) = (NSUpArrowFunctionKey, 126)
        case "B": (scalar, code) = (NSDownArrowFunctionKey, 125)
        case "C": (scalar, code) = (NSRightArrowFunctionKey, 124)
        default: (scalar, code) = (NSLeftArrowFunctionKey, 123)
        }
        let characters = String(try #require(UnicodeScalar(scalar)))
        return try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags.union([.function, .numericPad]),
            timestamp: 0, windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: isRepeat, keyCode: code
        ))
    }
}
#endif
