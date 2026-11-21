import Foundation
import Testing
@testable import CalmShared

// Uses Apple's "Testing" library, which ships with the free Command Line Tools (XCTest needs full Xcode).

struct LockStateTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func startsLocked() {
        #expect(LockState(now: t0).phase(now: t0) == .locked)
    }

    @Test func unlockNeedsARealReason() throws {
        var s = LockState(now: t0)
        #expect(throws: LockState.LockError.needsReason) { try s.requestUnlock(reason: "pls", now: t0) }
        try s.requestUnlock(reason: "I need x.com for a work post", now: t0)
    }

    @Test func waitThenWindowThenLocksAgain() throws {
        var s = LockState(now: t0)
        try s.requestUnlock(reason: "work reason, really", now: t0)
        #expect(s.phase(now: t0.addingTimeInterval(3600)) == .waiting(until: t0.addingTimeInterval(86_400)))
        #expect(!s.isWindowOpen(now: t0.addingTimeInterval(86_399)))
        #expect(s.isWindowOpen(now: t0.addingTimeInterval(86_400)))
        #expect(s.isWindowOpen(now: t0.addingTimeInterval(86_400 + 3_599)))
        let later = t0.addingTimeInterval(86_400 + 3_600)
        #expect(s.phase(now: later) == .locked)
        s.tidy(now: later)
        #expect(s.unlockRequestedAt == nil)
    }

    @Test func nothingLoosensWhileLocked() throws {
        var s = LockState(now: t0)
        #expect(throws: LockState.LockError.windowClosed) { try s.pause(now: t0) }
        #expect(throws: LockState.LockError.windowClosed) { try s.requireWindow(now: t0) }
        try s.requestUnlock(reason: "work reason, really", now: t0)
        // Still inside the 24-hour wait.
        #expect(throws: LockState.LockError.windowClosed) { try s.pause(now: t0.addingTimeInterval(1000)) }
    }

    @Test func pauseUsesUpTheWindowAndEnds() throws {
        var s = LockState(now: t0)
        try s.requestUnlock(reason: "work reason, really", now: t0)
        let open = t0.addingTimeInterval(86_400 + 10)
        try s.pause(now: open)
        #expect(s.isPaused(now: open.addingTimeInterval(60)))
        #expect(s.phase(now: open) == .locked)
        #expect(!s.isPaused(now: open.addingTimeInterval(3_601)))
    }

    @Test func cancelAlwaysAllowed() throws {
        var s = LockState(now: t0)
        try s.requestUnlock(reason: "work reason, really", now: t0)
        s.cancelUnlock()
        #expect(s.phase(now: t0.addingTimeInterval(90_000)) == .locked)
    }

    @Test func tamperResetsStreak() {
        var s = LockState(now: t0)
        let later = t0.addingTimeInterval(5 * 86_400)
        #expect(s.streakDays(now: later) == 5)
        s.recordTamper("Hosts file was edited", now: later)
        #expect(s.streakDays(now: later) == 0)
        #expect(s.tamperLog.count == 1)
    }

    @Test func dnsRescueLimitedToThreeADay() throws {
        var s = LockState(now: t0)
        for i in 0..<3 { try s.startDNSRescue(now: t0.addingTimeInterval(Double(i) * 600)) }
        #expect(throws: LockState.LockError.rescueLimitReached) { try s.startDNSRescue(now: t0.addingTimeInterval(2000)) }
        try s.startDNSRescue(now: t0.addingTimeInterval(90_000))
    }

    @Test func doubleClickUsesOneRescue() throws {
        var s = LockState(now: t0)
        try s.startDNSRescue(now: t0)
        try s.startDNSRescue(now: t0.addingTimeInterval(5))
        #expect(s.dnsRescueHistory.count == 1)
        #expect(s.dnsRescueUntil == t0.addingTimeInterval(LockState.dnsRescueDuration))
    }

    @Test func stateRoundTripsThroughJSON() throws {
        var s = LockState(now: t0)
        try s.requestUnlock(reason: "work reason, really", now: t0)
        let data = try CalmJSON.encoder.encode(s)
        #expect(try CalmJSON.decoder.decode(LockState.self, from: data) == s)
    }
}

struct BlocklistTests {
    @Test func normalize() {
        #expect(Blocklists.normalize("https://WWW.Instagram.com/reels/abc?x=1") == "www.instagram.com")
        #expect(Blocklists.normalize("  x.com:443 ") == "x.com")
        #expect(Blocklists.normalize("user@example.org/path") == "example.org")
        #expect(Blocklists.normalize("not a site") == nil)
        #expect(Blocklists.normalize("localhost") == nil)
        #expect(Blocklists.normalize("bad..com") == nil)
    }

    @Test(arguments: ["x.com", "www.x.com", "twitter.com", "instagram.com", "www.instagram.com",
                      "hotstar.com", "jiohotstar.com", "www.jiohotstar.com", "mask.icloud.com"])
    func requiredSiteIsBlocked(_ domain: String) {
        #expect(CalmSettings().activeSites.contains(domain))
    }

    @Test func addAndRemoveSite() {
        var s = CalmSettings()
        do { let ok = s.addSite("https://youtube.com/watch"); #expect(ok) }
        #expect(s.activeSites.contains("youtube.com"))
        #expect(s.activeSites.contains("www.youtube.com"))
        do { let ok = s.removeSite("instagram.com"); #expect(ok) }
        #expect(!s.activeSites.contains("instagram.com"))
        #expect(!s.activeSites.contains("www.instagram.com"))
        // Adding it back undoes the removal.
        do { let ok = s.addSite("instagram.com"); #expect(ok) }
        #expect(s.activeSites.contains("www.instagram.com"))
    }

    @Test func apps() {
        var s = CalmSettings()
        #expect(s.activeApps.contains("org.mozilla.firefox"))
        #expect(s.activeApps.contains("com.burbn.instagram"))
        // Chrome is allowed when its lock profile is installed.
        #expect(!s.activeApps.contains("com.google.Chrome"))
        do { let ok = s.addApp("not an id"); #expect(!ok) }
        do { let ok = s.addApp("com.example.Game"); #expect(ok) }
        #expect(s.activeApps.contains("com.example.Game"))
    }

    @Test func parseHostsList() {
        let text = "# comment\n0.0.0.0 bad.com\n127.0.0.1 localhost\n0.0.0.0 a.com b.com # trailing\n\n"
        #expect(Blocklists.parseHostsList(text) == ["bad.com", "a.com", "b.com"])
    }

    @Test func oldSettingsFileStillLoads() throws {
        let json = Data(#"{"extraSites":["reddit.com"]}"#.utf8)
        let s = try CalmJSON.decoder.decode(CalmSettings.self, from: json)
        #expect(s.extraSites == ["reddit.com"])
        #expect(!s.firewallLoaded)
    }
}

struct HostsFileTests {
    let original = "127.0.0.1\tlocalhost\n255.255.255.255\tbroadcasthost\n::1             localhost\n"

    @Test func applyKeepsOriginalAndIsIntact() {
        let section = HostsFile.section(primary: ["x.com"], extra: ["bad.com"])
        let out = HostsFile.apply(section: section, to: original)
        #expect(out.hasPrefix(original))
        #expect(out.contains("0.0.0.0 x.com\n:: x.com\n"))
        #expect(out.contains("0.0.0.0 bad.com\n"))
        #expect(!out.contains(":: bad.com"))
        #expect(HostsFile.isIntact(out, expectedSection: section))
    }

    @Test func applyTwiceDoesNotDuplicate() {
        let section = HostsFile.section(primary: ["x.com"], extra: [])
        let once = HostsFile.apply(section: section, to: original)
        #expect(HostsFile.apply(section: section, to: once) == once)
    }

    @Test func stripRestoresOriginal() {
        let section = HostsFile.section(primary: ["x.com"], extra: [])
        #expect(HostsFile.strip(HostsFile.apply(section: section, to: original)) == original)
    }

    @Test func detectsEdits() {
        let section = HostsFile.section(primary: ["x.com", "instagram.com"], extra: [])
        let good = HostsFile.apply(section: section, to: original)
        let edited = good.replacingOccurrences(of: "0.0.0.0 instagram.com\n", with: "")
        #expect(!HostsFile.isIntact(edited, expectedSection: section))
        #expect(HostsFile.extractSection(edited).map(HostsFile.fingerprint) != HostsFile.fingerprint(section))
        let noEnd = good.replacingOccurrences(of: HostsFile.endMarker, with: "")
        #expect(!HostsFile.isIntact(noEnd, expectedSection: section))
        #expect(HostsFile.strip(noEnd) == original)
    }

    @Test func fingerprintIsStable() {
        #expect(HostsFile.fingerprint("abc") == HostsFile.fingerprint("abc"))
        #expect(HostsFile.fingerprint("abc") != HostsFile.fingerprint("abd"))
    }
}

struct ProfileAndSpotifyTests {
    @Test func chromeProfile() throws {
        let data = try ChromeProfile.build(removalPassword: "abcd-efgh-jkmn", blockedSites: ["x.com"])
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["PayloadType"] as? String == "Configuration")
        let content = try #require(plist["PayloadContent"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[1]["RemovalPassword"] as? String == "abcd-efgh-jkmn")
        let policies = ChromeProfile.chromePolicies(blockedSites: ["x.com"])
        #expect(policies["IncognitoModeAvailability"] as? Int == 1)
        #expect(policies["DnsOverHttpsMode"] as? String == "off")
    }

    @Test func randomPassword() {
        let p = ChromeProfile.randomPassword()
        #expect(p.count == 14)
        #expect(p != ChromeProfile.randomPassword())
    }

    @Test func spotifyLinks() {
        let uri = "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
        #expect(Spotify.playlistURI(from: "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc") == uri)
        #expect(Spotify.playlistURI(from: "https://open.spotify.com/intl-en/playlist/37i9dQZF1DXcBWIGoYBM5M") == uri)
        #expect(Spotify.playlistURI(from: uri) == uri)
        #expect(Spotify.playlistURI(from: "https://open.spotify.com/album/1234567890abc") == nil)
        #expect(Spotify.playlistURI(from: "hello") == nil)
    }
}

struct UpdateTests {
    @Test func versionOrder() {
        #expect(CalmUpdate.isNewer("0.2.0", than: "0.1.0"))
        #expect(CalmUpdate.isNewer("0.10.0", than: "0.9.9"))
        #expect(CalmUpdate.isNewer("1.0", than: "0.9.9"))
        #expect(!CalmUpdate.isNewer("0.2.0", than: "0.2.0"))
        #expect(!CalmUpdate.isNewer("0.2", than: "0.2.0"))
        #expect(!CalmUpdate.isNewer("0.1.9", than: "0.2.0"))
    }

    @Test func picksNewestCalmRelease() {
        let json = """
        [
          {"tag_name":"v9.9.9","draft":false,"prerelease":false,"body":"RAG app","assets":[
            {"name":"Calm.pkg","browser_download_url":"https://example.com/rag.pkg"}]},
          {"tag_name":"calm-v0.4.0","draft":true,"prerelease":false,"assets":[
            {"name":"Calm.pkg","browser_download_url":"https://example.com/draft.pkg"}]},
          {"tag_name":"calm-v0.3.0","draft":false,"prerelease":false,"body":"Fixes","assets":[
            {"name":"Calm.pkg","browser_download_url":"https://example.com/3.pkg","digest":"sha256:ABCD"}]},
          {"tag_name":"calm-v0.2.0","draft":false,"prerelease":false,"assets":[
            {"name":"Calm.pkg","browser_download_url":"https://example.com/2.pkg"}]},
          {"tag_name":"calm-v0.5.0","draft":false,"prerelease":false,"assets":[]}
        ]
        """.data(using: .utf8)!
        let c = CalmUpdate.newest(fromReleasesJSON: json, current: "0.1.0")
        #expect(c?.version == "0.3.0")
        #expect(c?.downloadURL.absoluteString == "https://example.com/3.pkg")
        #expect(c?.sha256 == "abcd")
        #expect(CalmUpdate.newest(fromReleasesJSON: json, current: "0.3.0") == nil)
        #expect(CalmUpdate.newest(fromReleasesJSON: Data("oops".utf8), current: "0.1.0") == nil)
    }
}

struct ShowAllowanceTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Kolkata")!; return c }()
    // 2027-01-15 10:00 IST
    var morning: Date { cal.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 10))! }

    @Test func oneSessionADay() throws {
        var s = LockState(now: morning)
        try s.startShowSession(now: morning, calendar: cal)
        #expect(s.isShowSessionActive(now: morning.addingTimeInterval(39 * 60)))
        #expect(!s.isShowSessionActive(now: morning.addingTimeInterval(41 * 60)))
        // Clicking again during the session is fine; after it, not until tomorrow.
        try s.startShowSession(now: morning.addingTimeInterval(60), calendar: cal)
        #expect(throws: LockState.LockError.showUsedToday) {
            try s.startShowSession(now: morning.addingTimeInterval(3 * 3600), calendar: cal)
        }
        let tomorrow = cal.date(from: DateComponents(year: 2027, month: 1, day: 16, hour: 7))!
        try s.startShowSession(now: tomorrow, calendar: cal)
        #expect(s.isShowSessionActive(now: tomorrow))
    }

    @Test func oneEpisodePerSession() throws {
        var s = LockState(now: morning)
        #expect(throws: LockState.LockError.showNotActive) { try s.chooseEpisode("100", now: morning) }
        try s.startShowSession(now: morning, calendar: cal)
        try s.chooseEpisode("100", now: morning)
        try s.chooseEpisode("100", now: morning.addingTimeInterval(600))   // same episode again is fine
        #expect(throws: LockState.LockError.oneEpisodePerDay) { try s.chooseEpisode("101", now: morning.addingTimeInterval(700)) }
    }

    @Test func oldStateStillLoads() throws {
        let s = LockState(now: morning)
        var json = try JSONSerialization.jsonObject(with: CalmJSON.encoder.encode(s)) as! [String: Any]
        json.removeValue(forKey: "showSessionStart")
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try CalmJSON.decoder.decode(LockState.self, from: data).showSessionStart == nil)
    }

    @Test func showSitesCoverHotstar() {
        #expect(Blocklists.showSites.contains("www.hotstar.com"))
        #expect(Blocklists.showSites.contains("jiohotstar.com"))
        #expect(!Blocklists.showSites.contains("instagram.com"))
    }
}

struct ShowRulesTests {
    func d(_ s: String) -> ShowRules.Decision { ShowRules.decide(URL(string: s)!) }

    @Test func seriesAndEpisodes() {
        #expect(d("https://www.hotstar.com/in/shows/devon-ke-dev-mahadev/8001") == .allow)
        #expect(d("https://www.hotstar.com/in/shows/devon-ke-dev-mahadev/8001/the-birth-of-sati/1000123456/watch") == .episode("1000123456"))
        #expect(d("https://www.hotstar.com/shows/devon-ke-dev-mahadev/8001/x/42") == .episode("42"))
        #expect(d("https://www.jiohotstar.com/in/shows/devon-ke-dev-mahadev/8001") == .allow)
    }

    @Test func blocksEverythingElse() {
        #expect(d("https://www.hotstar.com/in/shows/anupamaa/1260022017") == .block)
        #expect(d("https://www.hotstar.com/in/home") == .block)
        #expect(d("https://www.hotstar.com/in/movies/x/1") == .block)
        #expect(d("https://www.hotstar.com/in/explore?search_query=cricket") == .block)
        #expect(d("https://www.youtube.com/watch?v=1") == .block)
        #expect(d("http://www.hotstar.com/in/shows/devon-ke-dev-mahadev/8001") == .block)
        #expect(d("https://evilhotstar.com/in/shows/devon-ke-dev-mahadev/8001") == .block)
    }

    @Test func searchAndSignInAllowed() {
        #expect(d("https://www.hotstar.com/in/explore?search_query=Devon%20Ke%20Dev%20Mahadev") == .allow)
        #expect(d("https://www.hotstar.com/in/onboarding?ref=x") == .allow)
        #expect(d("https://www.hotstar.com/in/profiles") == .allow)
    }
}

struct BrowserExtensionTests {
    func prefs(_ entries: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["extensions": ["settings": entries]])
    }
    let path = "/Library/Application Support/Calm/BlankPage"

    @Test func installedAndOn() {
        #expect(BrowserExtensions.isInstalled(securePreferences: prefs(["abc": ["path": path, "location": 4, "disable_reasons": []]]), extensionPath: path))
    }
    @Test func turnedOffCountsAsMissing() {
        #expect(!BrowserExtensions.isInstalled(securePreferences: prefs(["abc": ["path": path, "disable_reasons": [1]]]), extensionPath: path))
        #expect(!BrowserExtensions.isInstalled(securePreferences: prefs(["abc": ["path": path, "state": 0]]), extensionPath: path))
    }
    @Test func otherExtensionsDontCount() {
        #expect(!BrowserExtensions.isInstalled(securePreferences: prefs(["x": ["path": "x/1.0_0"]]), extensionPath: path))
        #expect(!BrowserExtensions.isInstalled(securePreferences: Data("not json".utf8), extensionPath: path))
    }
}

struct ShowBrowserTests {
    @Test func everyCommonBrowserClosesDuringShow() {
        for id in ["ai.perplexity.comet", "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser"] {
            #expect(Blocklists.browsersClosedDuringShow.contains(id))
        }
        // Calm's own window lives in the menu-bar app, which must never be closed.
        #expect(!Blocklists.browsersClosedDuringShow.contains("com.calm.bar"))
    }
}

struct EndShowTests {
    @Test func endingEarlyClosesTheSessionAndUsesTheDay() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let t = c.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 10))!
        var s = LockState(now: t)
        try s.startShowSession(now: t, calendar: c)
        s.endShowSession(now: t.addingTimeInterval(300))
        #expect(!s.isShowSessionActive(now: t.addingTimeInterval(301)))
        #expect(s.showUsedToday(now: t.addingTimeInterval(400), calendar: c))
    }

    @Test func extensionNeedsFileAccessToBeReady() {
        let path = "/Library/Application Support/Calm/BlankPage"
        func prefs(_ e: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: ["extensions": ["settings": ["a": e]]]) }
        #expect(BrowserExtensions.state(securePreferences: prefs(["path": path]), extensionPath: path) == .installed)
        #expect(BrowserExtensions.state(securePreferences: prefs(["path": path, "newAllowFileAccess": true]), extensionPath: path) == .ready)
        #expect(BrowserExtensions.state(securePreferences: prefs(["path": "/x"]), extensionPath: path) == .missing)
    }
}

struct WidgetDataTests {
    @Test func streakAndGoal() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let w = WidgetData(streakStart: start, protected: true, blockedSiteCount: 10, track: nil)
        #expect(w.streakDays(now: start.addingTimeInterval(4.5 * 86_400)) == 4)
        let g = w.goal(now: start.addingTimeInterval(3.5 * 86_400))
        #expect(g.days == 7)
        #expect(abs(g.progress - 0.5) < 0.001)
    }
    @Test func podcastSubtitleUsesShow() {
        #expect(WidgetData.Track(title: "Ep 1", artist: "", album: "Figuring Out", playing: true).subtitle == "Figuring Out")
    }
    @Test func roundTrips() throws {
        let w = WidgetData(streakStart: Date(timeIntervalSince1970: 1_800_000_000), protected: true, blockedSiteCount: 3,
                           track: .init(title: "a", artist: "b", album: "c", playing: false, artworkFile: "x.jpg"))
        #expect(try CalmJSON.decoder.decode(WidgetData.self, from: CalmJSON.encoder.encode(w)) == w)
    }
}
