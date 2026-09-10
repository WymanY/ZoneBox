import AppKit

enum WorkspaceApplicationInfo {
    static func info(bundleID: String) -> (name: String, icon: NSImage?) {
        let runningName = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.localizedName
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return (
                runningName ?? bundleID,
                NSImage(systemSymbolName: "app.fill", accessibilityDescription: runningName ?? bundleID)
            )
        }
        let bundle = Bundle(url: url)
        let storedName = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let name = runningName ?? storedName ?? url.deletingPathExtension().lastPathComponent
        let icon = (NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage)
            ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: name)
        return (name, icon)
    }

    static func info(for bundleIDs: [String]) -> [String: (name: String, icon: NSImage?)] {
        var values: [String: (name: String, icon: NSImage?)] = [:]
        for bundleID in bundleIDs where values[bundleID] == nil {
            values[bundleID] = info(bundleID: bundleID)
        }
        return values
    }
}
