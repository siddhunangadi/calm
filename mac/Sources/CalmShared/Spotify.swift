import Foundation

public enum Spotify {
    /// Accepts a share link ("https://open.spotify.com/playlist/ID?si=...") or a URI ("spotify:playlist:ID")
    /// and returns the URI the Spotify app understands, or nil.
    public static func playlistURI(from raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var id: Substring?
        if s.hasPrefix("spotify:playlist:") {
            id = s.dropFirst("spotify:playlist:".count)
        } else if let r = s.range(of: "open.spotify.com/") {
            let path = s[r.upperBound...].split(separator: "?").first ?? ""
            let parts = path.split(separator: "/")
            if let i = parts.firstIndex(of: "playlist"), i + 1 < parts.count { id = parts[i + 1] }
        }
        guard let id, (10...40).contains(id.count), id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return "spotify:playlist:\(id)"
    }
}
