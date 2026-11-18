// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipboard",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(name: "Clipboard", dependencies: ["ClipboardCore"]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
    ]
)
