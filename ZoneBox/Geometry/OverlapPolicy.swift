public enum OverlapPolicy: String, Codable, Sendable, CaseIterable {
    case smallestArea
    case largestArea
    case closestCenterToCursor
}
