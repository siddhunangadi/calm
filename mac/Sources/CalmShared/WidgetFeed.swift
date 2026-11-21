import Foundation

/// What the Calm widgets show. Written by the menu-bar app to a folder the sandboxed widgets may read.
public struct WidgetData: Codable, Equatable {
    public struct Track: Codable, Equatable {
        public var title: String
        public var artist: String
        public var album: String
        public var playing: Bool
        /// File name of the artwork inside `WidgetFeed.dir`, if downloaded.
        public var artworkFile: String?
        public init(title: String, artist: String, album: String, playing: Bool, artworkFile: String? = nil) {
            self.title = title; self.artist = artist; self.album = album; self.playing = playing; self.artworkFile = artworkFile
        }
        /// Podcasts have no artist; the show name is in the album.
        public var subtitle: String { artist.isEmpty ? album : artist }
    }

    public var streakStart: Date?
    public var protected: Bool
    public var blockedSiteCount: Int
    public var track: Track?

    public init(streakStart: Date?, protected: Bool, blockedSiteCount: Int, track: Track?) {
        self.streakStart = streakStart; self.protected = protected; self.blockedSiteCount = blockedSiteCount; self.track = track
    }

    public static let milestones = [1, 3, 7, 14, 21, 30, 60, 90, 180, 365]

    public func streakDays(now: Date) -> Int {
        guard let s = streakStart else { return 0 }
        return max(0, Int(now.timeIntervalSince(s) / 86_400))
    }

    /// Next milestone and how far along the way to it (0…1).
    public func goal(now: Date) -> (days: Int, progress: Double) {
        let d = streakDays(now: now)
        let goal = Self.milestones.first { $0 > d } ?? (d + 30)
        guard let s = streakStart else { return (goal, 0) }
        return (goal, min(1, max(0, now.timeIntervalSince(s) / 86_400 / Double(goal))))
    }
}

public enum WidgetFeed {
    public static let dir = "/Users/Shared/Calm"
    public static let file = dir + "/widget.json"
    public static let streakKind = "CalmStreak"
    public static let nowPlayingKind = "CalmNowPlaying"
    /// URLs the widgets' buttons open; the menu-bar app handles them.
    public static func url(_ action: String) -> URL { URL(string: "calm://spotify/\(action)")! }

    public static func read() -> WidgetData? {
        guard let d = FileManager.default.contents(atPath: file) else { return nil }
        return try? CalmJSON.decoder.decode(WidgetData.self, from: d)
    }
}
