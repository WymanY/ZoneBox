import AppKit
import ZoneBoxCore

@MainActor
final class ShortcutPanelController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: ShortcutWindow?
    private var documentStack: NSStackView?

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
    }

    var isKey: Bool { window?.isKeyWindow == true }
    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if window == nil { window = makeWindow() }
        rebuild()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        documentStack = nil
        runtime.shortcutPanelDidClose()
    }

    func applyLanguage() {
        window?.title = L10n.text(.shortcutsTitle)
        rebuild()
    }

    private func makeWindow() -> ShortcutWindow {
        let window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.shortcutsTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 3)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()

        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.wantsLayer = true
        window.contentView = effect

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let document = NSStackView()
        document.orientation = .vertical
        document.alignment = .width
        document.spacing = 16
        document.translatesAutoresizingMaskIntoConstraints = false
        document.edgeInsets = NSEdgeInsets(top: 8, left: 22, bottom: 22, right: 22)
        documentStack = document

        let clip = FlippedView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(document)
        scroll.documentView = clip

        effect.addSubview(scroll)
        let topAnchor = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? effect.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            clip.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return window
    }

    private func rebuild() {
        guard let document = documentStack else { return }
        for view in document.arrangedSubviews {
            document.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        document.addArrangedSubview(makeHeader())

        let columns = NSStackView()
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 14
        columns.addArrangedSubview(makeColumn(surfaces: [.global, .application]))
        columns.addArrangedSubview(makeColumn(surfaces: [.editor, .snap]))
        document.addArrangedSubview(columns)

        document.addArrangedSubview(makeFooter())
    }

    private func makeHeader() -> NSView {
        let iconWell = SymbolWell(symbol: "keyboard", tint: .controlAccentColor)

        let title = NSTextField(labelWithString: L10n.text(.shortcutsTitle))
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: L10n.text(.shortcutsSubtitle))
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let titles = NSStackView(views: [iconWell, textStack])
        titles.orientation = .horizontal
        titles.alignment = .centerY
        titles.spacing = 10

        let esc = KeyCapView(symbol: "esc")
        let header = NSStackView(views: [titles, NSView(), esc])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        titles.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return header
    }

    private func makeColumn(surfaces: [ShortcutSurface]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        let grouped = Dictionary(uniqueKeysWithValues: ShortcutCatalog.grouped(from: runtime.settings).map { ($0.surface, $0.items) })
        for surface in surfaces {
            let items = grouped[surface] ?? []
            stack.addArrangedSubview(
                ShortcutSectionView(
                    title: L10n.text(surface.titleKey),
                    symbol: surface.symbolName,
                    rows: displayRows(items)
                )
            )
        }
        return stack
    }

    private func makeFooter() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let note = NSTextField(wrappingLabelWithString: L10n.text(.shortcutsVoiceOverNote))
        note.font = .systemFont(ofSize: 11, weight: .regular)
        note.textColor = .secondaryLabelColor
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, note])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        let chrome = RoundedFillView()
        chrome.fillAlpha = 0.06
        chrome.cornerRadius = 10
        chrome.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: chrome.topAnchor),
            row.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: chrome.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: chrome.bottomAnchor),
        ])
        return chrome
    }

    private func displayRows(_ items: [ShortcutSpec]) -> [(title: String, caps: [String])] {
        var rows: [(String, [String])] = []
        var index = 0
        while index < items.count {
            let item = items[index]
            if item.id.hasPrefix("snapZone"), case .chord(let chord) = item.binding {
                let modifiers = Array(chord.displayCaps.dropLast())
                rows.append((L10n.text(.shortcutSnapZones), modifiers + ["1–9"]))
                while index < items.count, items[index].id.hasPrefix("snapZone") {
                    index += 1
                }
                continue
            }
            rows.append((item.title(language: LanguageCenter.language), caps(for: item)))
            index += 1
        }
        return rows
    }

    private func caps(for item: ShortcutSpec) -> [String] {
        switch item.binding {
        case .chord(let chord):
            return chord.displayCaps
        case .gesture(let key):
            switch key {
            case .shortcutGestureScroll:
                return [L10n.text(.shortcutGestureScroll)]
            case .shortcutGestureHorizontalScroll:
                return [L10n.text(.shortcutGestureHorizontalScroll)]
            case .shortcutGestureShiftDrag:
                return ["⇧", L10n.text(.shortcutGestureDrag)]
            case .shortcutGestureRightClick:
                return [L10n.text(.shortcutGestureRightClick)]
            default:
                return [L10n.text(key)]
            }
        }
    }
}

private extension ShortcutSurface {
    var symbolName: String {
        switch self {
        case .global: "globe"
        case .editor: "rectangle.dashed"
        case .snap: "rectangle.split.3x1"
        case .application: "macwindow"
        }
    }
}

private final class ShortcutWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private class RoundedFillView: NSView {
    var fillAlpha: CGFloat = 0.08
    var cornerRadius: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill = dark ? NSColor.white.withAlphaComponent(fillAlpha) : NSColor.black.withAlphaComponent(fillAlpha)
        let border = dark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.08)
        layer?.cornerRadius = cornerRadius
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = border.cgColor
    }
}

private final class SymbolWell: NSView {
    init(symbol: String, tint: NSColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        image.contentTintColor = tint
        addSubview(image)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32),
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
    }
}

private final class ShortcutSectionView: RoundedFillView {
    init(title: String, symbol: String, rows: [(title: String, caps: [String])]) {
        super.init(frame: .zero)
        fillAlpha = 0.05
        cornerRadius = 14

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        let header = NSStackView(views: [icon, heading])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 11, left: 12, bottom: 2, right: 12)

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 0
        for (index, row) in rows.enumerated() {
            if index > 0 {
                list.addArrangedSubview(HairlineView())
            }
            list.addArrangedSubview(ShortcutRowView(title: row.title, caps: row.caps))
        }

        let column = NSStackView(views: [header, list])
        column.orientation = .vertical
        column.alignment = .width
        column.spacing = 4
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

private final class ShortcutRowView: NSView {
    private var hover = false { didSet { needsDisplay = true } }

    init(title: String, caps: [String]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let keys = NSStackView(views: caps.map { KeyCapView(symbol: $0) })
        keys.orientation = .horizontal
        keys.alignment = .centerY
        keys.spacing = 4
        keys.setHuggingPriority(.required, for: .horizontal)
        keys.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, keys])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if hover {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            (dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

private final class HairlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let line = NSRect(x: 12, y: 0, width: max(0, bounds.width - 24), height: 1)
        NSColor.separatorColor.withAlphaComponent(0.7).setFill()
        line.fill()
    }
}

private final class KeyCapView: NSView {
    init(symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = true

        let font = Self.capFont
        let label = NSTextField(labelWithString: symbol)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.alignment = .center
        label.textColor = .labelColor
        label.isSelectable = false
        addSubview(label)

        let textSize = (symbol as NSString).size(withAttributes: [.font: font])
        let width = max(22, ceil(textSize.width) + 10)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        } else {
            layer?.backgroundColor = NSColor.white.cgColor
            layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
            layer?.shadowOpacity = 0
        }
    }

    private static var capFont: NSFont {
        let base = NSFont.systemFont(ofSize: 11, weight: .semibold)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: rounded, size: 11) ?? base
        }
        return base
    }
}
