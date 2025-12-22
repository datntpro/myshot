// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MyShot",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Temporarily disabled to test crash
        // .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        // .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "1.16.0")
    ],
    targets: [
        .executableTarget(
            name: "MyShot",
            dependencies: [
                // Temporarily disabled to test crash
                // "HotKey",
                // "KeyboardShortcuts"
            ],
            path: "Sources"
        )
    ]
)
