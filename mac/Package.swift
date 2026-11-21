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
// Desktop widgets (WidgetKit app extension, packaged into CalmBar.app/Contents/PlugIns by build-pkg.sh).
targets.append(.executableTarget(
    name: "CalmWidgets", dependencies: ["CalmShared"],
    swiftSettings: [.unsafeFlags(["-application-extension"])],
    linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]))
#endif

let package = Package(
    name: "Calm",
    platforms: [.macOS(.v14)],
    targets: targets
)
