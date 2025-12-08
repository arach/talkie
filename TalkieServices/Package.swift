// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TalkieServices",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TalkieServices",
            targets: ["TalkieServices"]
        ),
    ],
    dependencies: [
        .package(path: "../TalkieCore"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
    ],
    targets: [
        .target(
            name: "TalkieServices",
            dependencies: [
                "TalkieCore",
                "WhisperKit",
                "FluidAudio",
            ]
        ),
    ]
)
