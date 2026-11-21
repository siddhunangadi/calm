import Foundation

/// Runs a system command and returns its exit code and output.
@discardableResult
func sh(_ path: String, _ args: [String]) -> (code: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func logLine(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

/// Writes a file atomically with the given permissions (owner is root because we run as root).
func writeFile(_ path: String, _ data: Data, mode: Int) throws {
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
}

func setFlag(_ flag: String, _ path: String, recursive: Bool = false) {
    guard FileManager.default.fileExists(atPath: path) else { return }
    sh("/usr/bin/chflags", (recursive ? ["-R"] : []) + [flag, path])
}

func flushDNSCache() {
    sh("/usr/bin/dscacheutil", ["-flushcache"])
    sh("/usr/bin/killall", ["-HUP", "mDNSResponder"])
}
