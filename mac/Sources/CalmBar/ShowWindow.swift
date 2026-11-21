import AppKit
import WebKit
import CalmShared

/// Devon Ke Dev Mahadev in its own window: no address bar, can't leave the series,
/// and only the first episode opened today will play.
@MainActor
final class ShowWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = ShowWindow()
    private var window: NSWindow?
    private var web: WKWebView?
    private var urlObservation: NSKeyValueObservation?
    private weak var guardClient: GuardClient?
    /// Today's episode as far as this window knows (the guard has the final say).
    private var chosenEpisode: String?
    private var timer: Timer?

    func show(guardClient: GuardClient) {
        self.guardClient = guardClient
        chosenEpisode = guardClient.status?.showEpisodeID
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700), configuration: config)
        // JioHotstar only serves its player to browsers it knows.
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        web.navigationDelegate = self
        // The site changes pages without full loads, so watch the address too.
        urlObservation = web.observe(\.url, options: [.new]) { [weak self] web, _ in
            let url = web.url
            Task { @MainActor in self?.check(url) }
        }
        let start = UserDefaults.standard.url(forKey: "mahadevSeriesURL") ?? ShowRules.start
        web.load(URLRequest(url: start))

        let w = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Devon Ke Dev Mahadev"
        w.contentView = web
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        self.web = web

        // Close when today's session time is up.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.closeIfSessionOver() }
        }
    }

    private func closeIfSessionOver() {
        guard let ends = guardClient?.status?.showSessionEnds else {
            if guardClient?.status != nil { close(saying: "Today's Mahadev time is over. See you tomorrow.") }
            return
        }
        if Date() >= ends { close(saying: "Today's Mahadev time is over. See you tomorrow.") }
    }

    private func check(_ url: URL?) {
        guard let url, let web else { return }
        switch ShowRules.decide(url) {
        case .allow:
            // Remember the series page, so next time it opens straight there.
            if url.path.contains("/shows/\(ShowRules.seriesSlug)") {
                UserDefaults.standard.set(url, forKey: "mahadevSeriesURL")
            }
        case .episode(let id):
            let known = chosenEpisode ?? guardClient?.status?.showEpisodeID
            if let known, known != id {
                bounce(web, "One episode a day. Today's episode is already chosen.")
                return
            }
            if chosenEpisode == nil {
                chosenEpisode = id
                guardClient?.send(.showEpisode, id)
            }
        case .block:
            bounce(web, nil)
        }
    }

    private func bounce(_ web: WKWebView, _ message: String?) {
        if web.canGoBack, let back = web.backForwardList.backItem?.url, ShowRules.decide(back) != .block,
           !(message != nil && { if case .episode = ShowRules.decide(back) { return true }; return false }()) {
            web.goBack()
        } else {
            web.load(URLRequest(url: UserDefaults.standard.url(forKey: "mahadevSeriesURL") ?? ShowRules.start))
        }
        if let message { flash(message) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // Only top-level pages are limited; the site's scripts, images and video load freely.
        guard action.targetFrame?.isMainFrame ?? true, let url = action.request.url else { return decisionHandler(.allow) }
        if url.scheme == "about" || url.scheme == "blob" { return decisionHandler(.allow) }
        switch ShowRules.decide(url) {
        case .block:
            decisionHandler(.cancel)
        case .episode(let id):
            let known = chosenEpisode ?? guardClient?.status?.showEpisodeID
            if let known, known != id {
                decisionHandler(.cancel)
                flash("One episode a day. Today's episode is already chosen.")
            } else {
                decisionHandler(.allow)
            }
        case .allow:
            decisionHandler(.allow)
        }
    }

    private func flash(_ text: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = text
        alert.beginSheetModal(for: window)
    }

    private func close(saying text: String) {
        timer?.invalidate(); timer = nil
        urlObservation = nil
        web?.stopLoading()
        web?.pauseAllMediaPlayback()
        window?.close()
        window = nil; web = nil
        let alert = NSAlert()
        alert.messageText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        urlObservation = nil
        web?.pauseAllMediaPlayback()
        window = nil; web = nil
    }
}
