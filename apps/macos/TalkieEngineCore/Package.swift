// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TalkieEngineCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "TalkieEngineCore",
            targets: ["TalkieEngineCore"]
        ),
    ],
    dependencies: [
        .package(path: "../TalkieKit"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.13.6"),
    ],
    targets: [
        .target(
            name: "TalkieEngineCore",
            dependencies: [
                "TalkieKit",
                "WhisperKit",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
    ]
)
