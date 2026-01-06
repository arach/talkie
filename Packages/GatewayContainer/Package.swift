// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GatewayContainer",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GatewayContainer", targets: ["GatewayContainer"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/containerization.git", branch: "main")
    ],
    targets: [
        .target(
            name: "GatewayContainer",
            dependencies: [
                .product(name: "Containerization", package: "containerization")
            ]
        )
    ]
)
