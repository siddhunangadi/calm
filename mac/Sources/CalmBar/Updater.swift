import AppKit
import CryptoKit
import CalmShared

/// "Update available" in the leaf menu: checks GitHub Releases, downloads Calm.pkg,
/// installs it after one macOS password prompt, deletes the download and restarts into the new version.
@MainActor
final class Updater: ObservableObject {
    enum Phase: Equatable {
        case idle, checking, upToDate
        case available(CalmUpdate.Candidate)
        case downloading(String), installing(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    private var timer: Timer?

    init() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await self?.check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    /// For the design preview only.
    func showPreview(_ p: Phase) { timer?.invalidate(); phase = p }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    func check(userAsked: Bool = false) async {
        guard !isBusy else { return }
        phase = .checking
        var request = URLRequest(url: CalmUpdate.releasesAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Calm-Updater", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("GitHub didn't answer. Try again later.") }
            if let c = CalmUpdate.newest(fromReleasesJSON: data, current: currentVersion) {
                phase = .available(c)
            } else {
                phase = userAsked ? .upToDate : .idle
            }
        } catch {
            phase = userAsked ? .failed(message(error)) : .idle
        }
    }

    func install(_ c: CalmUpdate.Candidate) async {
        phase = .downloading(c.version)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CalmUpdate-\(UUID().uuidString)")
        let pkg = dir.appendingPathComponent("Calm.pkg")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let (tmp, response) = try await URLSession.shared.download(from: c.downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Download failed. Try again later.") }
            try FileManager.default.moveItem(at: tmp, to: pkg)
            let data = try Data(contentsOf: pkg)
            if let expected = c.sha256 {
                let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { throw UpdateError("The download was damaged. Try again.") }
            }

            phase = .installing(c.version)
            try await runInstaller(pkg: pkg.path, version: c.version)
            try? FileManager.default.removeItem(at: dir)
            // The new version is on disk. Quit; launchd (KeepAlive) starts the new one straight away.
            try? await Task.sleep(nanoseconds: 500_000_000)
            exit(0)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            phase = .failed(message(error))
        }
    }

    /// One macOS password prompt, then the root-only part: install, then delete the download.
    private func runInstaller(pkg: String, version: String) async throws {
        let marker = CalmUpdate.selfUpdateMarker
        let shell = "/usr/bin/touch \(q(marker)); /usr/sbin/installer -pkg \(q(pkg)) -target /; rc=$?; " +
                    "/bin/rm -f \(q(marker)) \(q(pkg)); exit $rc"
        let script = "do shell script \(appleString(shell)) with prompt \(appleString("Calm wants to update to version \(version).")) with administrator privileges"
        let result: (ok: Bool, error: String) = await Task.detached {
            var err: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&err)
            if let err {
                let code = err[NSAppleScript.errorNumber] as? Int ?? 0
                return (false, code == -128 ? "Update cancelled." : "Install failed: \(err[NSAppleScript.errorMessage] as? String ?? "unknown error")")
            }
            return (true, "")
        }.value
        if !result.ok { throw UpdateError(result.error) }
    }

    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func appleString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    private func message(_ e: Error) -> String { (e as? UpdateError)?.text ?? "No internet? Try again later." }
}

struct UpdateError: Error {
    let text: String
    init(_ text: String) { self.text = text }
}
