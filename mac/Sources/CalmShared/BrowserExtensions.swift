import Foundation

/// Is Calm's black-page extension installed and turned on in a Chromium browser profile?
/// Reads the profile's "Secure Preferences" (where Chrome, Comet, Brave… record extensions).
public enum BrowserExtensions {
    public struct Browser: Sendable {
        public let name: String
        /// Relative to the user's home folder.
        public let dataDir: String
    }

    public static let browsers = [
        Browser(name: "Comet", dataDir: "Library/Application Support/Comet"),
        Browser(name: "Chrome", dataDir: "Library/Application Support/Google/Chrome"),
    ]

    public enum State: Equatable { case missing, installed, ready }

    /// `.ready` = installed, turned on, and allowed to read files (it needs Calm's status for the Mahadev session).
    public static func state(securePreferences data: Data, extensionPath: String = CalmPaths.blankPageExtension) -> State {
        guard let entry = entry(securePreferences: data, extensionPath: extensionPath) else { return .missing }
        return (entry["newAllowFileAccess"] as? Bool) == true ? .ready : .installed
    }

    public static func isInstalled(securePreferences data: Data, extensionPath: String = CalmPaths.blankPageExtension) -> Bool {
        entry(securePreferences: data, extensionPath: extensionPath) != nil
    }

    private static func entry(securePreferences data: Data, extensionPath: String) -> [String: Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ext = json["extensions"] as? [String: Any],
              let settings = ext["settings"] as? [String: Any] else { return nil }
        let want = (extensionPath as NSString).standardizingPath
        for case let entry as [String: Any] in settings.values {
            guard let path = entry["path"] as? String, (path as NSString).standardizingPath == want else { continue }
            if let state = entry["state"] as? Int, state == 0 { return nil }
            if let reasons = entry["disable_reasons"] as? [Any], !reasons.isEmpty { return nil }
            if let reasons = entry["disable_reasons"] as? Int, reasons != 0 { return nil }
            return entry
        }
        return nil
    }

    /// Profile folders ("Default", "Profile 1", …) of a browser that has been used.
    public static func profiles(browserDir: String) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: browserDir) else { return [] }
        return names.filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .filter { fm.fileExists(atPath: browserDir + "/" + $0 + "/Secure Preferences") }
            .sorted()
    }
}
