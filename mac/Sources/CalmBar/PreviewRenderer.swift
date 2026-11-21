import SwiftUI
import AppKit
import CalmShared

/// Renders the panel with sample data to PNG files, so the design can be checked without installing.
@MainActor
enum PreviewRenderer {
    static func render(to prefix: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let now = Date()
        let status = CalmStatus(
            heartbeat: now, phase: .locked, phaseEnds: nil, unlockReason: nil,
            streakStart: now.addingTimeInterval(-4.6 * 86_400), tamperLog: [],
            extraSites: ["youtube.com"], removedSites: [], extraApps: [], blockedSiteCount: 74_611,
            chromeProfileInstalled: false, dnsRescueUntil: nil, dnsRescuesLeft: 2,
            revealedRemovalPassword: nil, lastMessage: "Now blocking youtube.com.")
        let guardClient = GuardClient(); guardClient.showPreview(status)
        let updater = Updater()
        if let url = URL(string: "https://example.com/Calm.pkg") {
            updater.showPreview(.available(.init(version: "0.3.0", downloadURL: url, sha256: nil, notes: "")))
        }
        let spotify = SpotifyController()
        spotify.playlistLink = "https://open.spotify.com/playlist/37i9dQZF1DX0XUsuxWHRQd"
        spotify.showPreview(nowPlaying: "Figuring Out · Raj Shamani")

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let root = PanelView()
                .environmentObject(guardClient)
                .environmentObject(FocusController())
                .environmentObject(spotify)
                .environmentObject(updater)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: root)
            host.appearance = NSAppearance(named: appearance)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let path = "\(prefix)-\(name).png"
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) \(Int(size.width))x\(Int(size.height))")
        }
    }
}
