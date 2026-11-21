import WidgetKit
import SwiftUI
import CalmShared

// Calm's desktop widgets: clean streak, and what's playing in Spotify.
// They read a small file the Calm menu-bar app keeps current (see WidgetFeed).

private let calmGreen = Color(red: 0.18, green: 0.60, blue: 0.44)
private let deepGreen = Color(red: 0.06, green: 0.20, blue: 0.15)

struct CalmEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
    let artwork: NSImage?
}

struct CalmProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalmEntry { CalmEntry(date: .now, data: Self.sample, artwork: nil) }

    func getSnapshot(in context: Context, completion: @escaping (CalmEntry) -> Void) {
        completion(context.isPreview && WidgetFeed.read() == nil ? placeholder(in: context) : load(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalmEntry>) -> Void) {
        // Hourly entries keep the day count right; Calm reloads us when anything else changes.
        let now = Date()
        let entries = (0..<24).map { load(at: now.addingTimeInterval(Double($0) * 3600)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }

    private func load(at date: Date) -> CalmEntry {
        let data = WidgetFeed.read()
        var art: NSImage?
        if let f = data?.track?.artworkFile { art = NSImage(contentsOfFile: WidgetFeed.dir + "/" + f) }
        return CalmEntry(date: date, data: data, artwork: art)
    }

    static let sample = WidgetData(streakStart: Date().addingTimeInterval(-4.4 * 86_400), protected: true,
                                   blockedSiteCount: 74_613,
                                   track: .init(title: "Figuring Out", artist: "Raj Shamani", album: "", playing: true))
}

// MARK: - Streak

struct StreakRing: View {
    let progress: Double
    let days: Int
    let goal: Int
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: size * 0.085)
            Circle().trim(from: 0, to: max(0.02, progress))
                .stroke(calmGreen.gradient, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(days)").font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.5)
                Text(days == 1 ? "day" : "days").font(.system(size: size * 0.12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
    }
}

struct StreakView: View {
    @Environment(\.widgetFamily) var family
    let entry: CalmEntry

    var body: some View {
        let d = entry.data
        let days = d?.streakDays(now: entry.date) ?? 0
        let g = d?.goal(now: entry.date) ?? (days: 1, progress: 0)
        Group {
            if family == .systemMedium {
                HStack(spacing: 16) {
                    StreakRing(progress: g.progress, days: days, goal: g.days, size: 104)
                    VStack(alignment: .leading, spacing: 6) {
                        header
                        Text("Clean streak").font(.system(size: 17, weight: .semibold))
                        if let s = d?.streakStart {
                            Text("Since \(s.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                        Label("Next goal · \(g.days) days", systemImage: "flag.checkered")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                        Text("\((d?.blockedSiteCount ?? 0).formatted()) sites blocked")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 8) {
                    header
                    StreakRing(progress: g.progress, days: days, goal: g.days, size: 92)
                    Text("Goal: \(g.days) days").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.30, blue: 0.22), deepGreen], startPoint: .top, endPoint: .bottom)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "leaf.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(calmGreen)
            Text("Calm").font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            Circle().fill(entry.data?.protected == false ? .red : calmGreen).frame(width: 6, height: 6)
        }
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeed.streakKind, provider: CalmProvider()) { StreakView(entry: $0) }
            .configurationDisplayName("Clean streak")
            .description("Your Calm streak and next milestone.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Now playing

struct ControlButton: View {
    let symbol: String
    let action: String
    var big = false
    var body: some View {
        Link(destination: WidgetFeed.url(action)) {
            Image(systemName: symbol)
                .font(.system(size: big ? 15 : 12, weight: .bold))
                .frame(width: big ? 36 : 28, height: big ? 36 : 28)
                .background(.white.opacity(big ? 0.22 : 0.12), in: Circle())
        }
    }
}

struct NowPlayingView: View {
    @Environment(\.widgetFamily) var family
    let entry: CalmEntry

    var body: some View {
        let t = entry.data?.track
        Group {
            if family == .systemMedium {
                HStack(spacing: 14) {
                    artwork.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        source
                        Spacer(minLength: 0)
                        Text(t?.title ?? "Nothing playing").font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        Text(t?.subtitle ?? "Open Spotify to start").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        Spacer(minLength: 0)
                        controls
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        artwork.frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Spacer()
                        Image(systemName: "music.note").font(.system(size: 11, weight: .bold)).foregroundStyle(.green)
                    }
                    Spacer(minLength: 0)
                    Text(t?.title ?? "Nothing playing").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(t?.subtitle ?? "Spotify").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { background }
    }

    private var source: some View {
        HStack(spacing: 5) {
            Image(systemName: "music.note").font(.system(size: 11, weight: .bold)).foregroundStyle(.green)
            Text(entry.data?.track?.playing == true ? "Now playing" : "Paused").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ControlButton(symbol: "backward.fill", action: "previous")
            ControlButton(symbol: entry.data?.track?.playing == true ? "pause.fill" : "play.fill",
                          action: entry.data?.track == nil ? "play" : "playpause", big: true)
            ControlButton(symbol: "forward.fill", action: "next")
        }
    }

    @ViewBuilder private var artwork: some View {
        if let img = entry.artwork {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: [.green.opacity(0.7), deepGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 20, weight: .bold)).foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    @ViewBuilder private var background: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.08)
            if let img = entry.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).blur(radius: 30).opacity(0.55)
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeed.nowPlayingKind, provider: CalmProvider()) { NowPlayingView(entry: $0) }
            .configurationDisplayName("Now playing")
            .description("What's playing in Spotify, with play, pause and skip.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CalmWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        NowPlayingWidget()
    }
}
