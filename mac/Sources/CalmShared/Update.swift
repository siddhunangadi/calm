import Foundation

/// Finding a newer Calm on GitHub Releases. Pure logic, so it is unit-tested.
public enum CalmUpdate {
    /// Public repo whose releases carry Calm.pkg, tagged "calm-v<version>".
    public static let releasesAPI = URL(string: "https://api.github.com/repos/siddhunangadi/calm/releases?per_page=50")!
    public static let tagPrefix = "calm-v"
    public static let assetName = "Calm.pkg"
    /// While this file exists, the installer is running from the menu-bar app's Update button,
    /// so postinstall leaves the menu-bar app alone (it restarts itself once the install finishes).
    public static let selfUpdateMarker = CalmPaths.supportDir + "/.self-update"

    public struct Candidate: Equatable, Sendable {
        public let version: String
        public let downloadURL: URL
        /// Hex SHA-256 of Calm.pkg as GitHub reports it, when it does.
        public let sha256: String?
        public let notes: String

        public init(version: String, downloadURL: URL, sha256: String?, notes: String) {
            self.version = version; self.downloadURL = downloadURL; self.sha256 = sha256; self.notes = notes
        }
    }

    /// "0.10.2" > "0.9.9". Missing parts count as 0; anything after "-" is ignored.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let core = v.split(separator: "-").first.map(String.init) ?? v
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let digest: String?
    }

    /// The newest published Calm release newer than `current`, if any.
    public static func newest(fromReleasesJSON data: Data, current: String) -> Candidate? {
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else { return nil }
        var best: Candidate?
        for r in releases where !r.draft && !r.prerelease && r.tag_name.hasPrefix(tagPrefix) {
            let version = String(r.tag_name.dropFirst(tagPrefix.count))
            guard isNewer(version, than: current),
                  let asset = r.assets.first(where: { $0.name == assetName }),
                  asset.browser_download_url.scheme == "https" else { continue }
            if let b = best, !isNewer(version, than: b.version) { continue }
            var sha: String?
            if let d = asset.digest, d.hasPrefix("sha256:") { sha = String(d.dropFirst(7)).lowercased() }
            best = Candidate(version: version, downloadURL: asset.browser_download_url, sha256: sha,
                             notes: r.body ?? "")
        }
        return best
    }
}
