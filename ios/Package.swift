// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NelNoteSync",
    platforms: [.macOS(.v12), .iOS(.v16)],
    products: [.library(name: "NelNoteSync", targets: ["NelNoteSync"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
    targets: [
        .target(name: "NelNoteSync", dependencies: ["Yams"], path: "Sync"),
        .testTarget(name: "NelNoteSyncTests", dependencies: ["NelNoteSync"], path: "SyncTests")
    ]
)
