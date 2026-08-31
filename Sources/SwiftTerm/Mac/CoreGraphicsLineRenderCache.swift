#if os(macOS)
import CoreText
import Foundation

struct PreparedViewLineSegment {
    let segment: ViewLineSegment
    let ctLine: CTLine
    let runs: [CTRun]
}

struct CoreGraphicsLineRenderState {
    let lineInfo: ViewLineInfo
    let preparedSegments: [PreparedViewLineSegment]
}

func canCacheCoreGraphicsLineRenderState(selectionActive: Bool,
                                         linkHighlightMode: LinkHighlightMode,
                                         commandActive: Bool,
                                         hasLinkHighlight: Bool) -> Bool {
    guard !selectionActive else { return false }

    switch linkHighlightMode {
    case .always:
        return true
    case .alwaysWithModifier:
        return !commandActive
    case .hover:
        return !hasLinkHighlight
    case .hoverWithModifier:
        return !commandActive && !hasLinkHighlight
    }
}

/// Bounded by the visible terminal rows. A BufferLine is mutated in place, so
/// object identity alone is insufficient; generation catches content changes.
struct CoreGraphicsLineRenderCache<Value> {
    struct Entry {
        let line: BufferLine
        let generation: UInt64
        let cols: Int
        let value: Value
    }

    private(set) var entries: [Int: Entry] = [:]

    var count: Int { entries.count }

    func value(forRow row: Int, line: BufferLine, cols: Int) -> Value? {
        guard let entry = entries[row],
              entry.line === line,
              entry.generation == line.generation,
              entry.cols == cols
        else {
            return nil
        }
        return entry.value
    }

    mutating func insert(_ value: Value, forRow row: Int, line: BufferLine, cols: Int) {
        entries[row] = Entry(line: line,
                             generation: line.generation,
                             cols: cols,
                             value: value)
    }

    mutating func retainRows(in visibleRange: ClosedRange<Int>?) {
        guard let visibleRange else {
            entries.removeAll(keepingCapacity: true)
            return
        }
        entries = entries.filter { visibleRange.contains($0.key) }
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }
}
#endif
