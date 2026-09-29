#if os(macOS) || os(iOS) || os(visionOS)
import Testing
import QuartzCore
import MetalKit
@testable import SwiftTerm
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Exercise the native display entry point, not just updateDisplay's scheduler.
@Suite(.serialized)
@MainActor
struct SynchronizedPresentationTests {
    private let esc = "\u{1b}"

    private func makeView() -> PresentationProbe {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        let view = PresentationProbe(frame: CGRect(x: 0, y: 0, width: 400, height: 160))
        view.feed(text: "\(esc)[?25l\(esc)[HBEFORE")
        view.updateDisplay(notifyAccessibility: false)
        return view
    }

    private func backingLayer(_ view: TerminalView) throws -> CALayer {
        #if os(macOS)
        return try #require(view.layer)
        #else
        return view.layer
        #endif
    }

    private func pixels(_ layer: CALayer) throws -> Data {
        let width = 400, height = 160
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        layer.render(in: context)
        return Data(bytes: try #require(context.data), count: width * height * 4)
    }

    @Test func nativeDisplayRetainsCompletedFrameUntilSyncEnds() throws {
        let view = makeView()
        let layer = try backingLayer(view)
        layer.display()
        let before = try pixels(layer)
        #expect(layer.contents != nil)

        view.feed(text: "\(esc)[?2026h\(esc)[2J\(esc)[HINCOMPLETE")
        // AppKit/UIKit may invalidate the layer independently of our scheduler.
        layer.setNeedsDisplay()
        layer.displayIfNeeded()
        #expect(try pixels(layer) == before)

        view.feed(text: "\(esc)[HCOMPLETE  \(esc)[?2026l")
        view.updateDisplay(notifyAccessibility: false)
        layer.displayIfNeeded()
        #expect(try pixels(layer) != before)
    }

    @Test func firstFrameDoesNotPresentPartialContent() throws {
        let view = makeView()
        let layer = try backingLayer(view)
        view.feed(text: "\(esc)[?2026h\(esc)[HPARTIAL")
        layer.display()
        #expect(layer.contents == nil)
        view.feed(text: "\(esc)[?2026l")
        view.updateDisplay(notifyAccessibility: false)
        layer.displayIfNeeded()
        #expect(layer.contents != nil)
    }

    @Test func syncEndConsumesDirtyRangeBeforeNativePresentation() throws {
        let view = makeView()
        view.feed(text: "\(esc)[?2026h\(esc)[HCOMPLETE\(esc)[?2026l")
        // Native painting and the delayed feed scheduler must not independently
        // commit the same dirty range. This contract is shared by Mac and iOS.
        #expect(view.terminal.getUpdateRange() == nil)
        #expect(view.caretView?.isHidden == true)
    }

    @Test func bytesAfterSyncEndStillGetPresented() async throws {
        let view = makeView()
        view.feed(text: "\(esc)[?2026h\(esc)[HCOMPLETE\(esc)[?2026l\(esc)[HTRAILING")
        #expect(view.terminal.getUpdateRange() != nil)
        try await Task.sleep(for: .milliseconds(60))
        #expect(view.terminal.getUpdateRange() == nil)
        #expect(view.terminal.getLine(row: 0)?.translateToString(trimRight: true).hasPrefix("TRAILING") == true)
    }

    @Test func cursorRemainsAttachedAndCommitsOnlyFinalVisibilityAndPosition() throws {
        let view = makeView()
        view.feed(text: "\(esc)[?25h")
        view.updateDisplay(notifyAccessibility: false)
        let caret = try #require(view.caretView)
        let originalFrame = caret.frame
        view.childAdds = 0
        view.childRemovals = 0
        #expect(caret.superview === view)
        #expect(!caret.isHidden)

        for _ in 0..<120 {
            view.feed(text: "\(esc)[?2026h\(esc)[?25l\(esc)[3;5H")
            view.updateCursorPosition() // e.g. a layout pass during a split feed
            #expect(caret.superview === view)
            #expect(!caret.isHidden)
            #expect(caret.frame == originalFrame)
            view.feed(text: "\(esc)[?25h\(esc)[1;7H\(esc)[?2026l")
            view.updateDisplay(notifyAccessibility: false)
            #expect(caret.superview === view)
            #expect(!caret.isHidden)
        }

        view.feed(text: "\(esc)[?2026h\(esc)[?25l\(esc)[?2026l")
        view.updateDisplay(notifyAccessibility: false)
        #expect(caret.isHidden)
        #expect(caret.superview === view)
        view.feed(text: "\(esc)[?25h")
        view.updateDisplay(notifyAccessibility: false)
        #expect(!caret.isHidden)
        #expect(caret.superview === view)
        #expect(view.childAdds == 0)
        #expect(view.childRemovals == 0)
    }

    @Test func cursorStaysAttachedWhileReadingScrollback() throws {
        let view = makeView()
        for row in 0..<40 { view.feed(text: "line \(row)\r\n") }
        view.feed(text: "\(esc)[?25h")
        view.scrollTo(row: 0, notifyAccessibility: false)
        let caret = try #require(view.caretView)
        #expect(caret.isHidden)
        #expect(caret.superview === view)
        view.scrollTo(row: view.terminal.buffer.yBase, notifyAccessibility: false)
        #expect(!caret.isHidden)
        #expect(caret.superview === view)
    }

    @Test func timeoutReleasesNativeDisplayAndFinalCursor() async throws {
        let view = makeView()
        let layer = try backingLayer(view)
        layer.display()
        let before = try pixels(layer)
        view.feed(text: "\(esc)[?2026h\(esc)[HAFTER TIMEOUT\(esc)[?25h")
        try await Task.sleep(for: .milliseconds(1150))
        #expect(!view.terminal.synchronizedOutputActive)
        view.updateDisplay(notifyAccessibility: false)
        layer.displayIfNeeded()
        #expect(try pixels(layer) != before)
        #expect(view.caretView?.isHidden == false)
    }

    @Test func resetAndResizeReleaseDisplayBarrier() throws {
        let view = makeView()
        let layer = try backingLayer(view)
        for resize in [false, true] {
            view.feed(text: "\(esc)[?2026h\(esc)[HPARTIAL")
            if resize {
                view.resize(cols: 32, rows: 6)
            } else {
                view.terminal.resetToInitialState()
            }
            #expect(!view.terminal.synchronizedOutputActive)
            view.feed(text: "\(esc)[HRECOVERED")
            view.updateDisplay(notifyAccessibility: false)
            layer.displayIfNeeded()
            #expect(layer.contents != nil)
        }
    }

    @Test func cursorStyleIsDeferredWithTheFrame() throws {
        let view = makeView()
        let caret = try #require(view.caretView)
        let previousStyle = caret.style
        view.feed(text: "\(esc)[?2026h\(esc)[6 q")
        #expect(caret.style == previousStyle)
        view.feed(text: "\(esc)[?2026l")
        view.updateDisplay(notifyAccessibility: false)
        #expect(caret.style == .steadyBar)
    }

    @Test func directDrawDoesNotClearOrPaintDuringSync() throws {
        let view = makeView()
        let context = try #require(CGContext(data: nil, width: 400, height: 160,
            bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(view.bounds)
        let bytes = try #require(context.data)
        let before = Data(bytes: bytes, count: 400 * 160 * 4)
        view.feed(text: "\(esc)[?2026h\(esc)[2J\(esc)[HPARTIAL")
        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(context)
        view.draw(view.bounds)
        UIGraphicsPopContext()
        #endif
        #expect(Data(bytes: bytes, count: before.count) == before)
        view.drawTerminalContents(dirtyRect: view.bounds, context: context, bufferOffset: 0)
        #expect(Data(bytes: bytes, count: before.count) == before)
        view.feed(text: "\(esc)[?2026l")
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func metalDoesNotAcquireDrawableDuringSync() throws {
        let view = makeView()
        let metal = DrawableProbe(frame: view.bounds, device: MTLCreateSystemDefaultDevice())
        metal.isPaused = true
        let renderer = try MetalTerminalRenderer(view: metal, terminalView: view)
        view.feed(text: "\(esc)[?2026h\(esc)[HPARTIAL")
        for _ in 0..<10 { renderer.draw(in: metal) }
        #expect(metal.drawableRequests == 0)
        view.feed(text: "\(esc)[?2026l")
        renderer.draw(in: metal)
        // currentRenderPassDescriptor may also query currentDrawable.
        #expect(metal.drawableRequests > 0)
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func switchingRendererDoesNotShowAHiddenCursor() throws {
        let view = makeView()
        try view.setUseMetal(true)
        view.feed(text: "\(esc)[?25h")
        view.updateDisplay(notifyAccessibility: false)
        #expect(view.caretView?.isHidden == true) // Metal owns the cursor.
        view.feed(text: "\(esc)[?25l")
        try view.setUseMetal(false)
        #expect(view.caretView?.isHidden == true)
        #expect(view.caretView?.superview === view)
    }
}

#if os(macOS)
private typealias NativeView = NSView
#else
private typealias NativeView = UIView
#endif

private final class PresentationProbe: TerminalView {
    var childAdds = 0
    var childRemovals = 0
    override func didAddSubview(_ subview: NativeView) {
        super.didAddSubview(subview)
        childAdds += 1
    }
    override func willRemoveSubview(_ subview: NativeView) {
        childRemovals += 1
        super.willRemoveSubview(subview)
    }
}

private final class DrawableProbe: MTKView {
    var drawableRequests = 0
    override var currentDrawable: CAMetalDrawable? {
        drawableRequests += 1
        return nil
    }
}
#endif
