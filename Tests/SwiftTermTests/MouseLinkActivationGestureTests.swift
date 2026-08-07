#if os(macOS)
import Testing
@testable import SwiftTerm

@Suite("macOS link activation gestures")
struct MouseLinkActivationGestureTests {
    @Test("Single click without dragging may activate")
    func singleClick() {
        var state = MouseLinkActivationGestureState()

        let cancelsPending = state.mouseDown(clickCount: 1)
        let activatesLink = state.mouseUp(clickCount: 1)

        #expect(!cancelsPending)
        #expect(activatesLink)
    }

    @Test("Dragging suppresses activation and resets on mouse up")
    func drag() {
        var state = MouseLinkActivationGestureState()

        _ = state.mouseDown(clickCount: 1)
        state.mouseDragged()
        let activatesDraggedLink = state.mouseUp(clickCount: 1)
        #expect(!activatesDraggedLink)
        #expect(!state.didDrag)

        _ = state.mouseDown(clickCount: 1)
        let activatesNextLink = state.mouseUp(clickCount: 1)
        #expect(activatesNextLink)
    }

    @Test("Later clicks cancel the staged first click", arguments: [2, 3])
    func multipleClicks(clickCount: Int) {
        var state = MouseLinkActivationGestureState()

        _ = state.mouseDown(clickCount: 1)
        let stagesFirstClick = state.mouseUp(clickCount: 1)
        let cancelsFirstClick = state.mouseDown(clickCount: clickCount)
        let activatesMultiClick = state.mouseUp(clickCount: clickCount)

        #expect(stagesFirstClick)
        #expect(cancelsFirstClick)
        #expect(!activatesMultiClick)
    }
}
#endif
