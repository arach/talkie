// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchCanonicalTest",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "NotchCanonicalTest",
            targets: ["NotchCanonicalTest"]
        )
    ],
    targets: [
        .executableTarget(
            name: "NotchCanonicalTest"
        ),
        .testTarget(
            name: "NotchCanonicalTestTests",
            dependencies: ["NotchCanonicalTest"]
        )
    ]
)
