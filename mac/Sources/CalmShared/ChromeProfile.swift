import Foundation

/// Builds the macOS configuration profile that locks down Chrome:
/// no incognito, no guest mode, no secure-DNS bypass, no proxy tricks, and the sites blocked.
/// It carries a removal password, so it can't be removed without it.
public enum ChromeProfile {
    public static func chromePolicies(blockedSites: [String]) -> [String: Any] {
        [
            "IncognitoModeAvailability": 1,        // 1 = incognito disabled
            "BrowserGuestModeEnabled": false,
            "BrowserAddPersonEnabled": false,
            "DnsOverHttpsMode": "off",
            "BuiltInDnsClientEnabled": false,      // use the Mac's DNS (the filter)
            "ProxySettings": ["ProxyMode": "direct"], // extensions can't route around the block
            "ForceGoogleSafeSearch": true,
            "ForceYouTubeRestrict": 1,
            "URLBlocklist": blockedSites,
        ]
    }

    public static func build(removalPassword: String, blockedSites: [String]) throws -> Data {
        let chromePayload: [String: Any] = [
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadVersion": 1,
            "PayloadIdentifier": CalmPaths.profileIdentifier + ".chrome",
            "PayloadUUID": "6B1C2E4A-9D0F-4C3B-8E21-CA1A0000C401",
            "PayloadDisplayName": "Chrome lock",
            "PayloadContent": [
                "com.google.Chrome": [
                    "Forced": [["mcx_preference_settings": chromePolicies(blockedSites: blockedSites)]],
                ],
            ],
        ]
        let removalPayload: [String: Any] = [
            "PayloadType": "com.apple.profileRemovalPassword",
            "PayloadVersion": 1,
            "PayloadIdentifier": CalmPaths.profileIdentifier + ".removal",
            "PayloadUUID": "6B1C2E4A-9D0F-4C3B-8E21-CA1A0000C402",
            "RemovalPassword": removalPassword,
        ]
        let profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": CalmPaths.profileIdentifier,
            "PayloadUUID": "6B1C2E4A-9D0F-4C3B-8E21-CA1A0000C400",
            "PayloadDisplayName": "Calm: Chrome lock",
            "PayloadDescription": "Turns off Chrome incognito and blocks distracting sites. Managed by Calm.",
            "PayloadOrganization": "Calm",
            "PayloadScope": "System",
            "PayloadRemovalDisallowed": false,
            "PayloadContent": [chromePayload, removalPayload],
        ]
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }

    /// A random password like "k7m2-q9xw-4tbz".
    public static func randomPassword() -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        let groups = (0..<3).map { _ in String((0..<4).map { _ in chars.randomElement()! }) }
        return groups.joined(separator: "-")
    }
}
