// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeUsage", path: "Sources/ClaudeUsage"),
        .testTarget(name: "ClaudeUsageTests", dependencies: ["ClaudeUsage"], path: "Tests/ClaudeUsageTests"),
    ],
    swiftLanguageModes: [.v5]
)
