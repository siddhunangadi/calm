import Foundation
import CalmShared

/// Talks to the guard: reads its status file and drops requests in its inbox.
@MainActor
final class GuardClient: ObservableObject {
    static let shared = GuardClient()

    @Published private(set) var status: CalmStatus?
    @Published private(set) var guardRunning = false
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// For the design preview only.
    func showPreview(_ s: CalmStatus) {
        timer?.invalidate()
        status = s
        guardRunning = true
    }

    func refresh() {
        guard let data = FileManager.default.contents(atPath: CalmPaths.statusFile),
              let s = try? CalmJSON.decoder.decode(CalmStatus.self, from: data) else {
            status = nil
            guardRunning = false
            return
        }
        status = s
        // The guard writes every 3 seconds; 30 seconds of silence means it was stopped.
        guardRunning = Date().timeIntervalSince(s.heartbeat) < 30
    }

    func send(_ kind: CalmRequest.Kind, _ value: String? = nil) {
        guard let data = try? CalmJSON.encoder.encode(CalmRequest(kind, value)) else { return }
        let name = UUID().uuidString
        let tmp = CalmPaths.inboxDir + "/\(name).tmp"
        let final = CalmPaths.inboxDir + "/\(name).json"
        do {
            try data.write(to: URL(fileURLWithPath: tmp))
            try FileManager.default.moveItem(atPath: tmp, toPath: final)
        } catch {
            NSLog("Calm: could not send request: \(error)")
        }
        // Pick up the guard's answer quickly.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            self?.refresh()
        }
    }
}
