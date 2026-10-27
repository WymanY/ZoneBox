import AppKit

enum ConsoleChrome {
    static let contentWidth: CGFloat = 372

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func brandBlue(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.40, green: 0.64, blue: 1, alpha: 1)
            : NSColor(srgbRed: 0.16, green: 0.42, blue: 0.96, alpha: 1)
    }

    /// Fill behind white text; stays deep in dark mode where `brandBlue` is lightened for text.
    static func primaryFill(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.20, green: 0.46, blue: 0.96, alpha: 1)
            : brandBlue(dark: false)
    }

    static func warning(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 1, green: 0.66, blue: 0.26, alpha: 1)
            : NSColor(srgbRed: 0.85, green: 0.45, blue: 0.0, alpha: 1)
    }

    static func panelTint(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.115, green: 0.118, blue: 0.13, alpha: 0.9)
            : NSColor(srgbRed: 0.955, green: 0.958, blue: 0.966, alpha: 0.94)
    }

    static func surface(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.06) : .white
    }

    static func opaqueSurface(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0.17, green: 0.172, blue: 0.183, alpha: 1) : .white
    }

    static func opaquePanel(dark: Bool) -> NSColor {
        panelTint(dark: dark).withAlphaComponent(1)
    }

    static func surfaceBorder(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.09) : NSColor.black.withAlphaComponent(0.08)
    }

    static func hoverWash(dark: Bool) -> NSColor {
        brandBlue(dark: dark).withAlphaComponent(dark ? 0.14 : 0.07)
    }

    static func pressedWash(dark: Bool) -> NSColor {
        brandBlue(dark: dark).withAlphaComponent(dark ? 0.24 : 0.14)
    }

    static func hoverBorder(dark: Bool) -> NSColor {
        brandBlue(dark: dark).withAlphaComponent(dark ? 0.7 : 0.55)
    }

    static func screenPlate(dark: Bool) -> NSColor {
        dark ? NSColor.black.withAlphaComponent(0.28) : NSColor(srgbRed: 0.925, green: 0.932, blue: 0.945, alpha: 1)
    }

    static func zoneActive(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.33, green: 0.56, blue: 0.98, alpha: 1)
            : NSColor(srgbRed: 0.22, green: 0.48, blue: 0.97, alpha: 1)
    }

    static func zoneIdle(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.40, green: 0.43, blue: 0.50, alpha: 1)
            : NSColor(srgbRed: 0.53, green: 0.58, blue: 0.66, alpha: 1)
    }

    /// Filled badge symbols get a white glyph so the check, arrow or exclamation stays visible.
    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        let palette: [NSColor] = name.hasSuffix(".fill") ? [.white, color] : [color]
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: palette))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }
}

/// Borderless button drawn entirely by ZoneBox so hover and press states read clearly on the
/// translucent menu panel.
final class ConsoleButton: NSButton {
    enum Role {
        case plain
        case accent
        case surface
        case primary
        case tinted
        case warning
        case keycap
    }

    var role: Role { didSet { needsDisplay = true } }
    var symbolName: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var trailingSymbolName: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var fontSize: CGFloat = 12 { didSet { invalidateIntrinsicContentSize() } }
    var fontWeight: NSFont.Weight = .medium { didSet { invalidateIntrinsicContentSize() } }
    var controlHeight: CGFloat = 24 { didSet { invalidateIntrinsicContentSize() } }
    var horizontalPadding: CGFloat = 8 { didSet { invalidateIntrinsicContentSize() } }
    var contentAlignment: NSTextAlignment = .center
    /// Non-interactive buttons keep full-strength text but show no hover or press state.
    var isInteractive = true {
        didSet {
            if !isInteractive { hovering = false }
            needsDisplay = true
        }
    }
    var titleColorOverride: NSColor? { didSet { needsDisplay = true } }

    private var hovering = false {
        didSet { if oldValue != hovering { needsDisplay = true } }
    }
    private var hoverArea: NSTrackingArea?

    init(role: Role, title: String = "", symbol: String? = nil, target: AnyObject? = nil, action: Selector? = nil) {
        self.role = role
        self.symbolName = symbol
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .shadowlessSquare
        imagePosition = .noImage
        refusesFirstResponder = true
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        if title.isEmpty, symbol != nil { horizontalPadding = 0 }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var title: String {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    override var isHidden: Bool {
        didSet { if isHidden { hovering = false } }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hovering = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = isInteractive && isEnabled
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        super.mouseDown(with: event)
        let point = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        hovering = bounds.contains(point)
    }

    private var iconOnly: Bool { title.isEmpty && symbolName != nil && trailingSymbolName == nil }

    private var labelFont: NSFont { .systemFont(ofSize: fontSize, weight: fontWeight) }

    private var symbolSize: CGFloat { iconOnly ? fontSize + 1 : fontSize - 1 }

    override var intrinsicContentSize: NSSize {
        if iconOnly { return NSSize(width: controlHeight, height: controlHeight) }
        var width = horizontalPadding * 2
        let text = (title as NSString).size(withAttributes: [.font: labelFont]).width
        width += ceil(text)
        if symbolName != nil { width += symbolSize + 5 }
        if trailingSymbolName != nil { width += 4 + 9 }
        return NSSize(width: ceil(width), height: controlHeight)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    private var radius: CGFloat {
        switch role {
        case .primary, .tinted, .warning: return bounds.height / 2
        case .keycap: return 5
        case .plain, .accent, .surface: return min(7, bounds.height / 2)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ConsoleChrome.isDark(effectiveAppearance)
        let active = isInteractive && isEnabled
        let pressed = active && isHighlighted
        let hot = active && hovering
        let blue = ConsoleChrome.brandBlue(dark: dark)
        let orange = ConsoleChrome.warning(dark: dark)

        var fill: NSColor?
        var border: NSColor?
        var foreground: NSColor
        switch role {
        case .plain:
            foreground = hot || pressed ? .labelColor : .secondaryLabelColor
            if pressed { fill = NSColor.labelColor.withAlphaComponent(0.12) }
            else if hot { fill = NSColor.labelColor.withAlphaComponent(0.07) }
        case .accent:
            foreground = blue
            if pressed { fill = ConsoleChrome.pressedWash(dark: dark) }
            else if hot { fill = ConsoleChrome.hoverWash(dark: dark) }
        case .surface:
            foreground = .labelColor
            fill = pressed
                ? ConsoleChrome.pressedWash(dark: dark)
                : (dark ? NSColor.white.withAlphaComponent(hot ? 0.16 : 0.10) : NSColor.white)
            border = hot || pressed ? ConsoleChrome.hoverBorder(dark: dark) : ConsoleChrome.surfaceBorder(dark: dark)
        case .primary:
            foreground = .white
            let base = ConsoleChrome.primaryFill(dark: dark)
            if pressed { fill = base.blended(withFraction: 0.18, of: .black) }
            else if hot { fill = base.blended(withFraction: 0.12, of: .white) }
            else { fill = base }
        case .tinted:
            foreground = blue
            fill = blue.withAlphaComponent(pressed ? 0.26 : hot ? 0.19 : 0.12)
        case .warning:
            foreground = orange
            fill = orange.withAlphaComponent(pressed ? 0.26 : hot ? 0.19 : 0.12)
        case .keycap:
            foreground = hot || pressed ? .labelColor : .secondaryLabelColor
            fill = NSColor.labelColor.withAlphaComponent(pressed ? 0.14 : hot ? 0.10 : 0.06)
            border = NSColor.labelColor.withAlphaComponent(0.10)
        }
        if let titleColorOverride { foreground = titleColorOverride }
        if !isEnabled { foreground = foreground.withAlphaComponent(0.4) }

        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if let fill {
            fill.setFill()
            shape.fill()
        }
        if let border {
            border.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        drawContent(color: foreground)
    }

    private func drawContent(color: NSColor) {
        let leading = symbolName.flatMap {
            ConsoleChrome.symbol($0, size: symbolSize, weight: iconOnly ? .semibold : .medium, color: color)
        }
        let trailing = trailingSymbolName.flatMap {
            ConsoleChrome.symbol($0, size: 8, weight: .bold, color: NSColor.secondaryLabelColor)
        }
        if iconOnly, let leading {
            draw(leading, centeredIn: bounds)
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let leadingWidth: CGFloat = leading == nil ? 0 : symbolSize + 5
        let trailingWidth: CGFloat = trailing == nil ? 0 : 4 + 9
        let available = max(0, bounds.width - horizontalPadding * 2 - leadingWidth - trailingWidth)
        let textWidth = min(ceil(textSize.width), available)
        let total = leadingWidth + textWidth + trailingWidth
        var x = contentAlignment == .left
            ? horizontalPadding
            : ((bounds.width - total) / 2).rounded()
        if let leading {
            draw(leading, centeredIn: NSRect(x: x, y: 0, width: symbolSize, height: bounds.height))
            x += leadingWidth
        }
        let textRect = NSRect(
            x: x,
            y: ((bounds.height - textSize.height) / 2).rounded(),
            width: textWidth + 1,
            height: ceil(textSize.height)
        )
        (title as NSString).draw(in: textRect, withAttributes: attributes)
        x += textWidth
        if let trailing {
            draw(trailing, centeredIn: NSRect(x: x + 4, y: 0, width: 9, height: bounds.height))
        }
    }

    private func draw(_ image: NSImage, centeredIn rect: NSRect) {
        let size = image.size
        let origin = NSPoint(
            x: (rect.midX - size.width / 2).rounded(),
            y: (rect.midY - size.height / 2).rounded()
        )
        image.draw(in: NSRect(origin: origin, size: size))
    }
}

/// Base for clickable cards and rows: tracks hover, shows a pressed state while the mouse is
/// down, and fires on mouse-up inside like a native control.
class ConsoleInteractiveView: NSView {
    private(set) var isHovering = false
    private(set) var isPressed = false
    private var hoverArea: NSTrackingArea?

    func interactionStateDidChange() {
        needsDisplay = true
    }

    func performPrimaryAction() {}

    func showContextMenu(with event: NSEvent) {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setHovering(false)
        setPressed(false)
    }

    override func mouseEntered(with event: NSEvent) {
        reconcileHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    func reconcileHoverState() {
        guard let window, !isHiddenOrHasHiddenAncestor else {
            setHovering(false)
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovering(bounds.contains(point) && visibleRect.contains(point))
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setPressed(bounds.contains(point) && visibleRect.contains(point))
    }

    override func mouseUp(with event: NSEvent) {
        let fire = isPressed
        setPressed(false)
        if fire { performPrimaryAction() }
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(with: event)
    }

    override func accessibilityPerformPress() -> Bool {
        performPrimaryAction()
        return true
    }

    private func setHovering(_ value: Bool) {
        guard isHovering != value else { return }
        isHovering = value
        interactionStateDidChange()
    }

    private func setPressed(_ value: Bool) {
        guard isPressed != value else { return }
        isPressed = value
        interactionStateDidChange()
    }
}

final class ThinOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        8
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

final class ScrollAwareClipView: NSClipView {
    var onBoundsChange: (() -> Void)?
    private var reportedBoundsOrigin: NSPoint?

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(newOrigin)
        reportBoundsOriginChange()
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: newOrigin)
        reportBoundsOriginChange()
    }

    private func reportBoundsOriginChange() {
        let origin = bounds.origin
        guard reportedBoundsOrigin != origin else { return }
        reportedBoundsOrigin = origin
        onBoundsChange?()
    }
}

/// Gradient laid over the bottom of a scroll view to show that more content is below.
final class ConsoleScrollFade: NSView {
    var color: (Bool) -> NSColor

    init(color: @escaping (Bool) -> NSColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let base = color(ConsoleChrome.isDark(effectiveAppearance))
        NSGradient(starting: base.withAlphaComponent(0), ending: base)?.draw(in: bounds, angle: -90)
    }

    static func shouldShow(for scroll: NSScrollView) -> Bool {
        guard let document = scroll.documentView else { return false }
        let visible = scroll.contentView.bounds
        let flipped = document.isFlipped
        let remaining = flipped
            ? document.frame.height - visible.maxY
            : visible.minY
        return remaining > 2
    }
}
