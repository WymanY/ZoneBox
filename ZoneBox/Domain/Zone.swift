import Foundation

public struct Zone: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var number: Int
    public var name: String?
    public var canvasRect: NormalizedRect?

    public init(id: UUID = UUID(), number: Int, name: String? = nil, canvasRect: NormalizedRect? = nil) {
        self.id = id
        self.number = number
        self.name = name
        self.canvasRect = canvasRect
    }
}
