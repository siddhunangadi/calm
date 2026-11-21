// swift-tools-version:5.9
import PackageDescription

var targets: [Target] = [
    // Pure logic shared by the guard and the menu-bar app. Foundation only, so it is easy to test.
    .target(name: "CalmShared"),
    // The guard: runs as root, always on, does the blocking.
    .executableTarget(name: "calmd", dependencies: ["CalmShared"]),
    .testTarget(name: "CalmSharedTests", dependencies: ["CalmShared"]),
]

#if os(macOS)
// The menu-bar app needs AppKit/SwiftUI, so it only builds on a Mac.
targets.append(.executableTarget(name: "CalmBar", dependencies: ["CalmShared"]))
#endif

let package = Package(
    name: "Calm",
    platforms: [.macOS(.v13)],
    targets: targets
)
