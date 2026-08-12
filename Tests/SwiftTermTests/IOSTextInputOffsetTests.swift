import XCTest
@testable import SwiftTerm

final class IOSTextInputOffsetTests: XCTestCase {
    func testTextInputRangeAcceptsUTF16EndOffsetForThaiInput() {
        let text = "ฟหกดเ้"
        XCTAssertEqual(text.count, 5)
        XCTAssertEqual(text.textInputUTF16Count, 6)

        let stringRange = text.textInputRange(startUTF16Offset: 6, endUTF16Offset: 6)

        XCTAssertEqual(String(text[stringRange]), "")
        XCTAssertEqual(text.textInputUTF16Offset(of: stringRange.lowerBound), 6)
    }

    func testFullRangeUsesUTF16OffsetsForThaiInput() {
        let text = "ฟหกดเ้"
        let range = text.textInputRange(startUTF16Offset: 0, endUTF16Offset: 6)

        XCTAssertEqual(String(text[range]), text)
    }

    func testDeleteRangeBeforeUTF16OffsetKeepsThaiClusterTogether() {
        let text = "ฟหกดเ้"
        let range = text.textInputCharacterRange(beforeUTF16Offset: 6)

        XCTAssertEqual(range.map { String(text[$0]) }, "เ้")
        XCTAssertEqual(range.map { text.textInputUTF16Offset(of: $0.lowerBound) }, 4)
    }

    func testValidTextPositionOffsetDoesNotClampPastDocumentBounds() {
        let text = "abcdef"

        XCTAssertEqual(text.textInputOffsetIfValid(3, advancedByUTF16Distance: -3), 0)
        XCTAssertEqual(text.textInputOffsetIfValid(3, advancedByUTF16Distance: 3), 6)
        XCTAssertNil(text.textInputOffsetIfValid(3, advancedByUTF16Distance: -4))
        XCTAssertNil(text.textInputOffsetIfValid(3, advancedByUTF16Distance: 4))
    }

    func testValidTextPositionOffsetRejectsInvalidStartAndOverflow() {
        let text = "abcdef"

        XCTAssertNil(text.textInputOffsetIfValid(-1, advancedByUTF16Distance: 1))
        XCTAssertNil(text.textInputOffsetIfValid(7, advancedByUTF16Distance: -1))
        XCTAssertNil(text.textInputOffsetIfValid(1, advancedByUTF16Distance: Int.max))
        XCTAssertNil(text.textInputOffsetIfValid(1, advancedByUTF16Distance: Int.min))
    }

    func testValidTextPositionOffsetKeepsUnicodeBoundaries() {
        let text = "a😀b"

        XCTAssertEqual(text.textInputUTF16Count, 4)
        XCTAssertEqual(text.textInputOffsetIfValid(1, advancedByUTF16Distance: 1), 3)
        XCTAssertEqual(text.textInputOffsetIfValid(3, advancedByUTF16Distance: -1), 1)
        XCTAssertNil(text.textInputOffsetIfValid(2, advancedByUTF16Distance: 0))
    }

#if canImport(UIKit)
    func testTextRangeFullRangeUsesUTF16OffsetsForThaiInput() {
        let text = "ฟหกดเ้"
        let range = TextRange(from: TextPosition(offset: 0), to: TextPosition(offset: 6))

        XCTAssertEqual(String(text[range.fullRange(in: text)]), text)
    }

    @MainActor
    func testTextPositionQueriesReturnNilOutsideDocument() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.textInputStorage = "abcdef"

        XCTAssertNil(view.position(from: TextPosition(offset: 3), offset: -300))
        XCTAssertNil(view.position(from: TextPosition(offset: 3), offset: 300))
        XCTAssertEqual(
            (view.position(from: TextPosition(offset: 3), offset: 3) as? TextPosition)?.offset,
            6
        )
    }

    @MainActor
    func testDirectionalTextPositionQueriesRespectDirection() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.textInputStorage = "abcdef"
        let position = TextPosition(offset: 3)

        XCTAssertEqual(
            (view.position(from: position, in: .left, offset: 2) as? TextPosition)?.offset,
            1
        )
        XCTAssertEqual(
            (view.position(from: position, in: .right, offset: 2) as? TextPosition)?.offset,
            5
        )
    }
#endif
}
