#if os(macOS) || os(iOS) || os(visionOS)
import QuartzCore

/// Keep Core Animation's last completed backing store while DEC 2026 is active.
/// Blocking only updateDisplay is insufficient: scrolling, layout and window
/// exposure can ask the native layer to draw independently of that scheduler.
/// Blocking only draw is also insufficient: UIKit may already have cleared its
/// drawing context. Defer display *before* allocating/clearing a new backing store.
/// No terminal-history copy or per-frame bitmap is needed.
final class TerminalDisplayLayer: CALayer {
    weak var terminalView: TerminalView?

    override func display() {
        guard terminalView?.terminal?.synchronizedOutputActive != true else { return }
        super.display()
    }
}
#endif
