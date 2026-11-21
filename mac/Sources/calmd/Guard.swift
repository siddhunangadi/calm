import Foundation
import CalmShared
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The always-on guard. Every few seconds it checks that the blocking is in place and fixes it if not.
final class Guard {
    private var state: LockState
    private var settings: CalmSettings
    private let removalPassword: String
    private let adultDomains: [String]

    private var tick = 0
    private var lastMessage: String?
    /// Size + date of /etc/hosts right after we last checked it, to skip re-reading an unchanged file.
    private var hostsSignature: String?
    /// Set when blocking was relaxed on purpose (pause / DNS rescue), so turning it back on isn't "tampering".
    private var skipTamperCheck = true
    private var relaxed = false
    /// True while DNS is on the router for a Wi-Fi login rescue, until the filter is put back.
    /// Kept apart from skipTamperCheck, which is cleared every tick while DNS is only checked every third.
    private var dnsRescueInEffect = false
    private var bundleIDCache: [String: String] = [:]
    private var profileDropCreatedAt: Date?
    private var blankPageMissing: [String] = []

    init() {
        let now = Date()
        state = Self.load(LockState.self, from: CalmPaths.stateFile) ?? LockState(now: now)
        settings = Self.load(CalmSettings.self, from: CalmPaths.settingsFile) ?? CalmSettings()
        if let saved = try? String(contentsOfFile: CalmPaths.secretFile, encoding: .utf8), !saved.isEmpty {
            removalPassword = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            removalPassword = ChromeProfile.randomPassword()
            try? writeFile(CalmPaths.secretFile, Data(removalPassword.utf8), mode: 0o600)
        }
        let adultText = (try? String(contentsOfFile: CalmPaths.adultHostsFile, encoding: .utf8)) ?? ""
        adultDomains = Blocklists.parseHostsList(adultText)
        logLine("calmd started. \(adultDomains.count) adult domains loaded.")
    }

    // MARK: - Main loop

    func run() -> Never {
        while true {
            #if canImport(ObjectiveC)
            autoreleasepool { step() }
            #else
            step()
            #endif
            Thread.sleep(forTimeInterval: 3)
        }
    }

    private func step() {
        let now = Date()
        state.tidy(now: now)
        processInbox(now: now)

        if state.isPaused(now: now) {
            if !relaxed { relaxAll() }
        } else {
            if relaxed { relaxed = false; skipTamperCheck = true }
            enforceHosts(now: now)
            if tick % 3 == 0 { enforceDNS(now: now) }
            if tick % 5 == 0 { enforceFirewall(now: now) }
            killBlockedApps()
            skipTamperCheck = false
        }
        if tick % 5 == 0 { checkChromeProfile(now: now) }
        if tick % 20 == 0 { protectOwnFiles() }
        if tick % 20 == 0 { checkBlankPageExtension(now: now) }

        save()
        writeStatus(now: now)
        tick += 1
    }

    // MARK: - Requests from the menu-bar app

    private func processInbox(now: Date) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: CalmPaths.inboxDir) else { return }
        // The app writes "x.tmp" first and renames it to "x.json" when complete.
        for name in names.sorted() where name.hasSuffix(".json") {
            let path = CalmPaths.inboxDir + "/" + name
            defer { try? fm.removeItem(atPath: path) }
            // Only small, plain files (no links to other files).
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.size] as? NSNumber)?.intValue ?? 0 < 16_384,
                  let data = fm.contents(atPath: path),
                  let req = try? CalmJSON.decoder.decode(CalmRequest.self, from: data) else { continue }
            handle(req, now: now)
        }
    }

    private func handle(_ req: CalmRequest, now: Date) {
        let value = req.value ?? ""
        do {
            switch req.kind {
            case .requestUnlock:
                try state.requestUnlock(reason: value, now: now)
                lastMessage = "Unlock requested. Come back in 24 hours."
            case .cancelUnlock:
                state.cancelUnlock()
                lastMessage = "Unlock cancelled. Good choice."
            case .addSite:
                lastMessage = settings.addSite(value) ? "Now blocking \(value)." : "That doesn't look like a website."
            case .addApp:
                lastMessage = settings.addApp(value) ? "Now blocking app \(value)." : "That doesn't look like an app id."
            case .removeSite:
                try state.requireWindow(now: now)
                lastMessage = settings.removeSite(value) ? "Removed \(value)." : "That doesn't look like a website."
            case .removeApp:
                try state.requireWindow(now: now)
                lastMessage = settings.removeApp(value) ? "Unblocked app \(value)." : "That doesn't look like an app id."
            case .pause:
                try state.pause(now: now)
                lastMessage = "Paused for 1 hour. Blocking returns by itself."
            case .uninstall:
                try state.requireWindow(now: now)
                uninstall()
            case .dnsRescue:
                try state.startDNSRescue(now: now)
                skipTamperCheck = true
                lastMessage = "Router DNS for 5 minutes so the Wi-Fi login page can load. Sites stay blocked."
            case .prepareChromeProfile:
                let data = try ChromeProfile.build(removalPassword: removalPassword,
                                                   blockedSites: Blocklists.chromeURLBlocklist + settings.extraSites)
                try writeFile(CalmPaths.profileDrop, data, mode: 0o644)
                profileDropCreatedAt = now
                lastMessage = "Chrome lock profile ready. Approve it in System Settings."
            case .startShow:
                try state.startShowSession(now: now)
                lastMessage = "Devon Ke Dev Mahadev: today's 40 minutes have started."
            case .showEpisode:
                try state.chooseEpisode(value, now: now)
            }
        } catch let e as LockState.LockError {
            switch e {
            case .needsReason: lastMessage = "Please write a real reason (at least 10 characters)."
            case .alreadyRequested: lastMessage = "An unlock is already in progress."
            case .windowClosed: lastMessage = "Locked. Request an unlock and wait 24 hours first."
            case .rescueLimitReached: lastMessage = "No Wi-Fi rescues left today."
            case .showUsedToday: lastMessage = "Today's Mahadev episode is done. Next one tomorrow."
            case .showNotActive: lastMessage = "Start today's Mahadev session first."
            case .oneEpisodePerDay: lastMessage = "One episode a day. Today's is already chosen."
            }
        } catch {
            lastMessage = "Something went wrong: \(error)"
        }
        logLine("request \(req.kind.rawValue): \(lastMessage ?? "")")
    }

    // MARK: - Hosts file

    private func expectedHostsSection() -> String {
        let removed = Set(settings.removedSites)
        // During today's Mahadev session Hotstar is reachable (every browser is closed meanwhile).
        let open = state.isShowSessionActive(now: Date()) ? Blocklists.showSites : []
        return HostsFile.section(primary: settings.activeSites.filter { !open.contains($0) }, extra: adultDomains.filter { !removed.contains($0) })
    }

    private func currentHostsSignature() -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: CalmPaths.hostsFile) else { return nil }
        let size = (a[.size] as? NSNumber)?.intValue ?? -1
        let date = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(date)"
    }

    private func enforceHosts(now: Date) {
        let expected = expectedHostsSection()
        let expectedPrint = HostsFile.fingerprint(expected)
        // Fast path: file untouched since our last check and the rules haven't changed.
        if let sig = currentHostsSignature(), sig == hostsSignature, settings.hostsSectionFingerprint == expectedPrint {
            return
        }
        let contents = (try? String(contentsOfFile: CalmPaths.hostsFile, encoding: .utf8)) ?? ""
        if HostsFile.isIntact(contents, expectedSection: expected) {
            settings.hostsSectionFingerprint = expectedPrint
            hostsSignature = currentHostsSignature()
            return
        }
        // Not matching. If the section isn't what we last wrote, someone edited it.
        if !skipTamperCheck, let last = settings.hostsSectionFingerprint {
            let found = HostsFile.extractSection(contents).map(HostsFile.fingerprint)
            if found != last || contents.components(separatedBy: HostsFile.beginMarker).count != 2 {
                tamper("Hosts file was edited", now: now)
            }
        }
        setFlag("nouchg", CalmPaths.hostsFile)
        do {
            try writeFile(CalmPaths.hostsFile, Data(HostsFile.apply(section: expected, to: contents).utf8), mode: 0o644)
            settings.hostsSectionFingerprint = expectedPrint
        } catch {
            logLine("could not write hosts: \(error)")
        }
        setFlag("uchg", CalmPaths.hostsFile)
        hostsSignature = currentHostsSignature()
        flushDNSCache()
    }

    // MARK: - DNS filter

    private func networkServices() -> [String] {
        let out = sh("/usr/sbin/networksetup", ["-listallnetworkservices"]).out
        return out.split(whereSeparator: \.isNewline).dropFirst().map {
            var s = String($0)
            if s.hasPrefix("*") { s.removeFirst() }
            return s.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    private func enforceDNS(now: Date) {
        let rescue = state.isDNSRescueActive(now: now)
        let desired = rescue ? [] : Blocklists.filterDNS
        var changed = false
        for service in networkServices() {
            let out = sh("/usr/sbin/networksetup", ["-getdnsservers", service]).out
            let current = out.contains("aren't any DNS Servers") ? [] :
                out.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard Set(current) != Set(desired) else {
                if !rescue && !settings.managedNetworkServices.contains(service) {
                    settings.managedNetworkServices.append(service)
                }
                continue
            }
            if !rescue && !skipTamperCheck && !dnsRescueInEffect && settings.managedNetworkServices.contains(service) {
                tamper("DNS was changed on \(service)", now: now)
            }
            sh("/usr/sbin/networksetup", ["-setdnsservers", service] + (desired.isEmpty ? ["Empty"] : desired))
            if !rescue && !settings.managedNetworkServices.contains(service) {
                settings.managedNetworkServices.append(service)
            }
            changed = true
        }
        if rescue { skipTamperCheck = true }
        // Once the filter is back on every service, later changes count as tampering again.
        dnsRescueInEffect = rescue
        if changed { flushDNSCache() }
    }

    // MARK: - Firewall (closes secure-DNS back doors)

    private var firewallRules: String {
        let table = Blocklists.bypassDNSServers.joined(separator: ", ")
        return """
        table <calm_bypass_dns> const { \(table) }
        block drop out quick proto { tcp, udp } from any to any port 853
        block drop out quick proto { tcp, udp } from any to <calm_bypass_dns> port { 53, 443 }

        """
    }

    private func enforceFirewall(now: Date) {
        let enabled = sh("/sbin/pfctl", ["-s", "info"]).out.contains("Status: Enabled")
        let loaded = sh("/sbin/pfctl", ["-a", CalmPaths.pfAnchor, "-s", "rules"]).out.contains("853")
        if enabled && loaded { settings.firewallLoaded = true; return }
        if settings.firewallLoaded && !skipTamperCheck { tamper("Firewall rules were removed", now: now) }
        let rulesPath = CalmPaths.privateDir + "/pf.rules"
        try? writeFile(rulesPath, Data(firewallRules.utf8), mode: 0o600)
        let load = sh("/sbin/pfctl", ["-a", CalmPaths.pfAnchor, "-f", rulesPath])
        if !enabled { sh("/sbin/pfctl", ["-E"]) }
        settings.firewallLoaded = load.code == 0
        if load.code != 0 { logLine("pfctl load failed: \(load.out)") }
    }

    // MARK: - Apps

    /// Finds the app bundle a running program belongs to and returns its bundle id.
    private func bundleID(forExecutable path: String) -> String? {
        guard let r = path.range(of: ".app/", options: .backwards) else { return nil }
        let bundle = String(path[..<r.lowerBound]) + ".app"
        if let cached = bundleIDCache[bundle] { return cached.isEmpty ? nil : cached }
        var id = ""
        for plist in [bundle + "/Contents/Info.plist", bundle + "/Info.plist"] {
            if let d = NSDictionary(contentsOfFile: plist), let b = d["CFBundleIdentifier"] as? String { id = b; break }
        }
        bundleIDCache[bundle] = id
        return id.isEmpty ? nil : id
    }

    private func killBlockedApps() {
        var blocked = settings.activeApps
        if !chromeProfileInstalled() { blocked.insert(Blocklists.chromeBundleID) }
        // Hotstar is open only for Calm's Mahadev window, so no browser may run meanwhile.
        if state.isShowSessionActive(now: Date()) { blocked.formUnion(Blocklists.browsersClosedDuringShow) }
        let out = sh("/bin/ps", ["-axww", "-o", "pid=,comm="]).out
        for line in out.split(whereSeparator: \.isNewline) {
            let trimmed = line.drop(while: { $0 == " " })
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { continue }
            let path = String(trimmed[trimmed.index(after: space)...])
            guard path.contains(".app/"), let id = bundleID(forExecutable: path), blocked.contains(id) else { continue }
            kill(pid, SIGKILL)
            logLine("quit blocked app \(id)")
        }
    }

    // MARK: - Black-page browser extension

    /// Once the extension has been seen in a browser profile, removing or turning it off is tampering.
    private func checkBlankPageExtension(now: Date) {
        guard let uid = consoleUserID(), let pw = getpwuid(uid_t(uid)), let homeC = pw.pointee.pw_dir else { return }
        let home = String(cString: homeC)
        var missing: [String] = []
        for browser in BrowserExtensions.browsers {
            let dir = home + "/" + browser.dataDir
            let profiles = BrowserExtensions.profiles(browserDir: dir)
            if profiles.isEmpty { continue }
            var anyMissing = false
            for profile in profiles {
                let key = "\(browser.name)/\(profile)"
                guard let data = FileManager.default.contents(atPath: dir + "/" + profile + "/Secure Preferences") else { continue }
                if BrowserExtensions.isInstalled(securePreferences: data) {
                    if !settings.blankPageSeen.contains(key) { settings.blankPageSeen.append(key) }
                } else {
                    anyMissing = true
                    if settings.blankPageSeen.contains(key) {
                        settings.blankPageSeen.removeAll { $0 == key }
                        tamper("Calm extension was removed from \(browser.name)", now: now)
                    }
                }
            }
            if anyMissing { missing.append(browser.name) }
        }
        blankPageMissing = missing
    }

    // MARK: - Chrome lock profile

    private func chromeProfileInstalled() -> Bool {
        guard let d = NSDictionary(contentsOfFile: CalmPaths.chromeManagedPrefs) else { return false }
        return (d["IncognitoModeAvailability"] as? NSNumber)?.intValue == 1
    }

    private func checkChromeProfile(now: Date) {
        let installed = chromeProfileInstalled()
        if installed {
            settings.chromeProfileSeen = true
        } else if settings.chromeProfileSeen {
            settings.chromeProfileSeen = false
            tamper("Chrome lock profile was removed (Chrome is blocked until it is back)", now: now)
        }
        // Don't leave the profile (which contains the removal password) lying around.
        if let created = profileDropCreatedAt, installed || now.timeIntervalSince(created) > 15 * 60 {
            try? FileManager.default.removeItem(atPath: CalmPaths.profileDrop)
            profileDropCreatedAt = nil
        }
    }

    // MARK: - Pause / uninstall

    /// Takes all blocking off (used by "Pause 1 hour" and by uninstall).
    private func relaxAll() {
        let contents = (try? String(contentsOfFile: CalmPaths.hostsFile, encoding: .utf8)) ?? ""
        setFlag("nouchg", CalmPaths.hostsFile)
        try? writeFile(CalmPaths.hostsFile, Data(HostsFile.strip(contents).utf8), mode: 0o644)
        settings.hostsSectionFingerprint = nil
        hostsSignature = nil
        for service in settings.managedNetworkServices {
            sh("/usr/sbin/networksetup", ["-setdnsservers", service, "Empty"])
        }
        sh("/sbin/pfctl", ["-a", CalmPaths.pfAnchor, "-F", "all"])
        settings.firewallLoaded = false
        flushDNSCache()
        relaxed = true
        logLine("blocking relaxed (pause or uninstall)")
    }

    private func uninstall() {
        logLine("uninstalling after the 24-hour wait")
        relaxAll()
        settings.managedNetworkServices = []
        if let uid = consoleUserID() {
            sh("/bin/launchctl", ["bootout", "gui/\(uid)/\(CalmPaths.agentLabel)"])
        }
        for path in [CalmPaths.daemonBinary, CalmPaths.daemonPlist, CalmPaths.agentPlist, CalmPaths.appBundle,
                     CalmPaths.supportDir, CalmPaths.profileDrop] {
            setFlag("noschg", path, recursive: true)
            setFlag("nouchg", path, recursive: true)
            try? FileManager.default.removeItem(atPath: path)
        }
        sh("/usr/sbin/pkgutil", ["--forget", "com.calm.pkg"])
        logLine("uninstalled. The Chrome profile stays until you remove it in System Settings with the password.")
        // Exiting with 0 tells launchd not to restart us (KeepAlive: SuccessfulExit = false).
        sh("/bin/launchctl", ["bootout", "system/\(CalmPaths.daemonLabel)"])
        exit(0)
    }

    private func consoleUserID() -> Int? {
        let a = try? FileManager.default.attributesOfItem(atPath: "/dev/console")
        guard let uid = (a?[.ownerAccountID] as? NSNumber)?.intValue, uid != 0 else { return nil }
        return uid
    }

    /// The "system immutable" flag makes normal deletes fail, even with sudo rm.
    private func protectOwnFiles() {
        for path in [CalmPaths.daemonBinary, CalmPaths.daemonPlist, CalmPaths.agentPlist] {
            setFlag("schg", path)
        }
        setFlag("schg", CalmPaths.appBundle, recursive: true)
    }

    // MARK: - Tampering, saving, status

    private func tamper(_ what: String, now: Date) {
        state.recordTamper(what, now: now)
        lastMessage = "\(what). Fixed it, and your streak restarted."
        logLine("TAMPER: \(what)")
    }

    private static func load<T: Decodable>(_ type: T.Type, from path: String) -> T? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? CalmJSON.decoder.decode(type, from: data)
    }

    private func save() {
        if let d = try? CalmJSON.encoder.encode(state) { try? writeFile(CalmPaths.stateFile, d, mode: 0o600) }
        if let d = try? CalmJSON.encoder.encode(settings) { try? writeFile(CalmPaths.settingsFile, d, mode: 0o600) }
    }

    private func writeStatus(now: Date) {
        let phase: CalmStatus.Phase
        var ends: Date?
        if state.isPaused(now: now) {
            phase = .paused; ends = state.pausedUntil
        } else {
            switch state.phase(now: now) {
            case .locked: phase = .locked
            case .waiting(let until): phase = .waiting; ends = until
            case .window(let until): phase = .window; ends = until
            }
        }
        let status = CalmStatus(
            heartbeat: now, phase: phase, phaseEnds: ends, unlockReason: state.unlockReason,
            streakStart: state.streakStart, tamperLog: Array(state.tamperLog.suffix(10)),
            extraSites: settings.extraSites, removedSites: settings.removedSites, extraApps: settings.extraApps,
            blockedSiteCount: settings.activeSites.count + adultDomains.count,
            chromeProfileInstalled: chromeProfileInstalled(),
            dnsRescueUntil: state.dnsRescueUntil,
            dnsRescuesLeft: max(0, LockState.dnsRescuesPerDay - state.dnsRescueHistory.count),
            revealedRemovalPassword: phase == .window ? removalPassword : nil,
            lastMessage: lastMessage,
            showSessionEnds: state.showSessionEnds(now: now),
            showUsedToday: state.showUsedToday(now: now),
            showEpisodeID: state.isShowSessionActive(now: now) ? state.showEpisodeID : nil,
            blankPageMissing: blankPageMissing)
        if let d = try? CalmJSON.encoder.encode(status) { try? writeFile(CalmPaths.statusFile, d, mode: 0o644) }
    }
}
