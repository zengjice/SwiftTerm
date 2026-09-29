#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import SwiftTerm

/// Unlike offscreen layer.display() probes, these tests let AppKit consume
/// ordinary view invalidations in a real window. Forcing the layer to display
/// masks a broken NSView -> CALayer invalidation path.
@MainActor
@Suite("Mac backing-layer lifecycle", .serialized)
struct MacBackingLayerLifecycleTests {
    private let frame = CGRect(x: 0, y: 0, width: 400, height: 180)
    private let esc = "\u{1b}"

    @Test(arguments: [false, true])
    func firstFrameAndOrdinaryOutputPaintWithoutInteraction(swiftUI: Bool) async throws {
        let view = makeView()
        view.feed(text: "\(esc)[?25l\(esc)[HFIRST FRAME")
        let window = makeWindow(view, swiftUI: swiftUI)
        defer { close(window) }
        window.orderBack(nil)

        #expect(try await waitUntil { view.drawCount > 0 })
        #expect(view.lastPaintedLine.hasPrefix("FIRST FRAME"))
        let previousDraws = view.drawCount
        // No DEC 2026, scroll, forced layer display or synthetic resize.
        view.feed(text: "\(esc)[HSECOND FRAME")
        #expect(try await waitUntil { view.drawCount > previousDraws })
        #expect(view.lastPaintedLine.hasPrefix("SECOND FRAME"))
    }

    @Test
    func attachmentUsesTheRealWindowsPixelScale() async throws {
        let view = makeView()
        let window = makeWindow(view)
        defer { close(window) }
        let layer = try #require(view.layer)
        #expect(layer.contentsScale == window.backingScaleFactor)
        #expect(view.layerContentsRedrawPolicy == .onSetNeedsDisplay)
        window.orderBack(nil)
        #expect(try await waitUntil { view.drawCount > 0 })
        #expect(view.lastDrawScale == window.backingScaleFactor)
    }

    @Test
    func backingScaleChangesRepaintWithoutChangingTerminalState() async throws {
        let view = makeView()
        let window = makeScaleWindow(view, scale: 1)
        defer { close(window) }
        window.orderBack(nil)
        #expect(try await waitUntil { view.drawCount > 0 })
        view.feed(text: "\(esc)[HSCALE CONTENT\(esc)[2;4H")
        #expect(try await waitUntil { view.lastPaintedLine.hasPrefix("SCALE CONTENT") })
        let terminal = view.getTerminal()
        let dimensions = (terminal.cols, terminal.rows)
        let cursor = (terminal.buffer.x, terminal.buffer.y)
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 5, row: 0))
        let selection = view.getSelection()

        for scale: CGFloat in [2, 1, 2] {
            let previousDraws = view.drawCount
            window.reportedScale = scale
            // Model the notification delivered when moving between screens.
            view.viewDidChangeBackingProperties()
            #expect(view.layer?.contentsScale == scale)
            #expect(try await waitUntil { view.drawCount > previousDraws })
            #expect(view.lastDrawScale == scale)
            #expect(terminal.cols == dimensions.0 && terminal.rows == dimensions.1)
            #expect(terminal.buffer.x == cursor.0 && terminal.buffer.y == cursor.1)
            #expect(view.getSelection() == selection)
            #expect(view.lastPaintedLine.hasPrefix("SCALE CONTENT"))
        }
    }

    @Test
    func movingBetweenWindowsRefreshesScaleAndFirstFrame() async throws {
        let view = makeView()
        view.feed(text: "\(esc)[?25l\(esc)[HPERSISTENT CONTENT")
        let first = makeScaleWindow(view, scale: 1)
        let second = makeScaleWindow(nil, scale: 2)
        defer { close(first); close(second) }
        first.orderBack(nil)
        #expect(try await waitUntil { view.drawCount > 0 })
        let previousDraws = view.drawCount
        second.contentView?.addSubview(view)
        second.orderBack(nil)
        #expect(view.window === second)
        #expect(view.layer?.contentsScale == 2)
        #expect(try await waitUntil { view.drawCount > previousDraws })
        #expect(view.lastDrawScale == 2)
        #expect(view.lastPaintedLine.hasPrefix("PERSISTENT CONTENT"))
    }

    @Test
    func hiddenTabPaintsItsLatestContentWhenShownAgain() async throws {
        let first = makeView()
        let second = makeView()
        let window = makeWindow(first)
        defer { close(window) }
        window.orderBack(nil)
        #expect(try await waitUntil { first.drawCount > 0 })

        first.isHidden = true
        second.feed(text: "\(esc)[?25l\(esc)[HSECOND TAB")
        window.contentView?.addSubview(second)
        #expect(try await waitUntil { second.drawCount > 0 })
        #expect(second.lastPaintedLine.hasPrefix("SECOND TAB"))
        let previousDraws = first.drawCount
        first.feed(text: "\(esc)[?25l\(esc)[HFIRST TAB UPDATED")
        try await pump(for: 0.05)
        second.removeFromSuperview()
        first.isHidden = false
        #expect(try await waitUntil { first.drawCount > previousDraws })
        #expect(first.lastPaintedLine.hasPrefix("FIRST TAB UPDATED"))
    }

    @Test
    func nativeInvalidationDuringSyncWaitsForCompletedFrame() async throws {
        let view = makeView()
        view.feed(text: "\(esc)[?25l\(esc)[HBEFORE")
        let window = makeWindow(view)
        defer { close(window) }
        window.orderBack(nil)
        #expect(try await waitUntil { view.drawCount > 0 })
        let previousDraws = view.drawCount

        view.feed(text: "\(esc)[?2026h\(esc)[HPARTIAL")
        view.needsDisplay = true
        try await pump(for: 0.05)
        #expect(view.getTerminal().synchronizedOutputActive)
        #expect(view.drawCount == previousDraws)
        #expect(view.lastPaintedLine.hasPrefix("BEFORE"))

        view.feed(text: "\(esc)[HCOMPLETE\(esc)[?2026l")
        #expect(try await waitUntil { view.drawCount > previousDraws })
        #expect(view.lastPaintedLine.hasPrefix("COMPLETE"))
    }

    @Test
    func synchronizedFramesPaintOnceIncludingReturnToLatest() async throws {
        let view = makeView()
        view.feed(text: "\(esc)[?1049h\(esc)[?25l\(esc)[HSTART")
        let window = makeWindow(view)
        defer { close(window) }
        window.orderBack(nil)
        try await pump(for: 0.1)
        let band = view.terminal.rows - 2
        // Both directions, then the final frame at the live edge. No forced draw.
        for index in 0..<12 {
            let previousDraws = view.drawCount
            let scroll = index < 6 ? "3T" : "3S"
            let label = index == 11 ? "LATEST" : "FRAME \(index)"
            view.feed(text: "\(esc)[?2026h\(esc)[1;\(band)r\(esc)[\(scroll)\(esc)[H\(label)\(esc)[r\(esc)[?2026l")
            try await pump(for: 0.06)
            #expect(view.drawCount == previousDraws + 1)
            #expect(view.lastPaintedLine.hasPrefix(label))
        }
    }

    @Test
    func firstSynchronizedFrameAppearsAtSyncEndWithoutMoreText() async throws {
        let view = makeView()
        let window = makeWindow(view)
        defer { close(window) }
        view.feed(text: "\(esc)[?2026h\(esc)[?25l\(esc)[HFIRST SYNC FRAME")
        window.orderBack(nil)
        try await pump(for: 0.05)
        #expect(view.drawCount == 0)
        #expect(view.getTerminal().synchronizedOutputActive)

        view.feed(text: "\(esc)[?2026l")
        #expect(try await waitUntil { view.drawCount > 0 })
        #expect(view.lastPaintedLine.hasPrefix("FIRST SYNC FRAME"))
    }

    @Test
    func syncTimeoutRepaintsWithoutAnyLaterBytes() async throws {
        let view = makeView()
        let window = makeWindow(view)
        defer { close(window) }
        window.orderBack(nil)
        #expect(try await waitUntil { view.drawCount > 0 })
        let previousDraws = view.drawCount
        view.feed(text: "\(esc)[?2026h\(esc)[?25l\(esc)[HAFTER TIMEOUT")
        view.needsDisplay = true
        try await pump(for: 0.05)
        #expect(view.drawCount == previousDraws)
        #expect(try await waitUntil(timeout: 1.5) { view.drawCount > previousDraws })
        #expect(!view.getTerminal().synchronizedOutputActive)
        #expect(view.lastPaintedLine.hasPrefix("AFTER TIMEOUT"))
    }

    @Test
    func resizeStillRepaintsWithoutNewOutput() async throws {
        let view = makeView()
        view.feed(text: "\(esc)[?25l\(esc)[HRESIZE CONTENT")
        let window = makeWindow(view)
        defer { close(window) }
        window.orderBack(nil)
        #expect(try await waitUntil { view.drawCount > 0 })
        let previousDraws = view.drawCount
        view.setFrameSize(CGSize(width: 380, height: 160))
        #expect(try await waitUntil { view.drawCount > previousDraws })
        #expect(view.lastPaintedLine.hasPrefix("RESIZE CONTENT"))
    }

    private func makeView() -> BackingLifecycleProbe {
        _ = NSApplication.shared
        let view = BackingLifecycleProbe(frame: frame)
        view.nativeForegroundColor = .white
        view.nativeBackgroundColor = .black
        return view
    }

    private func makeWindow(_ view: NSView, swiftUI: Bool = false) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        prepare(window)
        if swiftUI {
            window.contentView = NSHostingView(rootView: TerminalLifecycleHost(view: view)
                .frame(width: frame.width, height: frame.height))
        } else {
            window.contentView?.addSubview(view)
        }
        return window
    }

    private func makeScaleWindow(_ view: NSView?, scale: CGFloat) -> BackingScaleProbeWindow {
        let window = BackingScaleProbeWindow(contentRect: frame, styleMask: .borderless,
                                             backing: .buffered, defer: false)
        window.reportedScale = scale
        prepare(window)
        if let view { window.contentView?.addSubview(view) }
        return window
    }

    private func prepare(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.title = "SwiftTerm backing-layer test"
        let wrapper = NSView(frame: frame)
        wrapper.wantsLayer = true
        wrapper.layer?.masksToBounds = true
        window.contentView = wrapper
    }

    private func close(_ window: NSWindow) {
        window.orderOut(nil)
        window.close()
    }

    private func waitUntil(timeout: TimeInterval = 0.5, _ condition: () -> Bool) async throws -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            try await pump(for: 0.01)
            if condition() { return true }
        } while Date() < deadline
        return condition()
    }

    private func pump(for interval: TimeInterval) async throws {
        // Service AppKit/CA naturally. Do not call display(), displayIfNeeded(),
        // updateDisplay() or layer.setNeedsDisplay() to make a test pass.
        // Yield the main executor too: nested RunLoop.run alone cannot execute
        // the renderer's delayed main-queue update while inside a main-actor job.
        let deadline = Date(timeIntervalSinceNow: interval)
        repeat {
            drainNativeEvents()
            try await Task.sleep(for: .milliseconds(5))
        } while Date() < deadline
    }

    private func drainNativeEvents() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
    }
}

@MainActor
private final class BackingLifecycleProbe: TerminalView {
    var drawCount = 0
    var lastDrawScale: CGFloat = 0
    var lastPaintedLine = ""

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        lastDrawScale = NSGraphicsContext.current?.cgContext.ctm.a ?? 0
        lastPaintedLine = terminal.getLine(row: 0)?.translateToString(trimRight: true) ?? ""
        super.draw(dirtyRect)
    }
}

@MainActor
private final class BackingScaleProbeWindow: NSWindow {
    var reportedScale: CGFloat = 1
    override var backingScaleFactor: CGFloat { reportedScale }
}

@MainActor
private struct TerminalLifecycleHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
