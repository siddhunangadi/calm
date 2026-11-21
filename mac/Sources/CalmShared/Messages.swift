import Foundation

/// A request from the menu-bar app to the guard. The guard decides if it is allowed.
public struct CalmRequest: Codable, Equatable {
    public enum Kind: String, Codable {
        case requestUnlock, cancelUnlock
        case addSite, addApp            // always allowed: making it stricter is fine
        case removeSite, removeApp      // only in the unlock window
        case pause, uninstall           // only in the unlock window
        case dnsRescue                  // Wi-Fi login page help, limited
        case prepareChromeProfile       // put the Chrome lock profile where you can open it
        case startShow                  // today's Devon Ke Dev Mahadev session
        case showEpisode                // the episode chosen in it (value: episode id)
    }
    public var kind: Kind
    public var value: String?

    public init(_ kind: Kind, _ value: String? = nil) {
        self.kind = kind
        self.value = value
    }
}

/// Your own additions and removals. Kept in a root-only file.
public struct CalmSettings: Codable, Equatable {
    public var extraSites: [String] = []
    public var extraApps: [String] = []
    /// Built-in sites/apps you removed during an unlock window.
    public var removedSites: [String] = []
    public var removedApps: [String] = []
    /// Network services whose DNS Calm has set, so later changes count as tampering.
    public var managedNetworkServices: [String] = []
    /// True once the Chrome lock profile has been seen installed.
    public var chromeProfileSeen = false
    /// Fingerprint of the hosts section Calm last wrote (nil = not written / taken out on purpose).
    public var hostsSectionFingerprint: String?
    /// True while Calm's firewall rules are supposed to be loaded.
    public var firewallLoaded = false
    public init() {}

    // Missing keys fall back to defaults, so older settings files still load after an update.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        extraSites = try c.decodeIfPresent([String].self, forKey: .extraSites) ?? []
        extraApps = try c.decodeIfPresent([String].self, forKey: .extraApps) ?? []
        removedSites = try c.decodeIfPresent([String].self, forKey: .removedSites) ?? []
        removedApps = try c.decodeIfPresent([String].self, forKey: .removedApps) ?? []
        managedNetworkServices = try c.decodeIfPresent([String].self, forKey: .managedNetworkServices) ?? []
        chromeProfileSeen = try c.decodeIfPresent(Bool.self, forKey: .chromeProfileSeen) ?? false
        hostsSectionFingerprint = try c.decodeIfPresent(String.self, forKey: .hostsSectionFingerprint)
        firewallLoaded = try c.decodeIfPresent(Bool.self, forKey: .firewallLoaded) ?? false
    }

    public var activeSites: [String] {
        let removed = Set(removedSites)
        var seen = Set<String>()
        return (Blocklists.builtInSites + extraSites).flatMap { Blocklists.withWWW($0) }
            .filter { !removed.contains($0) && seen.insert($0).inserted }
    }

    public var activeApps: Set<String> {
        Set(Blocklists.blockedApps + extraApps).subtracting(removedApps)
    }

    public mutating func addSite(_ raw: String) -> Bool {
        guard let d = Blocklists.normalize(raw) else { return false }
        removedSites.removeAll { Blocklists.withWWW(d).contains($0) }
        if !extraSites.contains(d) && !Blocklists.builtInSites.contains(d) { extraSites.append(d) }
        return true
    }

    public mutating func removeSite(_ raw: String) -> Bool {
        guard let d = Blocklists.normalize(raw) else { return false }
        let variants = Blocklists.withWWW(d)
        extraSites.removeAll { variants.contains($0) }
        for v in variants where !removedSites.contains(v) { removedSites.append(v) }
        return true
    }

    public mutating func addApp(_ id: String) -> Bool {
        guard Blocklists.isBundleID(id) else { return false }
        removedApps.removeAll { $0 == id }
        if !extraApps.contains(id) && !Blocklists.blockedApps.contains(id) { extraApps.append(id) }
        return true
    }

    public mutating func removeApp(_ id: String) -> Bool {
        guard Blocklists.isBundleID(id) else { return false }
        extraApps.removeAll { $0 == id }
        if !removedApps.contains(id) { removedApps.append(id) }
        return true
    }
}

/// What the guard tells the menu-bar app (written every few seconds).
public struct CalmStatus: Codable, Equatable {
    public enum Phase: String, Codable { case locked, waiting, window, paused }
    public var heartbeat: Date
    public var phase: Phase
    /// When the current wait / window / pause ends.
    public var phaseEnds: Date?
    public var unlockReason: String?
    public var streakStart: Date
    public var tamperLog: [TamperEvent]
    public var extraSites: [String]
    public var removedSites: [String]
    public var extraApps: [String]
    public var blockedSiteCount: Int
    public var chromeProfileInstalled: Bool
    public var dnsRescueUntil: Date?
    public var dnsRescuesLeft: Int
    /// Shown only inside the unlock window, so you can remove the Chrome profile.
    public var revealedRemovalPassword: String?
    public var lastMessage: String?
    /// Devon Ke Dev Mahadev session (optional so older guards' status files still decode).
    public var showSessionEnds: Date?
    public var showUsedToday: Bool?
    public var showEpisodeID: String?

    public init(heartbeat: Date, phase: Phase, phaseEnds: Date?, unlockReason: String?, streakStart: Date,
                tamperLog: [TamperEvent], extraSites: [String], removedSites: [String], extraApps: [String],
                blockedSiteCount: Int, chromeProfileInstalled: Bool, dnsRescueUntil: Date?, dnsRescuesLeft: Int,
                revealedRemovalPassword: String?, lastMessage: String?,
                showSessionEnds: Date? = nil, showUsedToday: Bool? = nil, showEpisodeID: String? = nil) {
        self.showSessionEnds = showSessionEnds; self.showUsedToday = showUsedToday; self.showEpisodeID = showEpisodeID
        self.heartbeat = heartbeat; self.phase = phase; self.phaseEnds = phaseEnds
        self.unlockReason = unlockReason; self.streakStart = streakStart; self.tamperLog = tamperLog
        self.extraSites = extraSites; self.removedSites = removedSites; self.extraApps = extraApps
        self.blockedSiteCount = blockedSiteCount; self.chromeProfileInstalled = chromeProfileInstalled
        self.dnsRescueUntil = dnsRescueUntil; self.dnsRescuesLeft = dnsRescuesLeft
        self.revealedRemovalPassword = revealedRemovalPassword; self.lastMessage = lastMessage
    }
}

public enum CalmJSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
