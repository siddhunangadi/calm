import Foundation

/// Builds and checks Calm's block section inside /etc/hosts.
/// Everything else in your hosts file is left exactly as it was.
public enum HostsFile {
    public static let beginMarker = "# >>> CALM BLOCKLIST (managed by Calm; edits are undone automatically) >>>"
    public static let endMarker = "# <<< CALM BLOCKLIST <<<"

    /// The block section. `primary` sites get IPv4 + IPv6 lines, `extra` (the big adult list) gets IPv4 only
    /// to keep the file small; the DNS filter covers adult sites on IPv6.
    public static func section(primary: [String], extra: [String]) -> String {
        var lines = [beginMarker]
        var seen = Set<String>()
        for d in primary where seen.insert(d).inserted {
            lines.append("0.0.0.0 \(d)")
            lines.append(":: \(d)")
        }
        for d in extra where seen.insert(d).inserted {
            lines.append("0.0.0.0 \(d)")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Removes Calm's section (if any) and returns the rest of the file.
    public static func strip(_ contents: String) -> String {
        guard let start = contents.range(of: beginMarker) else { return contents }
        var before = String(contents[..<start.lowerBound])
        var after = ""
        if let end = contents.range(of: endMarker, range: start.upperBound..<contents.endIndex) {
            after = String(contents[end.upperBound...])
            if after.hasPrefix("\n") { after.removeFirst() }
        }
        // A tampered file may have lost its end marker: drop everything after the start then.
        while before.hasSuffix("\n\n") { before.removeLast() }
        return before + after
    }

    /// Your original hosts file with Calm's section added at the end.
    public static func apply(section: String, to contents: String) -> String {
        var base = strip(contents)
        if !base.isEmpty && !base.hasSuffix("\n") { base += "\n" }
        return base + "\n" + section
    }

    /// True if the file contains exactly our expected section.
    public static func isIntact(_ contents: String, expectedSection: String) -> Bool {
        guard let start = contents.range(of: beginMarker),
              let end = contents.range(of: endMarker, range: start.upperBound..<contents.endIndex) else { return false }
        let found = String(contents[start.lowerBound..<end.upperBound]) + "\n"
        return found == expectedSection
            // Make sure nobody added a second copy with different contents.
            && contents.components(separatedBy: beginMarker).count == 2
    }
}

extension HostsFile {
    /// Calm's section as it currently appears in the file, or nil if it is missing.
    public static func extractSection(_ contents: String) -> String? {
        guard let start = contents.range(of: beginMarker),
              let end = contents.range(of: endMarker, range: start.upperBound..<contents.endIndex) else { return nil }
        return String(contents[start.lowerBound..<end.upperBound]) + "\n"
    }

    /// Stable fingerprint of a text (Swift's own hash changes every launch, this one doesn't).
    public static func fingerprint(_ text: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in text.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(h, radix: 16)
    }
}
