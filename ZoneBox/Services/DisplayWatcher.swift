import AppKit
import CoreGraphics
import ZoneBoxCore

@MainActor
final class DisplayWatcher {
    private(set) var workAreas: [WorkArea] = []
    private(set) var primaryFlipHeight: CGFloat = 0
    var onChange: (() -> Void)?

    func refresh(document: inout StoreDocument) {
        let screens = NSScreen.screens
        primaryFlipHeight = CoordinateConverter.primaryFlipHeight(screenFramesAppKit: screens.map(\.frame))
        var areas: [WorkArea] = []
        for screen in screens {
            let probe = Self.probe(screen)
            let identity: DisplayIdentity
            if let match = DisplayIdentity.bestMatch(probe: probe, candidates: document.displays), match.1 >= 70 {
                var updated = match.0
                updated.lastCGDisplayID = probe.lastCGDisplayID
                updated.uuid = probe.uuid ?? updated.uuid
                updated.visibleWidth = probe.visibleWidth
                updated.visibleHeight = probe.visibleHeight
                updated.backingScale = probe.backingScale
                identity = updated
                if let idx = document.displays.firstIndex(where: { $0.id == updated.id }) {
                    document.displays[idx] = updated
                }
            } else {
                identity = probe
                document.displays.append(identity)
                let layout = LayoutTemplates.defaultForVisible(width: probe.visibleWidth, height: probe.visibleHeight)
                if !document.layouts.contains(where: { $0.id == layout.id }) {
                    document.layouts.append(layout)
                }
                document.assign(layoutID: layout.id, to: identity.id)
            }
            areas.append(
                WorkArea(
                    display: identity,
                    frameAppKit: screen.frame,
                    visibleFrameAppKit: screen.visibleFrame,
                    backingScale: screen.backingScaleFactor
                )
            )
        }
        workAreas = areas
        onChange?()
    }

    func area(containingAppKit point: CGPoint) -> WorkArea? {
        workAreas.first { $0.frameAppKit.contains(point) }
    }

    var activeDisplayIDs: [DisplayIdentity.ID] {
        workAreas.compactMap { area in
            screen(for: area.display.id) == nil ? nil : area.display.id
        }
    }

    func isActive(displayID: DisplayIdentity.ID) -> Bool {
        screen(for: displayID) != nil
    }

    func screen(for displayID: DisplayIdentity.ID) -> NSScreen? {
        guard let display = workAreas.first(where: { $0.display.id == displayID })?.display,
              display.lastCGDisplayID != 0
        else { return nil }
        return NSScreen.screens.first { Self.displayID(for: $0) == display.lastCGDisplayID }
    }

    static func probe(_ screen: NSScreen) -> DisplayIdentity {
        let number = displayID(for: screen)
        var uuid: UUID?
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(number) {
            let cf = cfUUID.takeUnretainedValue()
            uuid = UUID(uuidString: CFUUIDCreateString(nil, cf) as String)
        }
        return DisplayIdentity(
            uuid: uuid,
            lastCGDisplayID: number,
            vendorNumber: CGDisplayVendorNumber(number),
            productNumber: CGDisplayModelNumber(number),
            serialNumber: CGDisplaySerialNumber(number),
            localizedName: screen.localizedName,
            visibleWidth: screen.visibleFrame.width,
            visibleHeight: screen.visibleFrame.height,
            backingScale: screen.backingScaleFactor
        )
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
