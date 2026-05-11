// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Note: The Talkie iOS app target uses IPHONEOS_DEPLOYMENT_TARGET 26.0; this package keeps a
// lower declared floor so SwiftPM/Xcode resolve cleanly. App Store installs follow the app.

import PackageDescription

let package = Package(
    name: "TalkieMobileKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "TalkieMobileKit",
            targets: ["TalkieMobileKit"]),
    ],
    targets: [
        .target(
            name: "TalkieMobileKit",
            dependencies: []),
    ]
)
