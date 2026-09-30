#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics
import CoreText
import Testing
@testable import SwiftTerm
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Suite(.serialized)
@MainActor
struct CoreGraphicsRenderingCacheTests {
    private let esc = "\u{1b}"

    private func makeView(alternate: Bool = false) -> TerminalView {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 160))
        view.frame.size = CGSize(width: view.cellDimension.width * 32,
                                 height: view.cellDimension.height * 8)
        view.resize(cols: 32, rows: 8)
        view.feed(text: (alternate ? "\(esc)[?1049h" : "") + "\(esc)[?25l")
        for row in 1...8 {
            view.feed(text: "\(esc)[\(row);1HRow \(row) 文本 e\u{301} 👩🏽‍💻 ▄─ ")
        }
        return view
    }

    private func paint(_ view: TerminalView) throws -> Data {
        let width = Int(ceil(view.frame.width)), height = Int(ceil(view.frame.height))
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        #else
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        #endif
        view.drawTerminalContents(dirtyRect: view.bounds, context: context, bufferOffset: 0)
        return Data(bytes: try #require(context.data), count: width * height * 4)
    }

    private func cachedLine(_ view: TerminalView, row: Int) throws -> CTLine {
        let buffer = view.terminal.displayBuffer
        let absoluteRow = buffer.yDisp + row
        let state = try #require(view.coreGraphicsLineRenderCache.value(
            forRow: absoluteRow, line: buffer.lines[absoluteRow], cols: buffer.cols))
        return try #require(state.preparedSegments.first).ctLine
    }

    private func expectFreshPixels(_ pixels: Data, view: TerminalView) throws {
        view.coreGraphicsLineRenderCache.removeAll()
        #expect(try paint(view) == pixels)
    }

    @Test func unchangedRowsReuseCoreTextLayoutAndPixels() throws {
        let view = makeView()
        let first = try paint(view)
        let line = try cachedLine(view, row: 0)
        #expect(try paint(view) == first)
        #expect(try cachedLine(view, row: 0) === line)
        try expectFreshPixels(first, view: view)
    }

    @Test func changedRowRebuildsWithoutDiscardingItsNeighbor() throws {
        let view = makeView()
        let before = try paint(view)
        let unchanged = try cachedLine(view, row: 0)
        let changed = try cachedLine(view, row: 1)
        view.feed(text: "\(esc)[2;1H\(esc)[2KREPLACEMENT")
        let after = try paint(view)
        #expect(after != before)
        #expect(try cachedLine(view, row: 0) === unchanged)
        #expect(try cachedLine(view, row: 1) !== changed)
        try expectFreshPixels(after, view: view)
    }

    @Test(arguments: [false, true])
    func scrollRegionReusesMovedRowsInBothDirections(down: Bool) throws {
        let view = makeView(alternate: true)
        _ = try paint(view)
        let header = try cachedLine(view, row: 0)
        let footer = try cachedLine(view, row: 7)
        let sourceRow = down ? 1 : 4
        let moved = try cachedLine(view, row: sourceRow)
        view.feed(text: "\(esc)[2;7r\(esc)[3\(down ? "T" : "S")\(esc)[r")
        let pixels = try paint(view)
        #expect(try cachedLine(view, row: down ? 4 : 1) === moved)
        #expect(try cachedLine(view, row: 0) === header)
        #expect(try cachedLine(view, row: 7) === footer)
        #expect(view.coreGraphicsLineRenderCache.count <= 8)
        try expectFreshPixels(pixels, view: view)
    }

    @Test(arguments: 0..<7)
    func presentationChangesInvalidateLayout(change: Int) throws {
        let view = makeView()
        _ = try paint(view)
        #expect(view.coreGraphicsLineRenderCache.count > 0)
        switch change {
        case 0:
            view.font = TTFont.monospacedSystemFont(ofSize: view.font.pointSize + 1, weight: .regular)
        case 1: view.nativeForegroundColor = .red
        case 2: view.nativeBackgroundColor = .gray
        case 3: view.feed(text: "\(esc)]4;1;#00ff00\u{7}")
        case 4: view.useBrightColors.toggle()
        case 5: view.customBlockGlyphs.toggle()
        default: view.linkHighlightMode = .always
        }
        #expect(view.coreGraphicsLineRenderCache.count == 0)
        try expectFreshPixels(try paint(view), view: view)
    }

    @Test func selectionAndDynamicLinksDoNotReuseUnselectedLayout() throws {
        let view = makeView()
        let normal = try paint(view)
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 5, row: 0))
        let selected = try paint(view)
        #expect(selected != normal)
        try expectFreshPixels(selected, view: view)
        #expect(view.coreGraphicsLineRenderCache.count == 0)
        view.selectNone()
        #expect(try paint(view) == normal)

        view.feed(text: "\(esc)[1;1H\(esc)]8;;https://example.test\u{7}link\(esc)]8;;\u{7}")
        view.linkHighlightMode = .alwaysWithModifier
        let plainLink = try paint(view)
        view.commandActive = true
        let highlighted = try paint(view)
        #expect(highlighted != plainLink)
        try expectFreshPixels(highlighted, view: view)
        #expect(view.coreGraphicsLineRenderCache.count == 0)
        view.commandActive = false
        #expect(try paint(view) == plainLink)
    }

    @Test func resizeAndResetCannotReuseOldRows() throws {
        let view = makeView()
        _ = try paint(view)
        let old = try cachedLine(view, row: 0)
        view.resize(cols: 24, rows: 8)
        var pixels = try paint(view)
        #expect(try cachedLine(view, row: 0) !== old)
        try expectFreshPixels(pixels, view: view)
        view.terminal.resetToInitialState()
        view.feed(text: "RESET")
        pixels = try paint(view)
        try expectFreshPixels(pixels, view: view)
    }

    #if os(iOS) || os(visionOS)
    @Test func fractionalHistoryViewportReusesOnlyVisibleLines() throws {
        let view = makeView()
        for row in 0..<50 { view.feed(text: "\r\nHistory \(row)") }
        view.scroll(toPosition: 0)
        view.contentOffset.y = view.cellDimension.height * 3.25
        let firstPixels = try paint(view)
        let line = view.terminal.displayBuffer.lines[3]
        let key = ObjectIdentifier(line)
        let entry = try #require(view.coreGraphicsLineRenderCache.entries[key])
        #expect(try paint(view) == firstPixels)
        #expect(view.coreGraphicsLineRenderCache.entries[key]?.value.preparedSegments.first?.ctLine
            === entry.value.preparedSegments.first?.ctLine)
        view.contentOffset.y = view.cellDimension.height * 25.5
        let pixels = try paint(view)
        #expect(view.coreGraphicsLineRenderCache.entries[key] == nil)
        #expect(view.coreGraphicsLineRenderCache.count <= Int(ceil(view.bounds.height / view.cellDimension.height)) + 1)
        try expectFreshPixels(pixels, view: view)
    }
    #endif
}
#endif
