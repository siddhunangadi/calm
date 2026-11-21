import AppKit
import WidgetKit
import CalmShared

/// Keeps the Calm widgets' data file current and asks macOS to redraw them when something changes.
@MainActor
final class WidgetFeeder {
    static let shared = WidgetFeeder()
    private var timer: Timer?
    private var last: WidgetData?
    private var lastArtworkURL: String?

    func start() {
        registerWidgets()
        try? FileManager.default.createDirectory(atPath: WidgetFeed.dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in WidgetFeeder.shared.tick() }
        }
    }

    func tick(force: Bool = false) {
        let status = GuardClient.shared.status
        var track: WidgetData.Track?
        if let (t, art) = SpotifyController.shared.currentTrack() {
            track = t
            track?.artworkFile = artworkFile(for: art)
        }
        let data = WidgetData(streakStart: status?.streakStart, protected: GuardClient.shared.guardRunning,
                              blockedSiteCount: status?.blockedSiteCount ?? 0, track: track)
        guard force || data != last else { return }
        let streakChanged = data.streakStart != last?.streakStart || data.protected != last?.protected
            || data.blockedSiteCount != last?.blockedSiteCount
        let trackChanged = data.track != last?.track
        last = data
        if let d = try? CalmJSON.encoder.encode(data) {
            try? d.write(to: URL(fileURLWithPath: WidgetFeed.file), options: .atomic)
        }
        if streakChanged || force { WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeed.streakKind) }
        if trackChanged || force { WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeed.nowPlayingKind) }
    }

    /// Downloads the cover once per track; keeps only the current one.
    private func artworkFile(for urlString: String) -> String? {
        guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
        let name = "art-" + String(abs(urlString.hashValue)) + ".jpg"
        let path = WidgetFeed.dir + "/" + name
        if FileManager.default.fileExists(atPath: path) { return name }
        if lastArtworkURL == urlString { return nil }       // download already started
        lastArtworkURL = urlString
        Task.detached {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            let fm = FileManager.default
            for old in (try? fm.contentsOfDirectory(atPath: WidgetFeed.dir)) ?? [] where old.hasPrefix("art-") {
                try? fm.removeItem(atPath: WidgetFeed.dir + "/" + old)
            }
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            await MainActor.run { WidgetFeeder.shared.tick(force: true) }
        }
        return nil
    }

    /// Tell macOS about the widgets inside Calm, so they appear in Edit Widgets.
    private func registerWidgets() {
        let appex = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/CalmWidgets.appex").path
        guard FileManager.default.fileExists(atPath: appex) else { return }
        for args in [["-a", appex], ["-e", "use", "-i", "com.calm.bar.widgets"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            p.arguments = args
            try? p.run()
            p.waitUntilExit()
        }
    }
}

/// Handles calm:// links from the widgets' buttons.
final class CalmAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in WidgetFeeder.shared.start() }
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: s), url.scheme == "calm", url.host == "spotify" else { return }
        let action = url.lastPathComponent
        Task { @MainActor in
            let sp = SpotifyController.shared
            switch action {
            case "playpause": sp.playPause()
            case "next": sp.next()
            case "previous": sp.previous()
            case "play": sp.playlistURI == nil ? sp.playPause() : sp.playMyPlaylist()
            default: return
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            WidgetFeeder.shared.tick()
        }
    }
}
