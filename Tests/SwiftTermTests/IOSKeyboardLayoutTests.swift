#if os(iOS) || os(visionOS)
import Testing
import UIKit
@testable import SwiftTerm

@Suite("iOS extended keyboard layout", .serialized)
@MainActor
struct IOSKeyboardLayoutTests {
    @Test("Chord row fits phone, landscape and tablet widths without losing existing keys",
          arguments: [320.0, 375.0, 420.0, 852.0, 1024.0])
    func layout(width: Double) throws {
        let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: width, height: 300))
        let keyboard = KeyboardView(
            frame: CGRect(x: 0, y: 0, width: width, height: KeyboardView.minimumHeight),
            terminalView: terminal)
        let buttons = keyboard.views.compactMap { $0 as? UIButton }
        #expect(buttons.count == 36)
        #expect(buttons.prefix(6).map { $0.title(for: .normal) } ==
                ["⇧←", "⇧→", "⇧↑", "⇧↓", "⇧Tab", "⇧Enter"])
        #expect(buttons.prefix(6).allSatisfy { $0.accessibilityLabel?.hasPrefix("Shift ") == true })
        #expect(buttons.dropFirst(6).prefix(10).map { $0.title(for: .normal) } ==
                (1...10).map { "F\($0)" })
        for title in ["home", "end", "ins", "pgup", "pgdn", "[", "\\"] {
            #expect(buttons.contains { $0.title(for: .normal) == title })
        }
        for (index, button) in buttons.enumerated() {
            #expect(keyboard.bounds.contains(button.frame))
            #expect(button.frame.height >= 36)
            for other in buttons.dropFirst(index + 1) {
                #expect(!button.frame.intersects(other.frame))
            }
        }
    }

    @Test("Repeated layout does not retain old buttons")
    func rebuild() {
        let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: 420, height: 300))
        let keyboard = KeyboardView(
            frame: CGRect(x: 0, y: 0, width: 420, height: KeyboardView.minimumHeight),
            terminalView: terminal)
        weak var oldButton = keyboard.views.first
        for width in [320.0, 420.0, 852.0, 375.0] {
            keyboard.bounds.size.width = width
            keyboard.buildUI()
            #expect(keyboard.views.count == 36)
            #expect(keyboard.subviews.count == 36)
        }
        #expect(oldButton == nil)
    }
}
#endif
