// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DebugKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DebugKit",
            targets: ["DebugKit"]
        ),
    ],
    targets: [
        .target(
            name: "DebugKit",
            path: "Sources/DebugKit"
        ),
    ]
)
