// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TalkieSpeech",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.13.6"),
    ],
    targets: [
        .executableTarget(
            name: "TalkieSpeech",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources"
        ),
    ]
)
