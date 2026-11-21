import Foundation

/// The 24-hour self-lock. Pure logic (no files, no clock), so it is fully unit-tested.
public struct LockState: Codable, Equatable {
    public static let waitDuration: TimeInterval = 24 * 60 * 60
    public static let windowDuration: TimeInterval = 60 * 60
    public static let pauseDuration: TimeInterval = 60 * 60
    public static let dnsRescueDuration: TimeInterval = 5 * 60
    public static let dnsRescuesPerDay = 3
    /// Devon Ke Dev Mahadev: one session a day, long enough for one ~22-minute episode.
    public static let showSessionDuration: TimeInterval = 40 * 60

    public var installedAt: Date
    public var streakStart: Date
    public var unlockRequestedAt: Date?
    public var unlockReason: String?
    public var pausedUntil: Date?
    public var dnsRescueUntil: Date?
    public var dnsRescueHistory: [Date]
    public var tamperLog: [TamperEvent]
    /// Start of today's show session (optional, so older state files still load).
    public var showSessionStart: Date?
    /// The one episode chosen in that session.
    public var showEpisodeID: String?

    public init(now: Date) {
        installedAt = now
        streakStart = now
        dnsRescueHistory = []
        tamperLog = []
    }

    public enum Phase: Equatable {
        /// Normal. Nothing can be removed.
        case locked
        /// Unlock requested, still waiting.
        case waiting(until: Date)
        /// The 24 hours passed: you may remove sites, pause or uninstall until `until`.
        case window(until: Date)
    }

    public func phase(now: Date) -> Phase {
        guard let requested = unlockRequestedAt else { return .locked }
        let opens = requested.addingTimeInterval(Self.waitDuration)
        let closes = opens.addingTimeInterval(Self.windowDuration)
        if now < opens { return .waiting(until: opens) }
        if now < closes { return .window(until: closes) }
        return .locked
    }

    public func isWindowOpen(now: Date) -> Bool {
        if case .window = phase(now: now) { return true }
        return false
    }

    public func isPaused(now: Date) -> Bool {
        guard let p = pausedUntil else { return false }
        return now < p
    }

    public func isDNSRescueActive(now: Date) -> Bool {
        guard let r = dnsRescueUntil else { return false }
        return now < r
    }

    /// Clears an unused window after it closes, and an old pause, so the lock comes back by itself.
    public mutating func tidy(now: Date) {
        if let requested = unlockRequestedAt,
           now >= requested.addingTimeInterval(Self.waitDuration + Self.windowDuration) {
            unlockRequestedAt = nil
            unlockReason = nil
        }
        if let p = pausedUntil, now >= p { pausedUntil = nil }
        if let r = dnsRescueUntil, now >= r { dnsRescueUntil = nil }
        dnsRescueHistory.removeAll { now.timeIntervalSince($0) > 24 * 60 * 60 }
        if tamperLog.count > 50 { tamperLog.removeFirst(tamperLog.count - 50) }
    }

    public enum LockError: Error, Equatable {
        case needsReason, alreadyRequested, windowClosed, rescueLimitReached
        case showUsedToday, showNotActive, oneEpisodePerDay
    }

    // MARK: Show allowance (Devon Ke Dev Mahadev)

    public func isShowSessionActive(now: Date) -> Bool {
        guard let s = showSessionStart else { return false }
        return now >= s && now < s.addingTimeInterval(Self.showSessionDuration)
    }

    public func showSessionEnds(now: Date) -> Date? {
        isShowSessionActive(now: now) ? showSessionStart?.addingTimeInterval(Self.showSessionDuration) : nil
    }

    /// One session per calendar day.
    public func showUsedToday(now: Date, calendar: Calendar = .current) -> Bool {
        guard let s = showSessionStart else { return false }
        return calendar.isDate(s, inSameDayAs: now)
    }

    public mutating func startShowSession(now: Date, calendar: Calendar = .current) throws {
        if isShowSessionActive(now: now) { return }
        guard !showUsedToday(now: now, calendar: calendar) else { throw LockError.showUsedToday }
        showSessionStart = now
        showEpisodeID = nil
    }

    /// The first episode opened in a session is the only one allowed that day.
    public mutating func chooseEpisode(_ id: String, now: Date) throws {
        guard isShowSessionActive(now: now) else { throw LockError.showNotActive }
        if let chosen = showEpisodeID, chosen != id { throw LockError.oneEpisodePerDay }
        showEpisodeID = id
    }

    /// Step 1: ask to unlock. A reason is required, to make you think twice.
    public mutating func requestUnlock(reason: String, now: Date) throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { throw LockError.needsReason }
        guard phase(now: now) == .locked else { throw LockError.alreadyRequested }
        unlockRequestedAt = now
        unlockReason = String(trimmed.prefix(500))
    }

    /// Changed your mind: always allowed.
    public mutating func cancelUnlock() {
        unlockRequestedAt = nil
        unlockReason = nil
    }

    /// Pause all blocking for one hour. Only inside the window. Uses up the window.
    public mutating func pause(now: Date) throws {
        guard isWindowOpen(now: now) else { throw LockError.windowClosed }
        pausedUntil = now.addingTimeInterval(Self.pauseDuration)
        cancelUnlock()
    }

    /// Anything that loosens the rules (remove a site, uninstall) must pass this check.
    public func requireWindow(now: Date) throws {
        guard isWindowOpen(now: now) else { throw LockError.windowClosed }
    }

    /// Wi-Fi login pages (hotels, airports) sometimes need the router's own DNS.
    /// Allowed any time, 5 minutes each, 3 times a day. Site blocking stays on.
    public mutating func startDNSRescue(now: Date) throws {
        tidy(now: now)
        // A second click while one is running doesn't use up another.
        if isDNSRescueActive(now: now) { return }
        guard dnsRescueHistory.count < Self.dnsRescuesPerDay else { throw LockError.rescueLimitReached }
        dnsRescueHistory.append(now)
        dnsRescueUntil = now.addingTimeInterval(Self.dnsRescueDuration)
    }

    /// Someone changed a protected setting: it gets fixed and your streak starts over.
    public mutating func recordTamper(_ what: String, now: Date) {
        tamperLog.append(TamperEvent(date: now, what: what))
        streakStart = now
    }

    public func streakDays(now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(streakStart) / 86_400))
    }
}

public struct TamperEvent: Codable, Equatable {
    public var date: Date
    public var what: String
    public init(date: Date, what: String) { self.date = date; self.what = what }
}
