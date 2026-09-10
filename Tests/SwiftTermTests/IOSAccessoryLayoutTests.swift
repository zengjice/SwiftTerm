#if os(iOS) || os(visionOS)
import Testing
import UIKit
@testable import SwiftTerm

@Suite("iOS accessory layout", .serialized)
@MainActor
struct IOSAccessoryLayoutTests {
    @Test("Default configuration keeps the existing keyboard")
    func defaultConfiguration() throws {
        let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: 1024, height: 300))
        let accessory = try #require(terminal.inputAccessoryView as? TerminalAccessory)
        accessory.setupUI()

        #expect(hasButton(#selector(TerminalAccessory.left(_:)), in: accessory))
        #expect(hasButton(#selector(TerminalAccessory.right(_:)), in: accessory))
        #expect(hasButton(#selector(TerminalAccessory.f1(_:)), in: accessory))
    }

    @Test("Compact configuration survives portrait, landscape and tablet widths",
          arguments: [320.0, 375.0, 420.0, 852.0, 1024.0])
    func compactLayout(width: Double) throws {
        let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: 420, height: 300))
        let accessory = try #require(terminal.inputAccessoryView as? TerminalAccessory)
        accessory.configuration = .init(showsHorizontalArrows: false,
                                        showsFunctionKeys: false, buttonHeight: 32)
        accessory.controlModifier = true
        accessory.bounds.size.width = width
        accessory.layoutSubviews()

        #expect(accessory.bounds.height == 40)
        #expect(accessory.views.count == 11)
        #expect(!hasButton(#selector(TerminalAccessory.left(_:)), in: accessory))
        #expect(!hasButton(#selector(TerminalAccessory.right(_:)), in: accessory))
        #expect(!accessory.views.compactMap { $0 as? UIButton }.contains {
            $0.title(for: .normal)?.hasPrefix("F") == true
        })
        #expect(hasButton(#selector(TerminalAccessory.up(_:)), in: accessory))
        #expect(hasButton(#selector(TerminalAccessory.down(_:)), in: accessory))
        #expect(accessory.controlButton?.isSelected == true)
        #expect(accessory.touchButton.isSelected == !terminal.allowMouseReporting)

        for (index, view) in accessory.views.enumerated() {
            #expect(view.frame.height == 32)
            #expect(accessory.bounds.contains(view.frame))
            if index > 0 {
                #expect(abs(view.frame.minX - accessory.views[index - 1].frame.maxX - 4) < 0.001)
            }
        }
        #expect(abs((accessory.views.last?.frame.maxX ?? 0) - (width - 2)) < 0.001)
    }

    @Test("Resetting configuration restores the original accessory height")
    func restoreDefaults() throws {
        let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: 1024, height: 300))
        let accessory = try #require(terminal.inputAccessoryView as? TerminalAccessory)
        let originalHeight = accessory.bounds.height
        accessory.configuration = .init(showsHorizontalArrows: false,
                                        showsFunctionKeys: false, buttonHeight: 32)
        accessory.configuration = .init()

        #expect(accessory.bounds.height == originalHeight)
        #expect(hasButton(#selector(TerminalAccessory.left(_:)), in: accessory))
        #expect(hasButton(#selector(TerminalAccessory.f1(_:)), in: accessory))
    }

    private func hasButton(_ action: Selector, in accessory: TerminalAccessory) -> Bool {
        accessory.views.compactMap { $0 as? UIButton }.contains {
            $0.actions(forTarget: accessory, forControlEvent: .touchDown)?
                .contains(NSStringFromSelector(action)) == true
        }
    }
}
#endif
