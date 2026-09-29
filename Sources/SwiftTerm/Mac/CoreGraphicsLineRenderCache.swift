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
/// Key by line identity rather than row: DECSTBM moves intact lines between
/// rows. Row-dependent render state (Kitty placeholders) must still be rebuilt.
struct CoreGraphicsLineRenderCache<Value> {
    struct Entry {
        let line: BufferLine
        let row: Int
        let generation: UInt64
        let cols: Int
        let reusableAcrossRows: Bool
        let value: Value
    }

    private(set) var entries: [ObjectIdentifier: Entry] = [:]

    var count: Int { entries.count }

    func value(forRow row: Int, line: BufferLine, cols: Int) -> Value? {
        guard let entry = entries[ObjectIdentifier(line)],
              entry.line === line,
              entry.generation == line.generation,
              entry.cols == cols,
              entry.reusableAcrossRows || entry.row == row
        else {
            return nil
        }
        return entry.value
    }

    mutating func insert(_ value: Value, forRow row: Int, line: BufferLine, cols: Int,
                         reusableAcrossRows: Bool = true) {
        entries[ObjectIdentifier(line)] = Entry(line: line,
                             row: row,
                             generation: line.generation,
                             cols: cols,
                             reusableAcrossRows: reusableAcrossRows,
                             value: value)
    }

    mutating func retainLines(_ visibleLines: [BufferLine]) {
        guard !visibleLines.isEmpty else {
            entries.removeAll(keepingCapacity: true)
            return
        }
        let visibleIDs = Set(visibleLines.map { ObjectIdentifier($0) })
        entries = entries.filter { visibleIDs.contains($0.key) }
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }
}
#endif
