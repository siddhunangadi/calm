import AppKit
import WebKit

/// A small window that shows only Audible: no tabs, no address bar, nothing else to click into.
@MainActor
final class AudibleWindow {
    static let shared = AudibleWindow()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        web.load(URLRequest(url: URL(string: "https://www.audible.in/library/titles")!))
        let w = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Audible"
        w.contentView = web
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}
