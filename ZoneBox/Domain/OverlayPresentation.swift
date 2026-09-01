import CoreGraphics
import Foundation

public struct OverlayCandidateLabel: Equatable, Sendable {
    public var text: String
    public var anchorAX: CGRect

    public init(text: String, anchorAX: CGRect) {
        self.text = text
        self.anchorAX = anchorAX
    }
}

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
    public var candidateOutlinesAX: [CGRect]
    public var candidateLabel: OverlayCandidateLabel?
    public var strip: OverlayStripRenderModel?
    public var layoutName: String?

    public static let empty = OverlayPresentation(
        candidateOutlinesAX: [],
        candidateLabel: nil,
        strip: nil,
        layoutName: nil
    )

    public init(
        candidateOutlinesAX: [CGRect] = [],
        candidateLabel: OverlayCandidateLabel? = nil,
        strip: OverlayStripRenderModel? = nil,
        layoutName: String? = nil
    ) {
        self.candidateOutlinesAX = candidateOutlinesAX
        self.candidateLabel = candidateLabel
        self.strip = strip
        self.layoutName = layoutName
    }
}
