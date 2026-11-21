import Foundation
import CalmShared

// calmd: Calm's guard. Started by launchd as root (see com.calm.calmd.plist).
guard getuid() == 0 else {
    FileHandle.standardError.write(Data("calmd must run as root (it is started by launchd).\n".utf8))
    exit(1)
}

let fm = FileManager.default
try? fm.createDirectory(atPath: CalmPaths.supportDir, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: CalmPaths.privateDir, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: CalmPaths.inboxDir, withIntermediateDirectories: true)
try? fm.setAttributes([.posixPermissions: 0o755, .ownerAccountID: 0], ofItemAtPath: CalmPaths.supportDir)
try? fm.setAttributes([.posixPermissions: 0o700, .ownerAccountID: 0], ofItemAtPath: CalmPaths.privateDir)
// Like /tmp: anyone may drop a request in, nobody but root can read or delete others' files.
try? fm.setAttributes([.posixPermissions: 0o1733, .ownerAccountID: 0], ofItemAtPath: CalmPaths.inboxDir)

Guard().run()
