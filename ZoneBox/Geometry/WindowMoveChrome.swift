import CoreGraphics

/// Pointer-down classification for window-move chrome versus in-window content.
///
/// Snap overlay arms only for title-bar drags. Content hits (text, web views,
/// tables, sliders) stay inert even when Shift is held or the pointer wiggles.
public enum WindowMoveChrome: Sendable {
    public static let titleBarHeight: CGFloat = 36
    public static let titleBarRole = "AXTitleBar"

    private static let titleBarButtonSubroles: Set<String> = [
        "AXCloseButton",
        "AXMinimizeButton",
        "AXZoomButton",
        "AXFullScreenButton",
    ]

    private static let contentRoles: Set<String> = [
        "AXButton",
        "AXTab",
        "AXTabGroup",
        "AXTextArea",
        "AXTextField",
        "AXList",
        "AXOutline",
        "AXTable",
        "AXMenu",
        "AXMenuBar",
        "AXMenuItem",
        "AXSlider",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXComboBox",
        "AXIncrementor",
        "AXRow",
        "AXCell",
        "AXLink",
        "AXHandle",
        "AXSplitter",
        "AXProgressIndicator",
        "AXBrowser",
        "AXColorWell",
        "AXDisclosureTriangle",
    ]

    public static func contains(
        axPoint: CGPoint,
        windowFrameAX: CGRect,
        hitRole: String?,
        hitSubrole: String?,
        ancestorRoles: [String]
    ) -> Bool {
        if let hitSubrole, titleBarButtonSubroles.contains(hitSubrole) {
            return false
        }
        if let hitRole, contentRoles.contains(hitRole) {
            return false
        }
        if ancestorRoles.contains(where: { contentRoles.contains($0) }) {
            return false
        }
        if hitRole == titleBarRole || ancestorRoles.contains(titleBarRole) {
            return true
        }
        if hitRole == "AXToolbar" || ancestorRoles.contains("AXToolbar") {
            return titleBarBand(windowFrameAX, height: 52).contains(axPoint)
        }
        return titleBarBand(windowFrameAX).contains(axPoint)
    }

    public static func titleBarBand(_ windowFrameAX: CGRect) -> CGRect {
        titleBarBand(windowFrameAX, height: titleBarHeight)
    }

    public static func titleBarBand(_ windowFrameAX: CGRect, height: CGFloat) -> CGRect {
        CGRect(
            x: windowFrameAX.minX,
            y: windowFrameAX.minY,
            width: windowFrameAX.width,
            height: min(height, max(windowFrameAX.height, 0))
        )
    }
}
