// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitHubJiraSystemTray",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GitHubJiraSystemTray", targets: ["GitHubJiraSystemTray"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "GitHubJiraSystemTray",
            path: "Sources/GitHubJiraSystemTray"
        ),
        .testTarget(
            name: "GitHubJiraSystemTrayTests",
            dependencies: [
                "GitHubJiraSystemTray",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/GitHubJiraSystemTrayTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
