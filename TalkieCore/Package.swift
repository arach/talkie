// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TalkieCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TalkieCore",
            targets: ["TalkieCore"]
        ),
    ],
    targets: [
        .target(
            name: "TalkieCore"
        ),
    ]
)
