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

    /// Full details for the Now Playing widget (nil when Spotify isn't running or has nothing loaded).
    func currentTrack() -> (track: WidgetData.Track, artworkURL: String)? {
        guard isRunning else { return nil }
        let sep = "\u{1F}"
        let script = """
        tell application id "com.spotify.client"
            set s to (player state as text)
            return (name of current track) & "\(sep)" & (artist of current track) & "\(sep)" & (album of current track) & "\(sep)" & s & "\(sep)" & (artwork url of current track)
        end tell
        """
        guard let out = runScript(script, quiet: true) else { return nil }
        let p = out.components(separatedBy: sep)
        guard p.count >= 5, !p[0].isEmpty else { return nil }
        return (WidgetData.Track(title: p[0], artist: p[1], album: p[2], playing: p[3] == "playing"), p[4])
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
