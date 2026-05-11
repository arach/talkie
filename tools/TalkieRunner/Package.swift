// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TalkieRunner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TalkieRunner",
            path: "TalkieRunner"
        )
    ]
)
