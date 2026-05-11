// swift-tools-version: 5.9
//
// Voice Intent Benchmark Tool
// Standalone CLI for testing voice intent recognition accuracy.
//
// NOT part of production builds - lives in scripts/ for development use only.
//
// Usage:
//   cd scripts/voice-intent-benchmark
//   swift run voice-intent-benchmark [--json] [--output results.json] [--verbose]
//

import PackageDescription

let package = Package(
    name: "voice-intent-benchmark",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "voice-intent-benchmark", targets: ["VoiceIntentBenchmark"]),
    ],
    dependencies: [
        .package(path: "../../apps/macos/TalkieKit"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceIntentBenchmark",
            dependencies: [
                .product(name: "TalkieKit", package: "TalkieKit"),
            ],
            path: "Sources"),
    ]
)
