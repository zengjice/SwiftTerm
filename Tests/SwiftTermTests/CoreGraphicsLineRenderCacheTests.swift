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
        let line = BufferLine(cols: 4)
        var cache = CoreGraphicsLineRenderCache<String>()
        cache.insert("first", forRow: 1, line: line, cols: 4)
        cache.insert("second", forRow: 2, line: line, cols: 4)
        cache.insert("third", forRow: 3, line: line, cols: 4)

        cache.retainRows(in: 2...3)

        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.value(forRow: 1, line: line, cols: 4))
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
