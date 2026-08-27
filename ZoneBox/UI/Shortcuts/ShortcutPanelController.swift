import AppKit
import ZoneBoxCore

@MainActor
final class ShortcutPanelController: NSObject, NSWindowDelegate {
    private unowned let runtime: AppRuntime
    private var window: ShortcutWindow?
    private var documentView: NSStackView?

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
        documentView = nil
        runtime.shortcutPanelDidClose()
    }

    func applyLanguage() {
        window?.title = L10n.text(.shortcutsTitle)
        rebuild()
    }

    private func makeWindow() -> ShortcutWindow {
        let window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.shortcutsTitle)
        window.minSize = NSSize(width: 440, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 3)
        window.center()

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let document = NSStackView()
        document.orientation = .vertical
        document.alignment = .width
        document.spacing = 16
        document.translatesAutoresizingMaskIntoConstraints = false
        document.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        documentView = document

        let clip = FlippedView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(document)
        scroll.documentView = clip

        let content = NSView()
        window.contentView = content
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            clip.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return window
    }

    private func rebuild() {
        guard let document = documentView else { return }
        for view in document.arrangedSubviews {
            document.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for group in ShortcutCatalog.grouped(from: runtime.settings) {
            document.addArrangedSubview(sectionHeader(L10n.text(group.surface.titleKey)))
            for item in group.items {
                document.addArrangedSubview(row(for: item))
            }
        }

        let note = NSTextField(wrappingLabelWithString: L10n.text(.shortcutsVoiceOverNote))
        note.font = .systemFont(ofSize: 11, weight: .regular)
        note.textColor = .secondaryLabelColor
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        document.addArrangedSubview(note)
    }

    private func sectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func row(for item: ShortcutSpec) -> NSView {
        let title = NSTextField(labelWithString: item.title(language: LanguageCenter.language))
        title.font = .systemFont(ofSize: 13, weight: .regular)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let caps = NSStackView(views: capViews(for: item))
        caps.orientation = .horizontal
        caps.spacing = 6
        caps.alignment = .centerY
        caps.setHuggingPriority(.required, for: .horizontal)
        caps.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [title, caps])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func capViews(for item: ShortcutSpec) -> [NSView] {
        switch item.binding {
        case .chord(let chord):
            return chord.displayCaps.map { KeyCapView(symbol: $0) }
        case .gesture(let key):
            return [KeyCapView(symbol: L10n.text(key), wide: true)]
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

private final class KeyCapView: NSView {
    init(symbol: String, wide: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        let label = NSTextField(labelWithString: symbol)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = wide
            ? .systemFont(ofSize: 12, weight: .semibold)
            : .monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        addSubview(label)

        let minWidth: CGFloat = wide ? 84 : 26
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override var wantsUpdateLayer: Bool { true }
}
