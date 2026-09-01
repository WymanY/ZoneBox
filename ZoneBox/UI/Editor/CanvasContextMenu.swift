import AppKit
import ZoneBoxCore

enum CanvasContextMenu {
    static func make(
        layout: Layout,
        hitZone: Zone?,
        selectionCount: Int,
        target: AnyObject,
        insert: Selector,
        duplicate: Selector,
        splitVertical: Selector,
        splitHorizontal: Selector,
        selectAll: Selector,
        delete: Selector,
        center: Selector,
        fillTemplate: Selector,
        align: Selector,
        matchSize: Selector,
        distribute: Selector,
        snapHalf: Selector,
        assignNumber: Selector
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let isCanvas = layout.kind != .grid
        let hasSelection = selectionCount > 0 || hitZone != nil

        if hitZone == nil {
            addItem(menu, title: L10n.text(.canvasNewPane), action: insert, target: target, enabled: isCanvas, key: "click")
            addSeparator(menu)
            let templates = NSMenu()
            let presets = LayoutTemplates.editorPresets()
            let keys: [L10nKey] = [
                .editorColumns2, .editorColumns3, .editorRows2, .editorGrid2x2, .editorPriority, .editorFocus,
            ]
            for (index, key) in keys.enumerated() where presets.indices.contains(index) {
                let item = NSMenuItem(title: L10n.text(key), action: fillTemplate, keyEquivalent: "")
                item.target = target
                item.tag = index
                item.isEnabled = isCanvas
                templates.addItem(item)
            }
            let fill = NSMenuItem(title: L10n.text(.canvasFillFromTemplate), action: nil, keyEquivalent: "")
            fill.submenu = templates
            fill.isEnabled = isCanvas
            menu.addItem(fill)
            addItem(
                menu,
                title: L10n.text(.canvasSelectAll),
                action: selectAll,
                target: target,
                enabled: !layout.zones.isEmpty,
                keyEquivalent: "a",
                modifiers: .command
            )
            return menu
        }

        addItem(
            menu,
            title: L10n.text(.canvasDuplicate),
            action: duplicate,
            target: target,
            enabled: isCanvas && hasSelection,
            keyEquivalent: "d",
            modifiers: .command
        )
        addItem(
            menu,
            title: L10n.text(.canvasSplitVertical),
            action: splitVertical,
            target: target,
            enabled: isCanvas && hasSelection,
            keyEquivalent: "\\",
            modifiers: [.command, .shift]
        )
        addItem(
            menu,
            title: L10n.text(.canvasSplitHorizontal),
            action: splitHorizontal,
            target: target,
            enabled: isCanvas && hasSelection,
            keyEquivalent: "-",
            modifiers: .command
        )
        addSeparator(menu)

        let halves = NSMenu()
        addTagged(halves, title: L10n.text(.canvasSnapHalfLeft), action: snapHalf, tag: 0, target: target, enabled: isCanvas)
        addTagged(halves, title: L10n.text(.canvasSnapHalfRight), action: snapHalf, tag: 1, target: target, enabled: isCanvas)
        addTagged(halves, title: L10n.text(.canvasSnapHalfTop), action: snapHalf, tag: 2, target: target, enabled: isCanvas)
        addTagged(halves, title: L10n.text(.canvasSnapHalfBottom), action: snapHalf, tag: 3, target: target, enabled: isCanvas)
        let halfItem = NSMenuItem(title: L10n.text(.canvasSnapToHalf), action: nil, keyEquivalent: "")
        halfItem.submenu = halves
        halfItem.isEnabled = isCanvas && hasSelection
        menu.addItem(halfItem)
        addItem(menu, title: L10n.text(.canvasCenter), action: center, target: target, enabled: isCanvas && hasSelection)
        addSeparator(menu)

        let alignMenu = NSMenu()
        addTagged(alignMenu, title: L10n.text(.canvasAlignLeft), action: align, tag: 0, target: target, enabled: selectionCount >= 2)
        addTagged(alignMenu, title: L10n.text(.canvasAlignCenterX), action: align, tag: 1, target: target, enabled: selectionCount >= 2)
        addTagged(alignMenu, title: L10n.text(.canvasAlignRight), action: align, tag: 2, target: target, enabled: selectionCount >= 2)
        addTagged(alignMenu, title: L10n.text(.canvasAlignTop), action: align, tag: 3, target: target, enabled: selectionCount >= 2)
        addTagged(alignMenu, title: L10n.text(.canvasAlignCenterY), action: align, tag: 4, target: target, enabled: selectionCount >= 2)
        addTagged(alignMenu, title: L10n.text(.canvasAlignBottom), action: align, tag: 5, target: target, enabled: selectionCount >= 2)
        let alignItem = NSMenuItem(title: L10n.text(.canvasAlign), action: nil, keyEquivalent: "")
        alignItem.submenu = alignMenu
        alignItem.isEnabled = isCanvas && selectionCount >= 2
        menu.addItem(alignItem)

        let sizeMenu = NSMenu()
        addTagged(sizeMenu, title: L10n.text(.canvasMatchWidth), action: matchSize, tag: 0, target: target, enabled: selectionCount >= 2)
        addTagged(sizeMenu, title: L10n.text(.canvasMatchHeight), action: matchSize, tag: 1, target: target, enabled: selectionCount >= 2)
        addTagged(sizeMenu, title: L10n.text(.canvasMatchBoth), action: matchSize, tag: 2, target: target, enabled: selectionCount >= 2)
        let sizeItem = NSMenuItem(title: L10n.text(.canvasMatchSize), action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        sizeItem.isEnabled = isCanvas && selectionCount >= 2
        menu.addItem(sizeItem)

        let distributeMenu = NSMenu()
        addTagged(distributeMenu, title: L10n.text(.canvasDistributeHorizontal), action: distribute, tag: 0, target: target, enabled: selectionCount >= 3)
        addTagged(distributeMenu, title: L10n.text(.canvasDistributeVertical), action: distribute, tag: 1, target: target, enabled: selectionCount >= 3)
        let distributeItem = NSMenuItem(title: L10n.text(.canvasDistribute), action: nil, keyEquivalent: "")
        distributeItem.submenu = distributeMenu
        distributeItem.isEnabled = isCanvas && selectionCount >= 3
        menu.addItem(distributeItem)
        addSeparator(menu)

        let numberMenu = NSMenu()
        for number in 1...9 {
            addTagged(numberMenu, title: "(number)", action: assignNumber, tag: number, target: target, enabled: isCanvas && hasSelection)
        }
        let numberItem = NSMenuItem(title: L10n.text(.canvasNumber), action: nil, keyEquivalent: "")
        numberItem.submenu = numberMenu
        numberItem.isEnabled = isCanvas && hasSelection
        menu.addItem(numberItem)
        addItem(
            menu,
            title: L10n.text(.canvasDeletePane),
            action: delete,
            target: target,
            enabled: hasSelection,
            keyEquivalent: "\u{8}",
            modifiers: []
        )
        return menu
    }

    private static func addSeparator(_ menu: NSMenu) {
        menu.addItem(.separator())
    }

    private static func addItem(
        _ menu: NSMenu,
        title: String,
        action: Selector,
        target: AnyObject,
        enabled: Bool,
        key: String? = nil,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.isEnabled = enabled
        item.keyEquivalentModifierMask = modifiers
        if let key {
            item.toolTip = key
        }
        menu.addItem(item)
    }

    private static func addTagged(
        _ menu: NSMenu,
        title: String,
        action: Selector,
        tag: Int,
        target: AnyObject,
        enabled: Bool
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.tag = tag
        item.isEnabled = enabled
        menu.addItem(item)
    }
}
