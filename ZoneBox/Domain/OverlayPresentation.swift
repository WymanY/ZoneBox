import CoreGraphics
import Foundation

public struct OverlayStripRenderModel: Equatable, Sendable {
    public var geometry: LayoutStripGeometry
    public var highlightedLayoutID: Layout.ID?
    public var highlightedZoneNumber: Int?

    public init(
        geometry: LayoutStripGeometry,
        highlightedLayoutID: Layout.ID? = nil,
        highlightedZoneNumber: Int? = nil
    ) {
        self.geometry = geometry
        self.highlightedLayoutID = highlightedLayoutID
        self.highlightedZoneNumber = highlightedZoneNumber
    }
}

public struct OverlayPresentation: Equatable, Sendable {
    public var strip: OverlayStripRenderModel?
    public var layoutName: String?

    public static let empty = OverlayPresentation(
        strip: nil,
        layoutName: nil
    )

    public init(
        strip: OverlayStripRenderModel? = nil,
        layoutName: String? = nil
    ) {
        self.strip = strip
        self.layoutName = layoutName
    }

    /// Chrome for the armed snap overlay. Alternate-layout outlines and
    /// pointer-candidate labels are intentionally omitted.
    public static func snapSession(
        strip: OverlayStripRenderModel? = nil
    ) -> OverlayPresentation {
        OverlayPresentation(strip: strip)
    }
}
