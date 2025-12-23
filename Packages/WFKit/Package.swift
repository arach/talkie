// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WFKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Library - importable by other projects (Talkie, etc.)
        .library(name: "WFKit", targets: ["WFKit"]),
        // Demo app - example instantiation of WFKit
        .executable(name: "Workflow", targets: ["WorkflowApp"])
    ],
    dependencies: [
        // Local DebugKit package (sibling in monorepo)
        .package(path: "../DebugKit")
    ],
    targets: [
        // WFKit library - reusable components
        .target(
            name: "WFKit",
            dependencies: ["DebugKit"],
            path: "Sources/WFKit"
        ),
        // Demo app - imports WFKit
        .executableTarget(
            name: "WorkflowApp",
            dependencies: ["WFKit"],
            path: "Sources/WorkflowApp"
        )
    ]
)
