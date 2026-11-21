import AppKit
import CalmShared

/// Plays only your playlist, by remote-controlling the Spotify app. You never need to open its window.
@MainActor
final class SpotifyController: ObservableObject {
    static let shared = SpotifyController()

    @Published var playlistLink: String {
        didSet { UserDefaults.standard.set(playlistLink, forKey: "playlistLink") }
    }
    @Published private(set) var nowPlaying = ""

    init() {
        playlistLink = UserDefaults.standard.string(forKey: "playlistLink") ?? ""
    }

    /// For the design preview only.
    func showPreview(nowPlaying: String) { self.nowPlaying = nowPlaying }

    var playlistURI: String? { Spotify.playlistURI(from: playlistLink) }

    /// Without Spotify installed, any script that names it makes macOS ask "Where is Spotify?".
    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil }
    var isSpotifyActive: Bool { isRunning && liveTrack() != nil }
    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }

    func playMyPlaylist() {
        guard let uri = playlistURI else { return }
        runScript("tell application id \"com.spotify.client\" to play track \"\(uri)\"")
        afterCommand(hideSpotify: true)
    }

    func playPause() { runScript("tell application id \"com.spotify.client\" to playpause"); afterCommand() }
    func next() { runScript("tell application id \"com.spotify.client\" to next track"); afterCommand() }
    func previous() { runScript("tell application id \"com.spotify.client\" to previous track"); afterCommand() }

    func refreshNowPlaying() {
        guard isRunning else { nowPlaying = ""; return }
        let script = "tell application id \"com.spotify.client\" to return (name of current track) & \" · \" & (artist of current track)"
        nowPlaying = runScript(script) ?? ""
    }

    /// The last thing played, kept after Spotify quits so the widget can show it and resume it.
    struct LastPlayed: Codable {
        var track: WidgetData.Track
        var uri: String
        var position: Double
        var artworkURL: String
    }

    private(set) var lastPlayed: LastPlayed? = {
        guard let d = UserDefaults.standard.data(forKey: "lastPlayed") else { return nil }
        return try? JSONDecoder().decode(LastPlayed.self, from: d)
    }()

    private func remember(_ l: LastPlayed) {
        lastPlayed = l
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: "lastPlayed") }
    }

    /// What the Now Playing widget shows: the current track, or the last one (paused) when Spotify is closed.
    func widgetTrack() -> (track: WidgetData.Track, artworkURL: String)? {
        if isRunning, let live = liveTrack() {
            remember(live)
            return (live.track, live.artworkURL)
        }
        guard var l = lastPlayed else { return nil }
        l.track.playing = false
        return (l.track, l.artworkURL)
    }

    /// Spotify's current track, or nil when it isn't running or has nothing loaded.
    private func liveTrack() -> LastPlayed? {
        let sep = "\u{1F}"
        let script = """
        tell application id "com.spotify.client"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (album of t) & "\(sep)" & (player state as text) & "\(sep)" & (artwork url of t) & "\(sep)" & (id of t) & "\(sep)" & (player position as text)
        end tell
        """
        guard let out = runScript(script, quiet: true) else { return nil }
        let p = out.components(separatedBy: sep)
        guard p.count >= 7, !p[0].isEmpty else { return nil }
        let pos = Double(p[6].replacingOccurrences(of: ",", with: ".")) ?? 0
        return LastPlayed(track: .init(title: p[0], artist: p[1], album: p[2], playing: p[3] == "playing"),
                          uri: p[5], position: pos, artworkURL: p[4])
    }

    /// Spotify is closed (or has nothing loaded): open it in the background and carry on where you stopped.
    func resumeLast() {
        guard let l = lastPlayed, l.uri.hasPrefix("spotify:") else {
            if playlistURI != nil { playMyPlaylist() }
            return
        }
        runScript("tell application id \"com.spotify.client\" to play track \"\(l.uri)\"")
        let position = max(0, l.position - 3)   // a few seconds back, to pick up the thread
        Task { @MainActor [weak self] in
            for _ in 0..<10 {   // wait until Spotify has loaded it
                try? await Task.sleep(nanoseconds: 700_000_000)
                if self?.runScript("tell application id \"com.spotify.client\" to return (player state as text)", quiet: true) == "playing" { break }
            }
            if position > 5 {
                self?.runScript("tell application id \"com.spotify.client\" to set player position to \(Int(position))", quiet: true)
            }
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").forEach { $0.hide() }
            self?.refreshNowPlaying()
        }
    }

    /// Play/pause from the widget: resumes the last track if Spotify is closed or idle.
    func widgetPlayPause() {
        if isRunning, liveTrack() != nil { playPause() } else { resumeLast() }
    }

    /// Spotify opens its window when it starts; hide it so its home feed doesn't pull you in.
    private func afterCommand(hideSpotify: Bool = false) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if hideSpotify {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").forEach { $0.hide() }
            }
            self?.refreshNowPlaying()
        }
    }

    @discardableResult
    private func runScript(_ source: String, quiet: Bool = false) -> String? {
        guard isInstalled else { return nil }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, !quiet { NSLog("Calm Spotify: \(error)") }
        return result?.stringValue
    }
}
