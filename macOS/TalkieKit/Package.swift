// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TalkieKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TalkieKit",
            targets: ["TalkieKit"]),
    ],
    targets: [
        .target(
            name: "TalkieKit",
            dependencies: []),
    ]
)
