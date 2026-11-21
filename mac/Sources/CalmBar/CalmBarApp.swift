import SwiftUI
import AppKit
import CalmShared

@main
enum CalmMain {
    static func main() {
        // CALM_RENDER_PREVIEW=/path/prefix renders the panel to PNGs (light + dark) and exits. Used to check the design.
        if let out = ProcessInfo.processInfo.environment["CALM_RENDER_PREVIEW"] {
            MainActor.assumeIsolated { PreviewRenderer.render(to: out) }
            return
        }
        CalmBarApp.main()
    }
}

struct CalmBarApp: App {
    @StateObject private var guardClient = GuardClient()
    @StateObject private var focus = FocusController()
    @StateObject private var spotify = SpotifyController()
    @StateObject private var updater = Updater()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(guardClient)
                .environmentObject(focus)
                .environmentObject(spotify)
                .environmentObject(updater)
        } label: {
            Image(systemName: focus.isOn ? "moon.circle.fill" : "leaf.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Design tokens

enum Calm {
    static let accent = Color(red: 0.18, green: 0.60, blue: 0.44)
    static let width: CGFloat = 360
    static let corner: CGFloat = 12
}

/// A grouped card, like the sections in System Settings.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: Calm.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Calm.corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white))
    }
}

/// Icon, title, optional subtitle, and something on the right.
struct Row<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 48) }
}

/// Small round icon button for the music controls.
struct GlyphButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Panel

struct PanelView: View {
    @EnvironmentObject var guardClient: GuardClient
    @EnvironmentObject var focus: FocusController
    @EnvironmentObject var spotify: SpotifyController
    @EnvironmentObject var updater: Updater

    @State private var newSite = ""
    @State private var unlockReason = ""
    @State private var siteToRemove = ""
    @State private var showAllowedApps = false
    @State private var confirmUninstall = false
    @State private var showUnlockForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header.padding(.bottom, 2)
            updateBanner
            streakCard
            if let s = guardClient.status, !s.chromeProfileInstalled { chromeCard }
            alerts
            if let missing = guardClient.status?.blankPageMissing, !missing.isEmpty { blankPageCard(missing) }
            focusCard
            listenCard
            showCard
            blockCard
            lockCard
            footer.padding(.top, 2)
        }
        .padding(14)
        .frame(width: Calm.width)
        .tint(Calm.accent)
        .onAppear { spotify.refreshNowPlaying(); guardClient.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            IconTile(symbol: "leaf.fill", tint: Calm.accent, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Calm").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(guardClient.guardRunning ? Calm.accent : .red).frame(width: 6, height: 6)
                    Text(statusLine).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("Check for updates") { Task { await updater.check(userAsked: true) } }
                    .disabled(updater.isBusy)
                if let s = guardClient.status {
                    Button("Wi-Fi login page won't load? (\(s.dnsRescuesLeft) left today)") { guardClient.send(.dnsRescue) }
                        .disabled(s.dnsRescuesLeft == 0 || (s.dnsRescueUntil ?? .distantPast) > Date())
                }
                Divider()
                Text("Calm \(updater.currentVersion)")
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var statusLine: String {
        guard guardClient.guardRunning else {
            return guardClient.status == nil ? "Not installed" : "Guard stopped"
        }
        switch guardClient.status?.phase {
        case .paused?: return "Paused"
        case .window?: return "Unlocked for now"
        default:
            let n = guardClient.status?.blockedSiteCount ?? 0
            return "Protected · \(n.formatted()) sites blocked"
        }
    }

    // MARK: Streak

    private var streakCard: some View {
        let start = guardClient.status?.streakStart ?? Date()
        let days = max(0, Int(Date().timeIntervalSince(start) / 86_400))
        let goal = Self.milestones.first { $0 > days } ?? (days + 30)
        let progress = Double(Date().timeIntervalSince(start) / 86_400) / Double(goal)
        return Card {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean streak").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(days)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(days == 1 ? "day" : "days").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    }
                    Text(guardClient.status == nil ? "Install Calm.pkg to start" :
                            "Since \(start.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
                    Circle().trim(from: 0, to: max(0.02, min(1, progress)))
                        .stroke(Calm.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(goal)").font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("goal").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 52, height: 52)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private static let milestones = [1, 3, 7, 14, 21, 30, 60, 90, 180, 365]

    // MARK: Update

    @ViewBuilder private var updateBanner: some View {
        switch updater.phase {
        case .available(let c):
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 18)).foregroundStyle(Calm.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Calm \(c.version) is ready").font(.system(size: 12, weight: .semibold))
                    Text("Needs your Mac password once").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Update") { Task { await updater.install(c) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(10)
            .background(Calm.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .downloading(let v):
            progressBanner("Downloading Calm \(v)…")
        case .installing(let v):
            progressBanner("Installing Calm \(v). Calm restarts when done.")
        case .upToDate:
            notice("checkmark.circle.fill", Calm.accent, "Calm is up to date.")
        case .failed(let why):
            notice("exclamationmark.triangle.fill", .orange, why)
        default:
            EmptyView()
        }
    }

    private func progressBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func notice(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Chrome lock

    private var chromeCard: some View {
        Card {
            Row(symbol: "lock.shield.fill", tint: .orange, title: "Chrome lock needed",
                subtitle: "Chrome won't open until it's on") {
                Button("Install") {
                    guardClient.send(.prepareChromeProfile)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        NSWorkspace.shared.open(URL(fileURLWithPath: CalmPaths.profileDrop))
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Profiles-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: Black page extension

    private func blankPageCard(_ browsers: [String]) -> some View {
        Card {
            Row(symbol: "rectangle.fill", tint: .black, title: "Black page in \(browsers.joined(separator: " & "))",
                subtitle: "Add the Calm extension so blocked sites go black") {
                Button("How") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: CalmPaths.blankPageExtension)])
                    let a = NSAlert()
                    a.messageText = "Add the Calm extension"
                    a.informativeText = """
                    1. In \(browsers.first ?? "the browser"), open the address  \(browsers.first == "Comet" ? "comet://extensions" : "chrome://extensions")
                    2. Turn on "Developer mode" (top right).
                    3. Click "Load unpacked" and choose the BlankPage folder Finder just showed you \
                    (Macintosh HD → Library → Application Support → Calm → BlankPage).
                    4. In the Calm extension's Details, turn on "Allow access to file URLs" so sites you block later go black too.

                    Once it's on, removing it later counts as tampering and restarts your streak.
                    """
                    NSApp.activate(ignoringOtherApps: true)
                    a.runModal()
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: Alerts (tampering, guard messages)

    @ViewBuilder private var alerts: some View {
        if let s = guardClient.status {
            let recent = s.tamperLog.filter { Date().timeIntervalSince($0.date) < 24 * 3600 }
            if let last = recent.last {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(last.what).font(.system(size: 11, weight: .medium))
                        Text("\(last.date.formatted(date: .omitted, time: .shortened)) · Calm fixed it and restarted your streak")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: Focus

    private var focusCard: some View {
        Card {
            Row(symbol: "moon.fill", tint: .indigo, title: "Focus",
                subtitle: "Hides every app that isn't allowed") {
                Toggle("", isOn: Binding(get: { focus.isOn }, set: { focus.setOn($0) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            RowDivider()
            Button { withAnimation(.easeOut(duration: 0.15)) { showAllowedApps.toggle() } } label: {
                HStack {
                    Text("Allowed apps").font(.system(size: 12))
                    Spacer()
                    Text("\(focus.allowed.count)").font(.system(size: 12)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary).rotationEffect(.degrees(showAllowedApps ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12).padding(.vertical, 8).padding(.leading, 36)
            }
            .buttonStyle(.plain)
            if showAllowedApps {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(focus.runningApps, id: \.processIdentifier) { app in
                            if let id = app.bundleIdentifier {
                                Toggle(isOn: Binding(get: { focus.allowed.contains(id) }, set: { _ in focus.toggleAllowed(id) })) {
                                    Text(app.localizedName ?? id).font(.system(size: 12))
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 48).padding(.trailing, 12).padding(.bottom, 10)
                }
                .frame(maxHeight: 150)
            }
        }
    }

    // MARK: Listen

    private var listenCard: some View {
        Card {
            if !spotify.isInstalled {
                Row(symbol: "music.note", tint: .green, title: "Spotify",
                    subtitle: "Install the Spotify app to play your playlist here") { EmptyView() }
            } else if spotify.playlistURI == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Row(symbol: "music.note", tint: .green, title: "Your playlist",
                        subtitle: "Spotify → playlist → ··· → Share → Copy link") { EmptyView() }
                        .padding(.bottom, -6)
                    TextField("Paste playlist link", text: $spotify.playlistLink)
                        .textFieldStyle(.roundedBorder).controlSize(.small)
                        .padding(.leading, 48).padding(.trailing, 12).padding(.bottom, 10)
                }
            } else {
                let parts = spotify.nowPlaying.components(separatedBy: " · ")
                Row(symbol: "music.note", tint: .green,
                    title: spotify.nowPlaying.isEmpty ? "Your playlist" : parts[0],
                    subtitle: spotify.nowPlaying.isEmpty ? "Spotify" : parts.dropFirst().joined(separator: " · ")) {
                    HStack(spacing: 6) {
                        GlyphButton(symbol: "backward.fill") { spotify.previous() }
                        GlyphButton(symbol: "playpause.fill") {
                            spotify.nowPlaying.isEmpty ? spotify.playMyPlaylist() : spotify.playPause()
                        }
                        GlyphButton(symbol: "forward.fill") { spotify.next() }
                    }
                }
                .contextMenu { Button("Change playlist") { spotify.playlistLink = "" } }
            }
            RowDivider()
            Row(symbol: "headphones", tint: .orange, title: "Audible", subtitle: "Opens in its own window") {
                Button("Open") { AudibleWindow.shared.show() }.controlSize(.small)
            }
        }
    }

    // MARK: Devon Ke Dev Mahadev

    private var showCard: some View {
        let st = guardClient.status
        let ends = st?.showSessionEnds.flatMap { $0 > Date() ? $0 : nil }
        let used = st?.showUsedToday ?? false
        let subtitle: String
        if let ends { subtitle = "Browsers closed until \(ends.formatted(date: .omitted, time: .shortened))" }
        else if used { subtitle = "Today's episode is done · next one tomorrow" }
        else { subtitle = "One episode a day · browsers close for 40 min" }
        return Card {
            Row(symbol: "sparkles", tint: Color(red: 0.95, green: 0.55, blue: 0.15),
                title: "Devon Ke Dev Mahadev", subtitle: subtitle) {
                if ends != nil {
                    Button("Open") { ShowWindow.shared.show(guardClient: guardClient) }.controlSize(.small)
                } else {
                    Button("Watch") {
                        guardClient.send(.startShow)
                        Task { @MainActor in
                            // Wait for the guard to open Hotstar before loading it.
                            for _ in 0..<20 {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                guardClient.refresh()
                                if guardClient.status?.showSessionEnds != nil { break }
                            }
                            if guardClient.status?.showSessionEnds != nil {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)   // let the DNS cache clear
                                ShowWindow.shared.show(guardClient: guardClient)
                            }
                        }
                    }
                    .controlSize(.small)
                    .disabled(used || st == nil)
                }
            }
        }
    }

    // MARK: Block more

    private var blockCard: some View {
        Card {
            HStack(spacing: 8) {
                IconTile(symbol: "nosign", tint: .red)
                TextField("Block a website, e.g. reddit.com", text: $newSite)
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                    .onSubmit(addSite)
                Button("Block", action: addSite).controlSize(.small).disabled(newSite.isEmpty)
                Menu {
                    Section("Block an open app") {
                        ForEach(focus.runningApps, id: \.processIdentifier) { app in
                            if let id = app.bundleIdentifier {
                                Button(app.localizedName ?? id) { guardClient.send(.addApp, id) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.2x2").font(.system(size: 12))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Block an open app")
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }

    private func addSite() {
        guard !newSite.isEmpty else { return }
        guardClient.send(.addSite, newSite)
        newSite = ""
    }

    // MARK: Lock

    @ViewBuilder private var lockCard: some View {
        Card {
            switch guardClient.status?.phase {
            case .locked?, nil:
                Row(symbol: "lock.fill", tint: .gray, title: "Locked",
                    subtitle: "Loosening rules takes 24 hours") {
                    if !showUnlockForm {
                        Button("Unlock…") { withAnimation(.easeOut(duration: 0.15)) { showUnlockForm = true } }
                            .controlSize(.small)
                    }
                }
                if showUnlockForm {
                    VStack(alignment: .trailing, spacing: 6) {
                        TextField("Why do you want to unlock?", text: $unlockReason, axis: .vertical)
                            .textFieldStyle(.roundedBorder).controlSize(.small).lineLimit(1...3)
                        HStack {
                            Button("Never mind") { showUnlockForm = false; unlockReason = "" }
                                .buttonStyle(.borderless).controlSize(.small)
                            Spacer()
                            Button("Start 24-hour wait") {
                                guardClient.send(.requestUnlock, unlockReason); unlockReason = ""; showUnlockForm = false
                            }
                            .controlSize(.small)
                            .disabled(unlockReason.trimmingCharacters(in: .whitespaces).count < 10)
                        }
                    }
                    .padding(.leading, 48).padding(.trailing, 12).padding(.bottom, 10)
                }
            case .waiting?:
                Row(symbol: "hourglass", tint: .orange, title: "Unlock opens \(relative(guardClient.status?.phaseEnds))",
                    subtitle: guardClient.status?.unlockReason.map { "“\($0)”" }) {
                    Button("Cancel") { guardClient.send(.cancelUnlock) }.controlSize(.small)
                }
            case .window?:
                Row(symbol: "lock.open.fill", tint: Calm.accent, title: "Unlocked",
                    subtitle: "Locks again \(relative(guardClient.status?.phaseEnds))") {
                    Button("Lock now") { guardClient.send(.cancelUnlock) }.controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Site to unblock", text: $siteToRemove).textFieldStyle(.roundedBorder).controlSize(.small)
                        Button("Unblock") { guardClient.send(.removeSite, siteToRemove); siteToRemove = "" }
                            .controlSize(.small).disabled(siteToRemove.isEmpty)
                    }
                    ForEach(guardClient.status?.extraApps ?? [], id: \.self) { id in
                        Button("Unblock app \(id)") { guardClient.send(.removeApp, id) }.controlSize(.small)
                    }
                    HStack {
                        Button("Pause 1 hour") { guardClient.send(.pause) }.controlSize(.small)
                        Spacer()
                        Button("Uninstall Calm…", role: .destructive) { confirmUninstall = true }.controlSize(.small)
                    }
                    if let pw = guardClient.status?.revealedRemovalPassword {
                        Text("Chrome lock removal password: \(pw)").font(.system(size: 11)).textSelection(.enabled)
                    }
                }
                .padding(.leading, 48).padding(.trailing, 12).padding(.bottom, 10)
            case .paused?:
                Row(symbol: "pause.fill", tint: .orange, title: "Paused",
                    subtitle: "Blocking returns \(relative(guardClient.status?.phaseEnds))") { EmptyView() }
            }
        }
        .confirmationDialog("Remove Calm completely?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { guardClient.send(.uninstall) }
        } message: {
            Text("All blocking stops. The Chrome lock stays until you remove it in System Settings with the password shown here.")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if let s = guardClient.status, let until = s.dnsRescueUntil, until > Date() {
                Image(systemName: "wifi").foregroundStyle(.orange)
                Text("Wi-Fi login help on until \(until.formatted(date: .omitted, time: .shortened))")
            } else if let m = guardClient.status?.lastMessage {
                Text(m).lineLimit(1)
            }
            Spacer()
            Text("v\(updater.currentVersion)").foregroundStyle(.tertiary)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func relative(_ date: Date?) -> String {
        guard let date else { return "soon" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
