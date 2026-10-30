import AppKit
import ZoneBoxCore

@MainActor
final class ShortcutPanelController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: ShortcutWindow?
    private var headerHost: NSView?
    private var columnsHost: NSView?
    private var footerHost: NSView?
    private var scrollView: NSScrollView?

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
    }

    var isKey: Bool { window?.isKeyWindow == true }
    var isVisible: Bool { window?.isVisible == true }

    func show() {
        let isNew = window == nil
        if isNew { window = makeWindow() }
        rebuild()
        fitWindowToContent(center: isNew)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        headerHost = nil
        columnsHost = nil
        footerHost = nil
        scrollView = nil
        runtime.shortcutPanelDidClose()
    }

    func applyLanguage() {
        window?.title = L10n.text(.shortcutsTitle)
        rebuild()
        fitWindowToContent(center: false)
    }

    @objc private func handleCustomizeClicked() {
        runtime.openKeyboardSettings()
    }

    private func makeWindow() -> ShortcutWindow {
        let window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: ShortcutPanelMetrics.windowWidth, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.shortcutsTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 3)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let content = NSVisualEffectView()
        content.material = .contentBackground
        content.blendingMode = .withinWindow
        content.state = .followsWindowActiveState
        window.contentView = content

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        headerHost = header

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentView.drawsBackground = false
        scrollView = scroll

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        let columns = NSView()
        columns.translatesAutoresizingMaskIntoConstraints = false
        columnsHost = columns
        document.addSubview(columns)
        scroll.documentView = document

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footerHost = footer

        content.addSubview(header)
        content.addSubview(scroll)
        content.addSubview(footer)

        let inset = ShortcutPanelMetrics.pageInset
        let topAnchor = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: ShortcutPanelMetrics.sectionGap),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            footer.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 14),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),

            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            columns.topAnchor.constraint(equalTo: document.topAnchor),
            columns.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: inset),
            columns.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -inset),
            columns.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -ShortcutPanelMetrics.scrollBottomInset),
        ])
        return window
    }

    private func rebuild() {
        guard let headerHost, let columnsHost, let footerHost else { return }
        install(makeHeader(), in: headerHost)
        install(makeColumns(), in: columnsHost)
        install(makeFooter(), in: footerHost)
    }

    private func install(_ view: NSView, in host: NSView) {
        host.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }

    /// Grows the window to show every shortcut without scrolling, capped to the screen.
    private func fitWindowToContent(center: Bool) {
        guard let window, let content = window.contentView, let scrollView, let columnsHost else { return }
        // Second pass lets wrapped row titles report their final height.
        content.layoutSubtreeIfNeeded()
        content.layoutSubtreeIfNeeded()
        let chrome = content.bounds.height - scrollView.frame.height
        let desired = chrome + columnsHost.frame.height + ShortcutPanelMetrics.scrollBottomInset
        let visibleHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let height = min(desired, visibleHeight - 48).rounded()
        let previousTop = window.frame.maxY
        window.setContentSize(NSSize(width: ShortcutPanelMetrics.windowWidth, height: height))
        if center {
            window.center()
        } else {
            var frame = window.frame
            frame.origin.y = previousTop - frame.height
            window.setFrame(frame, display: true)
        }
    }

    private func makeHeader() -> NSView {
        let container = NSView()

        let iconWell = HeaderIconWell(symbol: "keyboard.fill", tint: .systemOrange)

        let title = NSTextField(labelWithString: L10n.text(.shortcutsTitle))
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: L10n.text(.shortcutsSubtitle))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let leftGroup = NSStackView(views: [iconWell, textStack])
        leftGroup.orientation = .horizontal
        leftGroup.alignment = .centerY
        leftGroup.spacing = 14
        leftGroup.translatesAutoresizingMaskIntoConstraints = false

        let customizeButton = NSButton(
            title: L10n.text(.shortcutsCustomize),
            target: self,
            action: #selector(handleCustomizeClicked)
        )
        customizeButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        customizeButton.imagePosition = .imageLeading
        customizeButton.imageHugsTitle = true
        customizeButton.bezelStyle = .rounded
        customizeButton.controlSize = .regular
        customizeButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(leftGroup)
        container.addSubview(customizeButton)

        NSLayoutConstraint.activate([
            leftGroup.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftGroup.topAnchor.constraint(equalTo: container.topAnchor),
            leftGroup.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            customizeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            customizeButton.centerYAnchor.constraint(equalTo: leftGroup.centerYAnchor),
            customizeButton.leadingAnchor.constraint(greaterThanOrEqualTo: leftGroup.trailingAnchor, constant: 16),
        ])

        return container
    }

    private func makeColumns() -> NSView {
        let grouped = Dictionary(uniqueKeysWithValues: ShortcutCatalog.grouped(from: runtime.settings).map { ($0.surface, $0.items) })

        let columns = NSStackView(views: [
            makeColumn(surfaces: [.global, .snap], grouped: grouped),
            makeColumn(surfaces: [.editor, .application], grouped: grouped),
        ])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = ShortcutPanelMetrics.sectionGap
        // Lets the shorter column end at its content instead of stretching to the taller one.
        columns.setHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        return columns
    }

    private func makeColumn(surfaces: [ShortcutSurface], grouped: [ShortcutSurface: [ShortcutSpec]]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = ShortcutPanelMetrics.sectionGap
        stack.translatesAutoresizingMaskIntoConstraints = false

        for surface in surfaces {
            let items = grouped[surface] ?? []
            guard !items.isEmpty else { continue }
            let section = ShortcutSectionView(
                title: L10n.text(surface.titleKey),
                symbol: surface.symbolName,
                rows: displayRows(items)
            )
            stack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func makeFooter() -> NSView {
        let container = NSView()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        icon.contentTintColor = .tertiaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let note = NSTextField(wrappingLabelWithString: L10n.text(.shortcutsVoiceOverNote))
        note.font = .systemFont(ofSize: 11.5)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let closeHint = ShortcutKeysView(
            tokens: ShortcutToken.parse(L10n.text(.shortcutsCloseHint)),
            textColor: .tertiaryLabelColor
        )

        container.addSubview(icon)
        container.addSubview(note)
        container.addSubview(closeHint)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: note.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),

            note.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            note.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            note.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            note.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            note.trailingAnchor.constraint(lessThanOrEqualTo: closeHint.leadingAnchor, constant: -20),

            closeHint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            closeHint.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeHint.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            closeHint.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        let hug = container.heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .defaultLow
        hug.isActive = true
        return container
    }

    private func displayRows(_ items: [ShortcutSpec]) -> [(title: String, tokens: [ShortcutToken])] {
        var rows: [(String, [ShortcutToken])] = []
        var index = 0
        while index < items.count {
            let item = items[index]
            if item.id.hasPrefix("snapZone"), case .chord(let chord) = item.binding {
                let modifiers = Array(chord.displayCaps.dropLast())
                rows.append((L10n.text(.shortcutSnapZones), (modifiers + ["1–9"]).map(ShortcutToken.key)))
                while index < items.count, items[index].id.hasPrefix("snapZone") {
                    index += 1
                }
                continue
            }
            rows.append((item.title(language: LanguageCenter.language), tokens(for: item)))
            index += 1
        }
        return rows
    }

    private func tokens(for item: ShortcutSpec) -> [ShortcutToken] {
        switch item.binding {
        case .chord(let chord):
            return chord.displayCaps.map(ShortcutToken.key)
        case .gesture(let key):
            return ShortcutToken.parse(L10n.text(key))
        }
    }
}

private enum ShortcutPanelMetrics {
    static let windowWidth: CGFloat = 840
    static let pageInset: CGFloat = 28
    static let sectionGap: CGFloat = 20
    static let scrollBottomInset: CGFloat = 4
    static let rowInset: CGFloat = 16
    static let rowHeight: CGFloat = 30
}

/// One piece of a binding: a physical key drawn as a keycap, or descriptive gesture text.
private enum ShortcutToken {
    case key(String)
    case text(String)

    private static let keySymbols: Set<String> = [
        "⌃", "⌥", "⇧", "⌘", "⇥", "⌫", "↩", "←", "→", "↑", "↓", "esc", "1–9",
    ]

    /// Splits localized gesture copy such as "⌘  drag empty space" into keycaps and text.
    static func parse(_ string: String) -> [ShortcutToken] {
        var tokens: [ShortcutToken] = []
        var words: [String] = []
        func flushWords() {
            guard !words.isEmpty else { return }
            tokens.append(.text(words.joined(separator: " ")))
            words.removeAll()
        }
        for word in string.split(whereSeparator: \.isWhitespace).map(String.init) {
            if keySymbols.contains(word) {
                flushWords()
                tokens.append(.key(word))
            } else {
                words.append(word)
            }
        }
        flushWords()
        return tokens
    }

    var spokenText: String {
        switch self {
        case .key(let symbol), .text(let symbol): symbol
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

/// Matches SettingsGroupSurfaceView used throughout the Settings window.
private final class ShortcutGroupSurfaceView: NSVisualEffectView {
    init(content: NSView) {
        super.init(frame: .zero)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
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
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.76).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
            layer?.borderWidth = 0.5
        }
    }
}

/// Matches SettingsRowIconView, scaled up for the panel header.
private final class HeaderIconWell: NSView {
    private let tint: NSColor

    init(symbol: String, tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous

        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        image.contentTintColor = tint
        addSubview(image)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 40),
            heightAnchor.constraint(equalToConstant: 40),
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

private final class ShortcutSectionView: NSStackView {
    init(title: String, symbol: String, rows: [(title: String, tokens: [ShortcutToken])]) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .width
        spacing = 7
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        icon.contentTintColor = .controlAccentColor

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        let header = NSStackView(views: [icon, heading])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 0)

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 0
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = RowSeparatorView()
                list.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }
            let rowView = ShortcutRowView(title: row.title, tokens: row.tokens)
            list.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }

        let card = ShortcutGroupSurfaceView(content: list)
        addArrangedSubview(header)
        addArrangedSubview(card)
        header.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        card.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class ShortcutRowView: NSView {
    init(title: String, tokens: [ShortcutToken]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let label = RowTitleLabel(title)
        let keys = ShortcutKeysView(tokens: tokens, textColor: .secondaryLabelColor)

        addSubview(label)
        addSubview(keys)

        let hug = heightAnchor.constraint(equalToConstant: 0)
        hug.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultHigh.rawValue - 10)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShortcutPanelMetrics.rowInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: keys.leadingAnchor, constant: -12),

            keys.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(ShortcutPanelMetrics.rowInset - 4)),
            keys.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(greaterThanOrEqualToConstant: ShortcutPanelMetrics.rowHeight),
            hug,
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(([title] + tokens.map(\.spokenText)).joined(separator: " "))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Wraps long English titles onto a second line instead of truncating them.
private final class RowTitleLabel: NSTextField {
    init(_ title: String) {
        super.init(frame: .zero)
        stringValue = title
        font = .systemFont(ofSize: 13)
        textColor = .labelColor
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        lineBreakMode = .byWordWrapping
        maximumNumberOfLines = 2
        cell?.wraps = true
        cell?.truncatesLastVisibleLine = true
        toolTip = title
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = max(0, floor(bounds.width))
        if width > 0, abs(preferredMaxLayoutWidth - width) > 1 {
            preferredMaxLayoutWidth = width
            invalidateIntrinsicContentSize()
        }
    }
}

private final class ShortcutKeysView: NSStackView {
    init(tokens: [ShortcutToken], textColor: NSColor) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 3
        translatesAutoresizingMaskIntoConstraints = false
        setHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        for token in tokens {
            switch token {
            case .key(let symbol):
                addArrangedSubview(KeyCapView(symbol: symbol))
            case .text(let text):
                let label = NSTextField(labelWithString: text)
                label.font = .systemFont(ofSize: 12)
                label.textColor = textColor
                label.setContentCompressionResistancePriority(.required, for: .horizontal)
                if let previous = arrangedSubviews.last { setCustomSpacing(6, after: previous) }
                addArrangedSubview(label)
                setCustomSpacing(6, after: label)
            }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class RowSeparatorView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShortcutPanelMetrics.rowInset),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Neutral keycap so dense lists stay calm; accent color is reserved for section icons.
private final class KeyCapView: NSView {
    private static let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
    private static let height: CGFloat = 21
    private static let radius: CGFloat = 5

    private let symbol: String

    init(symbol: String) {
        self.symbol = symbol
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        let textWidth = ceil((symbol as NSString).size(withAttributes: [.font: Self.font]).width)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: max(Self.height, textWidth + 12)),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let body = NSRect(x: 0.5, y: 1.5, width: bounds.width - 1, height: bounds.height - 2)
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: Self.radius, yRadius: Self.radius)

        if dark {
            NSColor.white.withAlphaComponent(0.10).setFill()
            bodyPath.fill()
            NSColor.white.withAlphaComponent(0.12).setStroke()
        } else {
            let lip = NSBezierPath(roundedRect: body.offsetBy(dx: 0, dy: -1), xRadius: Self.radius, yRadius: Self.radius)
            NSColor.black.withAlphaComponent(0.10).setFill()
            lip.fill()
            NSColor.white.setFill()
            bodyPath.fill()
            NSColor.black.withAlphaComponent(0.12).setStroke()
        }
        bodyPath.lineWidth = 0.5
        bodyPath.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(dark ? 0.88 : 0.78),
        ]
        let size = (symbol as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: (body.midX - size.width / 2).rounded(), y: (body.midY - size.height / 2).rounded())
        (symbol as NSString).draw(at: origin, withAttributes: attributes)
    }
}
