import Foundation

/// The built-in lists. You can add more from the menu-bar app at any time.
public enum Blocklists {
    public static let x: [String] = [
        "x.com", "www.x.com", "mobile.x.com", "api.x.com", "pro.x.com",
        "twitter.com", "www.twitter.com", "mobile.twitter.com", "api.twitter.com",
        "upload.twitter.com", "platform.twitter.com", "syndication.twitter.com",
        "tweetdeck.com", "tweetdeck.twitter.com", "t.co",
        "twimg.com", "abs.twimg.com", "abs-0.twimg.com", "pbs.twimg.com", "video.twimg.com", "ton.twimg.com",
        // Mirror sites that show X without logging in.
        "nitter.net", "xcancel.com",
    ]

    public static let instagram: [String] = [
        "instagram.com", "www.instagram.com", "i.instagram.com", "api.instagram.com",
        "graph.instagram.com", "l.instagram.com", "b.i.instagram.com", "about.instagram.com",
        "instagr.am", "www.instagr.am",
        "cdninstagram.com", "static.cdninstagram.com", "scontent.cdninstagram.com",
        // Viewer sites.
        "picuki.com", "www.picuki.com", "imginn.com", "www.imginn.com",
    ]

    public static let hotstar: [String] = [
        "hotstar.com", "www.hotstar.com", "api.hotstar.com", "hses.hotstar.com", "persona.hotstar.com",
        "jiohotstar.com", "www.jiohotstar.com",
        "hotstarext.com", "img1.hotstarext.com",
        "jiocinema.com", "www.jiocinema.com",
    ]

    /// Ways to get around DNS filtering: "secure DNS" servers and iCloud Private Relay.
    /// Blocking mask.icloud.com is Apple's documented way for a network to turn Private Relay off.
    public static let bypass: [String] = [
        "mask.icloud.com", "mask-h2.icloud.com", "mask-api.icloud.com",
        "dns.google", "dns.google.com", "cloudflare-dns.com", "mozilla.cloudflare-dns.com",
        "chrome.cloudflare-dns.com", "one.one.one.one", "1dot1dot1dot1.cloudflare-dns.com",
        "security.cloudflare-dns.com", "family.cloudflare-dns.com",
        "dns.quad9.net", "dns9.quad9.net", "dns10.quad9.net", "dns11.quad9.net",
        "doh.opendns.com", "dns.adguard.com", "dns.adguard-dns.com", "unfiltered.adguard-dns.com",
        "dns.nextdns.io", "dns0.eu", "doh.mullvad.net", "dns.mullvad.net", "base.dns.mullvad.net",
    ]

    /// Every browser is closed while the Mahadev session has Hotstar open, so Calm's own window
    /// (series only, one episode) is the only way in.
    public static let browsersClosedDuringShow: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "ai.perplexity.comet",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.google.chrome.for.testing", "org.chromium.Chromium",
        "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX", "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS", "org.mozilla.firefox", "app.zen-browser.zen", "net.imput.helium",
        "com.openai.atlas", "com.sigmaos.sigmaos.macos", "com.duckduckgo.macos.browser",
    ]

    /// Opened only during the daily Devon Ke Dev Mahadev session (Chrome's own block stays on).
    public static var showSites: Set<String> { Set(hotstar.flatMap { withWWW($0) }) }

    /// All built-in sites, in a stable order.
    public static var builtInSites: [String] { x + instagram + hotstar + bypass }

    /// Sites Chrome itself blocks (Chrome's rule also covers every sub-domain).
    public static let chromeURLBlocklist: [String] = [
        "x.com", "twitter.com", "t.co", "twimg.com", "tweetdeck.com", "nitter.net", "xcancel.com",
        "instagram.com", "cdninstagram.com", "instagr.am", "picuki.com", "imginn.com",
        "hotstar.com", "jiohotstar.com", "hotstarext.com", "jiocinema.com",
    ]

    /// Apps that are quit the moment they open. Matched by bundle id (an app's unique name).
    public static let blockedApps: [String] = [
        // X, Instagram, JioHotstar (iPhone/iPad versions can run on Apple-silicon Macs).
        "com.atebits.Tweetie2", "com.twitter.twitter-mac", "com.burbn.instagram", "in.startv.hotstar",
        "com.jio.media.ondemand",
        // Browsers other than Safari and Chrome (they could get around the rules).
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "com.brave.Browser", "com.brave.Browser.beta", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX", "com.opera.OperaAir",
        "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.google.Chrome.canary", "com.google.Chrome.beta",
        "com.google.Chrome.dev", "com.duckduckgo.macos.browser", "app.zen-browser.zen", "org.torproject.torbrowser",
        "net.waterfox.waterfox", "net.mullvad.mullvadbrowser", "com.kagi.kagimacOS",
        "com.apple.SafariTechnologyPreview", "ru.yandex.desktop.yandex-browser", "com.naver.Whale",
        // VPN apps.
        "com.wireguard.macos", "net.openvpn.connect.app", "com.nordvpn.macos", "com.nordvpn.osx",
        "com.expressvpn.ExpressVPN", "ch.protonvpn.mac", "com.cloudflare.1dot1dot1dot1.macos",
        "com.surfshark.vpnclient.macos", "com.privateinternetaccess.vpn", "com.windscribe.desktop",
        "net.tunnelblick.tunnelblick", "com.psiphon3.psiphon", "com.hotspotshield.vpn.mac",
        "com.cyberghostsrl.cyberghostmac", "net.mullvad.vpn", "com.tunnelbear.mac.TunnelBear",
    ]

    /// Chrome is allowed only while its lock profile (incognito off) is installed.
    public static let chromeBundleID = "com.google.Chrome"

    /// CleanBrowsing "Adult Filter": blocks adult sites and forces safe search. Free.
    public static let filterDNS: [String] = ["185.228.168.10", "185.228.169.11", "2a0d:2a00:1::1", "2a0d:2a00:2::1"]

    /// Public DNS / secure-DNS servers that apps could use directly to skip the filter.
    public static let bypassDNSServers: [String] = [
        "1.1.1.1", "1.0.0.1", "1.1.1.2", "1.0.0.2", "1.1.1.3", "1.0.0.3",
        "8.8.8.8", "8.8.4.4", "9.9.9.9", "149.112.112.112", "9.9.9.10", "149.112.112.10",
        "208.67.222.222", "208.67.220.220", "94.140.14.14", "94.140.15.15", "94.140.14.140",
        "45.90.28.0/24", "45.90.30.0/24", "193.110.81.0", "185.253.5.0", "194.242.2.2",
        "2606:4700:4700::1111", "2606:4700:4700::1001", "2001:4860:4860::8888", "2001:4860:4860::8844",
        "2620:fe::fe", "2620:fe::9", "2620:119:35::35", "2620:119:53::53",
    ]

    /// Turns what you type ("https://www.Example.com/path") into a clean domain ("www.example.com").
    /// Returns nil if it doesn't look like a domain.
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let i = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { s = String(s[..<i]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.lastIndex(of: ":") { s = String(s[..<colon]) }
        while s.hasSuffix(".") { s.removeLast() }
        guard s.count >= 3, s.count <= 253, s.contains("."), !s.hasPrefix("."), !s.hasPrefix("-") else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard s.allSatisfy({ allowed.contains($0) }), !s.contains("..") else { return nil }
        return s
    }

    /// For "example.com" also block "www.example.com" (the hosts file has no wildcards).
    public static func withWWW(_ domain: String) -> [String] {
        if domain.hasPrefix("www.") { return [domain, String(domain.dropFirst(4))] }
        return [domain, "www." + domain]
    }

    /// Lightweight check that a string looks like a bundle id, e.g. "com.example.App".
    public static func isBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, s.count <= 255 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { allowed.contains($0) } }
    }

    /// Reads a hosts-format file ("0.0.0.0 bad.com") and returns just the domains.
    public static func parseHostsList(_ text: String) -> [String] {
        var out: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let fields = content.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else { continue }
            for f in fields.dropFirst() {
                if let d = normalize(String(f)), d != "localhost" { out.append(d) }
            }
        }
        return out
    }
}
