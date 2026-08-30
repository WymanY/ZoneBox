import Foundation

public enum AppIdentity {
    public static let releaseBundleID = "com.fancyzone.app"
    public static let debugBundleID = "com.fancyzone.app.debug"

    public static var bundleID: String {
#if DEBUG
        debugBundleID
#else
        releaseBundleID
#endif
    }

    public static var supportDirectoryName: String { bundleID }

    public static var defaultSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
    }

    public static var ownBundleIDs: Set<String> {
        [releaseBundleID, debugBundleID]
    }
}
