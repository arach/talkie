// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DemoKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DemoKit", targets: ["DemoKit"]),
    ],
    targets: [
        .target(name: "DemoKit"),
    ]
)
