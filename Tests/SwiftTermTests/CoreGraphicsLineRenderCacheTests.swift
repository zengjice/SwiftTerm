#if os(macOS)
import XCTest
@testable import SwiftTerm

final class CoreGraphicsLineRenderCacheTests: XCTestCase {
    func testReusesUnchangedLine() {
        let line = BufferLine(cols: 4)
        var cache = CoreGraphicsLineRenderCache<String>()
        cache.insert("cached", forRow: 2, line: line, cols: 4)

        XCTAssertEqual(cache.value(forRow: 2, line: line, cols: 4), "cached")
    }

    func testRejectsMutatedLine() {
        let line = BufferLine(cols: 4)
        var cache = CoreGraphicsLineRenderCache<String>()
        cache.insert("cached", forRow: 2, line: line, cols: 4)
        line.copyFrom(line: BufferLine(cols: 4))

        XCTAssertNil(cache.value(forRow: 2, line: line, cols: 4))
    }

    func testRejectsReplacementLine() {
        let original = BufferLine(cols: 4)
        let replacement = BufferLine(cols: 4)
        var cache = CoreGraphicsLineRenderCache<String>()
        cache.insert("cached", forRow: 2, line: original, cols: 4)

        XCTAssertNil(cache.value(forRow: 2, line: replacement, cols: 4))
    }

    func testRejectsColumnChange() {
        let line = BufferLine(cols: 4)
        var cache = CoreGraphicsLineRenderCache<String>()
        cache.insert("cached", forRow: 2, line: line, cols: 4)

        XCTAssertNil(cache.value(forRow: 2, line: line, cols: 8))
    }

    func testPrunesRowsOutsideViewport() {
        let lines = (0..<3).map { _ in BufferLine(cols: 4) }
        var cache = CoreGraphicsLineRenderCache<String>()
        cache.insert("first", forRow: 1, line: lines[0], cols: 4)
        cache.insert("second", forRow: 2, line: lines[1], cols: 4)
        cache.insert("third", forRow: 3, line: lines[2], cols: 4)

        cache.retainLines(Array(lines[1...2]))

        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.value(forRow: 1, line: lines[0], cols: 4))
    }

    func testReusesMovedLinesInBothDirectionsWithoutOverwritingNeighbors() {
        let lines = (0..<5).map { _ in BufferLine(cols: 4) }
        var cache = CoreGraphicsLineRenderCache<Int>()
        for (row, line) in lines.enumerated() {
            cache.insert(row, forRow: row, line: line, cols: 4)
        }
        for offset in [-3, 3] {
            cache.retainLines(lines)
            for (row, line) in lines.enumerated() {
                XCTAssertEqual(cache.value(forRow: row + offset, line: line, cols: 4), row)
            }
        }
        XCTAssertEqual(cache.count, 5)
    }

    func testMovedLineStillChecksGenerationAndColumns() {
        let line = BufferLine(cols: 4)
        var cache = CoreGraphicsLineRenderCache<String>()
        cache.insert("cached", forRow: 2, line: line, cols: 4)
        XCTAssertNil(cache.value(forRow: 5, line: line, cols: 8))
        line.copyFrom(line: BufferLine(cols: 4))
        XCTAssertNil(cache.value(forRow: 5, line: line, cols: 4))
    }

    func testRowDependentStateIsNotReusedAfterMoving() {
        let line = BufferLine(cols: 4)
        var cache = CoreGraphicsLineRenderCache<String>()
        cache.insert("kitty", forRow: 2, line: line, cols: 4, reusableAcrossRows: false)
        XCTAssertEqual(cache.value(forRow: 2, line: line, cols: 4), "kitty")
        XCTAssertNil(cache.value(forRow: 3, line: line, cols: 4))
        cache.insert("moved kitty", forRow: 3, line: line, cols: 4, reusableAcrossRows: false)
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.value(forRow: 3, line: line, cols: 4), "moved kitty")
    }

    func testMovingViewportBoundsCacheAndReleasesOldLines() {
        var cache = CoreGraphicsLineRenderCache<Int>()
        var visible = (0..<5).map { _ in BufferLine(cols: 4) }
        for step in 0..<100 {
            visible.removeFirst()
            visible.append(BufferLine(cols: 4))
            cache.retainLines(visible)
            for (row, line) in visible.enumerated() {
                cache.insert(step, forRow: row, line: line, cols: 4)
            }
            XCTAssertEqual(cache.count, visible.count)
        }
        weak var oldLine = visible[0]
        visible.removeAll()
        cache.retainLines([])
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(oldLine)
    }

    func testDoesNotCacheSelection() {
        XCTAssertFalse(canCacheCoreGraphicsLineRenderState(
            selectionActive: true,
            linkHighlightMode: .always,
            commandActive: false,
            hasLinkHighlight: false
        ))
    }

    func testDoesNotCacheDynamicModifierHighlight() {
        XCTAssertFalse(canCacheCoreGraphicsLineRenderState(
            selectionActive: false,
            linkHighlightMode: .alwaysWithModifier,
            commandActive: true,
            hasLinkHighlight: false
        ))
    }

    func testCachesStaticLinkModes() {
        XCTAssertTrue(canCacheCoreGraphicsLineRenderState(
            selectionActive: false,
            linkHighlightMode: .always,
            commandActive: true,
            hasLinkHighlight: true
        ))
        XCTAssertTrue(canCacheCoreGraphicsLineRenderState(
            selectionActive: false,
            linkHighlightMode: .hover,
            commandActive: false,
            hasLinkHighlight: false
        ))
    }
}
#endif
