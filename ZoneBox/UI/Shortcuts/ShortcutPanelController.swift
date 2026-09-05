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

    @objc private func handleCustomizeClicked() {
        runtime.openKeyboardSettings()
    }

    private func makeWindow() -> ShortcutWindow {
        let window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.shortcutsTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 700, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 3)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()

        // Match SettingsWindowController content visual effect
        let content = NSVisualEffectView()
        content.material = .contentBackground
        content.blendingMode = .withinWindow
        content.state = .followsWindowActiveState
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let clip = FlippedView()
        clip.translatesAutoresizingMaskIntoConstraints = false

        let document = NSStackView()
        document.orientation = .vertical
        document.alignment = .leading
        document.spacing = 16
        document.translatesAutoresizingMaskIntoConstraints = false
        documentStack = document

        clip.addSubview(document)
        scroll.documentView = clip
        content.addSubview(scroll)

        let topAnchor = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            clip.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            clip.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            clip.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            document.topAnchor.constraint(equalTo: clip.topAnchor, constant: 14),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor, constant: 24),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -24),
            document.bottomAnchor.constraint(equalTo: clip.bottomAnchor, constant: -24),
        ])
        return window
    }

    private func rebuild() {
        guard let document = documentStack else { return }
        for view in document.arrangedSubviews {
            document.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let header = makeHeader()
        document.addArrangedSubview(header)
        header.leadingAnchor.constraint(equalTo: document.leadingAnchor).isActive = true
        header.trailingAnchor.constraint(equalTo: document.trailingAnchor).isActive = true

        let columns = NSStackView()
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 14
        columns.translatesAutoresizingMaskIntoConstraints = false

        let leftColumn = makeColumn(surfaces: [.global, .application])
        let rightColumn = makeColumn(surfaces: [.editor, .snap])

        columns.addArrangedSubview(leftColumn)
        columns.addArrangedSubview(rightColumn)

        document.addArrangedSubview(columns)
        columns.leadingAnchor.constraint(equalTo: document.leadingAnchor).isActive = true
        columns.trailingAnchor.constraint(equalTo: document.trailingAnchor).isActive = true

        let footer = makeFooter()
        document.addArrangedSubview(footer)
        footer.leadingAnchor.constraint(equalTo: document.leadingAnchor).isActive = true
        footer.trailingAnchor.constraint(equalTo: document.trailingAnchor).isActive = true
    }

    private func makeHeader() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconWell = HeaderIconWell(symbol: "keyboard.fill", tint: .controlAccentColor)

        let title = NSTextField(labelWithString: L10n.text(.shortcutsTitle))
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: L10n.text(.shortcutsSubtitle))
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let leftGroup = NSStackView(views: [iconWell, textStack])
        leftGroup.orientation = .horizontal
        leftGroup.alignment = .centerY
        leftGroup.spacing = 12
        leftGroup.translatesAutoresizingMaskIntoConstraints = false

        let customizeButton = NSButton(
            title: L10n.text(.shortcutsCustomize),
            target: self,
            action: #selector(handleCustomizeClicked)
        )
        customizeButton.bezelStyle = .rounded
        customizeButton.controlSize = .small
        customizeButton.font = .systemFont(ofSize: 12, weight: .medium)
        customizeButton.contentTintColor = .controlAccentColor

        let esc = KeyCapView(symbol: "esc")

        let rightGroup = NSStackView(views: [customizeButton, esc])
        rightGroup.orientation = .horizontal
        rightGroup.alignment = .centerY
        rightGroup.spacing = 10
        rightGroup.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(leftGroup)
        container.addSubview(rightGroup)

        NSLayoutConstraint.activate([
            leftGroup.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftGroup.topAnchor.constraint(equalTo: container.topAnchor),
            leftGroup.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            rightGroup.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightGroup.centerYAnchor.constraint(equalTo: leftGroup.centerYAnchor),
            rightGroup.leadingAnchor.constraint(greaterThanOrEqualTo: leftGroup.trailingAnchor, constant: 16),
        ])

        return container
    }

    private func makeColumn(surfaces: [ShortcutSurface]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let grouped = Dictionary(uniqueKeysWithValues: ShortcutCatalog.grouped(from: runtime.settings).map { ($0.surface, $0.items) })
        for surface in surfaces {
            let items = grouped[surface] ?? []
            guard !items.isEmpty else { continue }
            let card = ShortcutSectionCard(
                title: L10n.text(surface.titleKey),
                symbol: surface.symbolName,
                rows: displayRows(items)
            )
            stack.addArrangedSubview(card)
            card.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            card.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        return stack
    }

    private func makeFooter() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let note = NSTextField(wrappingLabelWithString: L10n.text(.shortcutsVoiceOverNote))
        note.font = .systemFont(ofSize: 11, weight: .regular)
        note.textColor = .secondaryLabelColor
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, note])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)

        let surface = AppGroupSurfaceView(cornerRadius: 10)
        surface.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: surface.topAnchor),
            row.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])
        return surface
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

/// Matches SettingsGroupSurfaceView used throughout the Settings window
private class AppGroupSurfaceView: NSVisualEffectView {
    var surfaceCornerRadius: CGFloat

    init(cornerRadius: CGFloat = 11) {
        self.surfaceCornerRadius = cornerRadius
        super.init(frame: .zero)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateColors()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.76).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
            layer?.borderWidth = 0.5
        }
    }
}

private final class HeaderIconWell: NSView {
    private let tint: NSColor

    init(symbol: String, tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        image.contentTintColor = tint
        addSubview(image)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32),
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColors()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = tint.withAlphaComponent(0.12).cgColor
            layer?.borderColor = tint.withAlphaComponent(0.08).cgColor
            layer?.borderWidth = 0.5
        }
    }
}

private final class ShortcutSectionCard: AppGroupSurfaceView {
    init(title: String, symbol: String, rows: [(title: String, caps: [String])]) {
        super.init(cornerRadius: 11)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
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
        header.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 4, right: 14)
        header.translatesAutoresizingMaskIntoConstraints = false

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false

        for (index, row) in rows.enumerated() {
            if index > 0 {
                let sep = CardSeparatorView(inset: 14)
                list.addArrangedSubview(sep)
                sep.leadingAnchor.constraint(equalTo: list.leadingAnchor).isActive = true
                sep.trailingAnchor.constraint(equalTo: list.trailingAnchor).isActive = true
            }
            let rowView = ShortcutRowView(title: row.title, caps: row.caps)
            list.addArrangedSubview(rowView)
            rowView.leadingAnchor.constraint(equalTo: list.leadingAnchor).isActive = true
            rowView.trailingAnchor.constraint(equalTo: list.trailingAnchor).isActive = true
        }

        let column = NSStackView(views: [header, list])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            header.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: column.trailingAnchor),

            list.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: column.trailingAnchor),
        ])
    }
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
        label.alignment = .left
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let keys = NSStackView(views: caps.map { KeyCapView(symbol: $0) })
        keys.orientation = .horizontal
        keys.alignment = .centerY
        keys.spacing = 4
        keys.translatesAutoresizingMaskIntoConstraints = false
        keys.setHuggingPriority(.required, for: .horizontal)
        keys.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(label)
        addSubview(keys)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: keys.leadingAnchor, constant: -10),

            keys.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            keys.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 32),
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
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
    }

    override func draw(_ dirtyRect: NSRect) {
        if hover {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            NSColor.controlAccentColor.withAlphaComponent(dark ? 0.14 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

private final class CardSeparatorView: NSView {
    private let inset: CGFloat

    init(inset: CGFloat = 14) {
        self.inset = inset
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let line = NSRect(x: inset, y: 0, width: max(0, bounds.width - (inset * 2)), height: 1)
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
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
        layer?.masksToBounds = false

        let font = Self.capFont
        let label = NSTextField(labelWithString: symbol)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.alignment = .center
        label.textColor = .controlAccentColor
        label.isSelectable = false
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
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
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
                layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.46).cgColor
                layer?.borderWidth = 1
                layer?.shadowOpacity = 0
            } else {
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
                layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
                layer?.borderWidth = 1
                layer?.shadowOpacity = 0
            }
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
