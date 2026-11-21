import AppKit
import CalmShared

/// Plays only your playlist, by remote-controlling the Spotify app. You never need to open its window.
@MainActor
final class SpotifyController: ObservableObject {
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
    private func runScript(_ source: String) -> String? {
        guard isInstalled else { return nil }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Calm Spotify: \(error)") }
        return result?.stringValue
    }
}
