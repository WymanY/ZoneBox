import AppKit
import ZoneBoxCore

enum PinIconState {
    case pin
    case unpin
}

enum PinIconArtwork {
    static func image(state: PinIconState, size: CGFloat) -> NSImage {
        let symbolName = state == .pin ? "pin.fill" : "pin.slash.fill"
        let symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: size * (state == .pin ? 0.78 : 0.72),
            weight: .bold
        ).applying(.init(paletteColors: [.black]))
        guard let symbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration) else {
            return NSImage(size: NSSize(width: size, height: size))
        }

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            let drawRect = NSRect(
                x: rect.midX - symbol.size.width / 2,
                y: rect.midY - symbol.size.height / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: drawRect)

            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class PinButtonPanel: NSPanel {
    private let button = NSButton()
    private let effectView: PinMaterialView
    private let panelSize: CGFloat
    private var badgeMode = false
    var onClick: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(size: CGFloat) {
        panelSize = size
        effectView = PinMaterialView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = size / 2
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.onHover = { [weak self] hovered in
            guard let self, self.badgeMode else { return }
            self.setBadgeHovered(hovered)
        }

        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.refusesFirstResponder = true
        button.target = self
        button.action = #selector(clicked)
        button.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            button.topAnchor.constraint(equalTo: effectView.topAnchor),
            button.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        contentView = effectView
        orderOut(nil)
    }

    func configure(state: PinIconState, toolTip: String) {
        let isBadge = state == .unpin
        badgeMode = isBadge
        let glyphSize: CGFloat = isBadge ? 14 : 15.5
        let fillColor = isBadge ? NSColor.systemRed : NSColor.systemBlue
        button.contentTintColor = .white
        button.image = PinIconArtwork.image(state: state, size: glyphSize)
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        effectView.layer?.backgroundColor = fillColor.cgColor
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
        alphaValue = 1
    }

    func show(frame: CGRect, reorder: Bool = true) {
        let target = NSRect(origin: frame.origin, size: NSSize(width: panelSize, height: panelSize))
        if abs(self.frame.origin.x - target.origin.x) >= 0.5
            || abs(self.frame.origin.y - target.origin.y) >= 0.5
            || self.frame.size != target.size
        {
            setFrame(target, display: false)
        }
        if reorder || !isVisible { orderFrontRegardless() }
    }

    func setBadgeHovered(_ hovered: Bool) {
        alphaValue = hovered ? 1 : 0.92
    }

    @objc private func clicked() {
        onClick?()
    }
}

private final class PinMaterialView: NSView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        tracking = next
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

enum PinPanelPlacement {
    static func appKitRect(
        fromAX rectAX: CGRect,
        windowFrameAX: CGRect,
        primaryFlipHeight: CGFloat,
        clampToVisibleScreen: Bool
    ) -> CGRect {
        var rect = CoordinateConverter.appKitRect(fromAX: rectAX, primaryFlipHeight: primaryFlipHeight)
        guard clampToVisibleScreen, !NSScreen.screens.isEmpty else { return rect }

        let windowAppKit = CoordinateConverter.appKitRect(
            fromAX: windowFrameAX,
            primaryFlipHeight: primaryFlipHeight
        )
        let screen = NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(windowAppKit).area < rhs.frame.intersection(windowAppKit).area
        } ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        rect.origin.x = min(max(rect.minX, visible.minX), max(visible.maxX - rect.width, visible.minX))
        rect.origin.y = min(max(rect.minY, visible.minY), max(visible.maxY - rect.height, visible.minY))
        return rect
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(width, 0) * max(height, 0)
    }
}
