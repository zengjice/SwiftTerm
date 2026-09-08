#if os(iOS) || os(visionOS)
import Testing
import UIKit
@testable import SwiftTerm

@Suite("iOS selection tap routing", .serialized)
@MainActor
struct IOSSelectionTapTests {
    @Test(arguments: [2, 3])
    func defaultBehaviorStillSelects(tapCount: Int) {
        let view = makeView()
        tap(view, count: tapCount, column: 1)

        #expect(view.selection.active)
        #expect(view.selection.getSelectedText().trimmingCharacters(in: .whitespacesAndNewlines)
            == (tapCount == 2 ? "hello" : "hello world"))
        #expect(view.panSelectionGesture?.isEnabled == true)
        #expect(view.lastLongSelect == Position(col: 1, row: 0))
    }

    @Test(arguments: [2, 3], [1, 25])
    func vetoConsumesTapBeforeAnySelectionOrMenu(tapCount: Int, column: Int) {
        let view = makeView()
        view.allowsSelection = false
        let offset = view.contentOffset
        let cursor = Position(col: view.getTerminal().buffer.x, row: view.getTerminal().buffer.y)

        let gesture = tap(view, count: tapCount, column: column)

        #expect(view.checkedPositions == [Position(col: column, row: 0)])
        #expect(!view.selection.active)
        #expect(view.panSelectionGesture == nil)
        #expect(view.lastLongSelect == nil)
        #expect(view.contentOffset == offset)
        #expect(Position(col: view.getTerminal().buffer.x, row: view.getTerminal().buffer.y) == cursor)
        // A rejected selection must not fail/disable its recognized multi-tap.
        #expect(gesture.state == .ended)
        #expect(gesture.isEnabled)
    }

    @Test(arguments: [2, 3])
    func vetoPreservesAnExistingSelectionAndHandleGesture(tapCount: Int) {
        let view = makeView()
        tap(view, count: 2, column: 1)
        let text = view.selection.getSelectedText()
        let handleGesture = view.panSelectionGesture
        let menuPosition = view.lastLongSelect
        view.allowsSelection = false

        tap(view, count: tapCount, column: 25)

        #expect(view.selection.active)
        #expect(view.selection.getSelectedText() == text)
        #expect(view.panSelectionGesture === handleGesture)
        #expect(view.panSelectionGesture?.isEnabled == true)
        #expect(view.lastLongSelect == menuPosition)
    }

    @Test
    func singleTapStillExitsSelectionWithoutTakingFocus() {
        let view = makeView()
        tap(view, count: 2, column: 1)
        view.allowsSelection = false
        #expect(!view.isFirstResponder)

        let gesture = makeTap(view, count: 1, column: 25)
        view.singleTap(gesture)

        #expect(!view.selection.active)
        #expect(view.panSelectionGesture?.isEnabled == false)
        #expect(!view.isFirstResponder)
        #expect(view.checkedPositions.count == 1)
    }

    @Test
    func selectionHandleHitTestingIsIndependentOfTapVeto() throws {
        let view = makeView()
        tap(view, count: 2, column: 1)
        view.allowsSelection = false
        let pan = try #require(view.panSelectionGesture)

        // An idle pan reports the origin: it is next to the "hello" start
        // handle, so dragging here still belongs to selection, not scrolling.
        #expect(view.gestureRecognizerShouldBegin(pan))
        view.setSelectionRange(start: Position(col: 20, row: 4), end: Position(col: 25, row: 4))
        #expect(!view.gestureRecognizerShouldBegin(pan))
        #expect(view.checkedPositions.count == 1)
    }

    @Test
    func programmaticSelectionIsNotVetoed() {
        let view = makeView()
        view.allowsSelection = false

        view.setSelectionRange(start: Position(col: 0, row: 0), end: Position(col: 5, row: 0))

        #expect(view.selection.active)
        #expect(view.selection.getSelectedText() == "hello")
        #expect(view.checkedPositions.isEmpty)
    }

    @Test(arguments: [2, 3])
    func mouseReportingDoesNotAskForLocalSelection(tapCount: Int) {
        let view = makeView()
        view.allowMouseReporting = true
        view.feed(text: "\u{1b}[?1000h")
        view.allowsSelection = false

        tap(view, count: tapCount, column: 1)

        #expect(view.checkedPositions.isEmpty)
        #expect(!view.selection.active)
    }

    @Test
    func unfinishedTapDoesNothing() {
        let view = makeView()
        let gesture = makeTap(view, count: 2, column: 1)
        gesture.state = .possible

        view.doubleTap(gesture)
        view.tripleTap(gesture)

        #expect(view.checkedPositions.isEmpty)
        #expect(!view.selection.active)
    }

    private func makeView() -> SelectionPolicyTerminalView {
        let view = SelectionPolicyTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.allowMouseReporting = false
        view.feed(text: "hello world")
        return view
    }

    @discardableResult
    private func tap(_ view: TerminalView, count: Int, column: Int) -> CompletedSelectionTap {
        let gesture = makeTap(view, count: count, column: column)
        if count == 2 {
            view.doubleTap(gesture)
        } else {
            view.tripleTap(gesture)
        }
        return gesture
    }

    private func makeTap(_ view: TerminalView, count: Int, column: Int) -> CompletedSelectionTap {
        let gesture = CompletedSelectionTap()
        gesture.numberOfTapsRequired = count
        gesture.point = CGPoint(
            x: (CGFloat(column) + 0.5) * view.cellDimension.width,
            y: view.cellDimension.height * 0.5
        )
        view.addGestureRecognizer(gesture)
        gesture.state = .ended
        return gesture
    }
}

@MainActor
private final class SelectionPolicyTerminalView: TerminalView {
    var allowsSelection = true
    var checkedPositions: [Position] = []

    override var canBecomeFirstResponder: Bool { false }

    override func shouldBeginSelection(at position: Position) -> Bool {
        checkedPositions.append(position)
        return allowsSelection && super.shouldBeginSelection(at: position)
    }
}

/// Drive the real tap action with a completed recognizer and a deterministic
/// location; do not synthesize touches or depend on the multi-tap timeout.
@MainActor
private final class CompletedSelectionTap: UITapGestureRecognizer {
    var point = CGPoint.zero
    private var reportedState = UIGestureRecognizer.State.possible

    override var state: UIGestureRecognizer.State {
        get { reportedState }
        set { reportedState = newValue }
    }

    override func location(in view: UIView?) -> CGPoint { point }
}
#endif
