import CoreGraphics

public enum SnapWindowEligibility: Sendable {
    public static let minimumSize: CGFloat = 80

    public static func isSnappable(
        layer: Int,
        size: CGSize,
        pid: pid_t,
        ownPID: pid_t,
        windowNumber: UInt32,
        bundleID: String?,
        excludedBundleIDs: [String],
        allowedWindowNumbers: Set<UInt32>
    ) -> Bool {
        guard layer == 0,
              size.width >= minimumSize,
              size.height >= minimumSize
        else { return false }
        if allowedWindowNumbers.contains(windowNumber) {
            return true
        }
        guard pid != ownPID else { return false }
        if let bundleID, excludedBundleIDs.contains(bundleID) {
            return false
        }
        return true
    }
}
