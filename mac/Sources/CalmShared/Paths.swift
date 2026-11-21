import Foundation

/// Every file location Calm uses, in one place.
public enum CalmPaths {
    public static let supportDir = "/Library/Application Support/Calm"
    /// World-readable snapshot the menu-bar app shows. Written only by the guard.
    public static let statusFile = supportDir + "/status.json"
    /// Drop box: the menu-bar app writes requests here, the guard reads and deletes them.
    public static let inboxDir = supportDir + "/inbox"
    /// Root-only folder for the lock state, settings and the profile removal password.
    public static let privateDir = supportDir + "/private"
    public static let stateFile = privateDir + "/state.json"
    public static let settingsFile = privateDir + "/settings.json"
    public static let secretFile = privateDir + "/removal-password"
    /// Big adult-site list shipped by the installer (optional, the DNS filter is the main defence).
    public static let adultHostsFile = supportDir + "/adult-hosts.txt"
    /// Where the Chrome lock profile is placed briefly so you can install it.
    public static let profileDrop = "/Users/Shared/Calm-Chrome.mobileconfig"

    public static let hostsFile = "/private/etc/hosts"
    public static let daemonBinary = "/Library/PrivilegedHelperTools/com.calm.calmd"
    public static let daemonPlist = "/Library/LaunchDaemons/com.calm.calmd.plist"
    public static let agentPlist = "/Library/LaunchAgents/com.calm.bar.plist"
    public static let appBundle = "/Applications/CalmBar.app"
    public static let chromeManagedPrefs = "/Library/Managed Preferences/com.google.Chrome.plist"

    public static let daemonLabel = "com.calm.calmd"
    public static let agentLabel = "com.calm.bar"
    public static let profileIdentifier = "com.calm.chrome-lock"
    /// pf anchor under com.apple/* so macOS's default pf.conf already evaluates it.
    public static let pfAnchor = "com.apple/250.CalmBlock"
}
