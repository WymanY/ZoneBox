import AppKit
import AVFoundation

/// A click-through presentation surface for a captured foreign window.
/// The panel owns only rendering; PinCenter remains the source of truth for
/// visibility, placement, and stacking.
@MainActor
final class PinMirrorPanel: NSPanel {
    private let mirrorView: PinMirrorView

    var renderer: AVSampleBufferVideoRenderer {
        mirrorView.displayLayer.sampleBufferRenderer
    }

    init() {
        mirrorView = PinMirrorView(frame: .zero)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        contentView = mirrorView
        orderOut(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `reorder` is separated from placement because `orderFrontRegardless()`
    /// is a WindowServer round-trip, and the watchdog re-places panels far more
    /// often than the stacking actually needs fixing.
    func place(frame: CGRect, reorder: Bool) {
        let current = self.frame
        let moved = abs(current.origin.x - frame.origin.x) >= 0.5
            || abs(current.origin.y - frame.origin.y) >= 0.5
            || abs(current.size.width - frame.size.width) >= 0.5
            || abs(current.size.height - frame.size.height) >= 0.5
        if moved { setFrame(frame, display: false) }
        if reorder || !isVisible { orderFrontRegardless() }
    }
}

@MainActor
private final class PinMirrorView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor

        displayLayer.backgroundColor = NSColor.clear.cgColor
        displayLayer.videoGravity = .resize
        displayLayer.preventsDisplaySleepDuringVideoPlayback = false
        layer?.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}
