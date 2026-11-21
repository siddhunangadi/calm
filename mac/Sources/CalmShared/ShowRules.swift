import Foundation

/// Which JioHotstar pages the Mahadev window may show. Pure logic, unit-tested.
public enum ShowRules {
    public static let seriesSlug = "devon-ke-dev-mahadev"
    public static let start = URL(string: "https://www.hotstar.com/in/explore?search_query=Devon%20Ke%20Dev%20Mahadev")!

    public enum Decision: Equatable {
        case allow
        /// An episode page; the id is the episode's content id.
        case episode(String)
        case block
    }

    static let hosts = ["hotstar.com", "jiohotstar.com"]
    /// Sign-in and profile pages the site needs before it plays anything.
    static let accountPaths = ["/onboarding", "/login", "/subscribe", "/paywall", "/mypage", "/profiles", "/myspace", "/consent"]

    public static func decide(_ url: URL) -> Decision {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return .block }
        let path = url.path.lowercased()
        // Strip a leading country segment like "/in".
        let parts = path.split(separator: "/").map(String.init)
        let rest = parts.first.map { $0.count == 2 } == true ? Array(parts.dropFirst()) : parts

        if rest.count >= 2, rest[0] == "shows", rest[1] == seriesSlug {
            // /shows/<slug>/<showId>/<episode-slug>/<episodeId>[/watch]
            if rest.count >= 5, rest[4].allSatisfy(\.isNumber) { return .episode(rest[4]) }
            return .allow
        }
        if rest.first == "explore" {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "search_query" }?.value?.lowercased() ?? ""
            return q.contains("mahadev") ? .allow : .block
        }
        let joined = "/" + rest.joined(separator: "/")
        if accountPaths.contains(where: { joined.hasPrefix($0) }) { return .allow }
        return .block
    }
}
