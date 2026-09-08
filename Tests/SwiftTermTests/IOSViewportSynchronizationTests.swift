#if os(iOS) || os(visionOS)
import Foundation
import Testing
import UIKit
@testable import SwiftTerm

@Suite("iOS terminal viewport synchronization")
@MainActor
struct IOSViewportSynchronizationTests {
    @Test
    func repeatedBottomScrollResynchronizesViewportAfterGeometryChange() {
        let view = makeView()
        stageHostResize(view, rows: 5)
        view.bounds.size.height = view.cellDimension.height * 5

        // No layout yet: an explicit same-row request must repair the native
        // viewport even though the emulator already considers itself at bottom.
        #expect(view.scrollPosition == 1)
        #expect(abs(view.contentOffset.y - expectedOffset(view)) > 0.5)
        view.scroll(toPosition: 1)
        expectSynchronized(view)
    }

    @Test
    func nativeLayoutResynchronizesAlreadyResizedTerminalWithoutOutput() {
        let view = makeView()
        stageHostResize(view, rows: 5)
        let logicalRow = view.getTerminal().displayBuffer.yDisp

        view.bounds.size.height = view.cellDimension.height * 5
        layout(view)

        #expect(view.getTerminal().rows == 5)
        #expect(view.getTerminal().displayBuffer.yDisp == logicalRow)
        expectSynchronized(view)
        // No new terminal bytes or another explicit bottom request is needed.
        layout(view)
        expectSynchronized(view)
    }

    @Test
    func snapshotResetBeforeNativeLayoutKeepsComposerVisible() {
        let view = makeView()
        let terminal = view.getTerminal()
        terminal.resize(cols: terminal.cols, rows: 5)
        terminal.resetToInitialState()
        for line in 0..<30 {
            view.feed(text: "snapshot \(line)\r\n")
        }
        view.feed(text: "\u{1b}[5;1HINPUT_READY")
        view.scroll(toPosition: 1)
        view.updateScroller()

        view.bounds.size.height = view.cellDimension.height * 5
        layout(view)

        let buffer = terminal.displayBuffer
        #expect(buffer.lines[buffer.yDisp + 4].translateToString().contains("INPUT_READY"))
        expectSynchronized(view)
    }

    @Test
    func insetChangeResynchronizesWithoutResizingTheGrid() {
        let view = makeView()
        // A partial cell leaves the native maximum below the logical row offset.
        view.bounds.size.height += view.cellDimension.height / 2
        layout(view)
        view.updateScroller()
        let previousOffset = view.contentOffset.y
        let previousRows = view.getTerminal().rows
        view.testInsets = UIEdgeInsets(top: 0, left: 0, bottom: view.cellDimension.height, right: 0)
        view.adjustedContentInsetDidChange()

        #expect(view.getTerminal().rows == previousRows)
        #expect(view.contentOffset.y > previousOffset)
        expectSynchronized(view)
    }

    @Test
    func layoutPreservesHistoryFractionAndSelection() {
        let view = makeView()
        view.testTracking = true
        let historyOffset = view.cellDimension.height * 4 + 3
        view.contentOffset.y = historyOffset
        view.testTracking = false
        let terminal = view.getTerminal()
        let row = terminal.displayBuffer.yDisp
        view.selection.setSelection(
            start: Position(col: 0, row: row),
            end: Position(col: 6, row: row)
        )
        let selectedText = view.selection.getSelectedText()

        // Same grid, different native height. Preserve history and sub-row drag
        // position instead of treating a layout change as "scroll to bottom".
        view.bounds.size.height += 1
        layout(view)

        #expect(view.userScrolling)
        #expect(terminal.userScrolling)
        #expect(terminal.displayBuffer.yDisp == row)
        #expect(abs(view.contentOffset.y - historyOffset) < 0.5)
        #expect(view.selection.active)
        #expect(view.selection.getSelectedText() == selectedText)
    }

    @Test(arguments: [true, false])
    func layoutDoesNotOverrideAnActiveDragOrHistoryMomentum(tracking: Bool) {
        let view = makeView()
        view.scroll(toPosition: 0.5)
        let gestureOffset = view.contentOffset.y
        view.testTracking = tracking
        view.testDecelerating = !tracking
        let terminal = view.getTerminal()
        terminal.setViewYDisp(terminal.displayBuffer.yDisp + 2)

        view.bounds.size.height += 1
        layout(view)

        #expect(view.userScrolling)
        #expect(abs(view.contentOffset.y - gestureOffset) < 0.5)
    }

    @Test
    func outputDrivenLayoutDoesNotRealignTheViewportWithoutGeometryChange() {
        let view = makeView()
        view.scroll(toPosition: 0.5)
        layout(view)
        let originalOffset = view.contentOffset.y
        let terminal = view.getTerminal()
        terminal.setViewYDisp(terminal.displayBuffer.yDisp + 2)

        layout(view)

        #expect(abs(view.contentOffset.y - originalOffset) < 0.5)
    }

    private func makeView() -> InteractionTerminalView {
        let view = InteractionTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.contentInsetAdjustmentBehavior = .never
        view.bounds.size = CGSize(width: view.cellDimension.width * 40, height: view.cellDimension.height * 10)
        layout(view)
        for line in 0..<40 {
            view.feed(text: "line \(line)\r\n")
        }
        view.scroll(toPosition: 1)
        view.updateScroller()
        layout(view)
        return view
    }

    private func stageHostResize(_ view: TerminalView, rows: Int) {
        view.getTerminal().resize(cols: view.getTerminal().cols, rows: rows)
        // Run the emulator's scroller update while the old bounds still apply,
        // as can happen before Auto Layout applies the Host's new height.
        view.updateScroller()
    }

    private func layout(_ view: TerminalView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func expectedOffset(_ view: TerminalView) -> CGFloat {
        min(
            CGFloat(view.getTerminal().displayBuffer.yDisp) * view.cellDimension.height,
            max(0, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        )
    }

    private func expectSynchronized(_ view: TerminalView, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(view.scrollPosition == 1)
        #expect(abs(view.contentOffset.y - expectedOffset(view)) < 0.5, sourceLocation: sourceLocation)
    }
}

@MainActor
private final class InteractionTerminalView: TerminalView {
    var testTracking = false
    var testDecelerating = false
    var testInsets: UIEdgeInsets?

    override var isTracking: Bool { testTracking }
    override var isDecelerating: Bool { testDecelerating }
    override var adjustedContentInset: UIEdgeInsets { testInsets ?? super.adjustedContentInset }
}
#endif
