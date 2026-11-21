import AppKit

/// Focus mode: hides every app that isn't on your list. Hidden apps keep running in the background.
@MainActor
final class FocusController: ObservableObject {
    static let defaultAllowed: Set<String> = [
        "net.whatsapp.WhatsApp", "desktop.WhatsApp", "com.spotify.client", "com.apple.finder",
        "com.apple.systempreferences",
    ]

    @Published private(set) var isOn: Bool
    @Published private(set) var allowed: Set<String>
    private var lastAllowedApp: NSRunningApplication?
    private let defaults = UserDefaults.standard

    init() {
        isOn = defaults.bool(forKey: "focusOn")
        allowed = Set(defaults.stringArray(forKey: "focusAllowed") ?? Array(Self.defaultAllowed))
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.appActivated(app) }
        }
        if isOn { hideOthers() }
    }

    func setOn(_ on: Bool) {
        isOn = on
        defaults.set(on, forKey: "focusOn")
        if on { hideOthers() }
        // macOS Focus (made once in System Settings) silences notifications from everything else.
        runShortcut(on ? "Calm Focus On" : "Calm Focus Off")
    }

    func isAllowed(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return true }
        return id == Bundle.main.bundleIdentifier || allowed.contains(id)
    }

    func toggleAllowed(_ bundleID: String) {
        if allowed.contains(bundleID) { allowed.remove(bundleID) } else { allowed.insert(bundleID) }
        defaults.set(Array(allowed), forKey: "focusAllowed")
        if isOn { hideOthers() }
    }

    /// Normal apps that are open right now (for the "allowed apps" list).
    var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func hideOthers() {
        for app in runningApps where !isAllowed(app) { app.hide() }
    }

    private func appActivated(_ app: NSRunningApplication?) {
        guard let app else { return }
        if isAllowed(app) { lastAllowedApp = app; return }
        guard isOn else { return }
        app.hide()
        lastAllowedApp?.activate(options: [])
    }

    private func runShortcut(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        try? p.run()
    }
}
