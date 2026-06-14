// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TalkieKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)  // Required for GRDB when building from TalkieSuite workspace
    ],
    products: [
        .library(
            name: "TalkieCore",
            targets: ["TalkieCore"]),
        .library(
            name: "TalkieKit",
            targets: ["TalkieKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "TalkieCore"),
        .target(
            name: "TalkieKit",
            dependencies: [
                "TalkieCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                .copy("Resources/Context"),
                .copy("Resources/Fonts"),
            ]),
        .testTarget(
            name: "TalkieKitTests",
            dependencies: ["TalkieKit"]),
    ]
)
