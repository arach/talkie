// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Talkie",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "TalkieMacOS",
            targets: ["TalkieMacOS"]
        ),
    ],
    dependencies: [
        // MLX Swift - Apple's ML framework for Apple Silicon (macOS only)
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0"),
    ],
    targets: [
        .target(
            name: "TalkieMacOS",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
            ]
        ),
    ]
)
