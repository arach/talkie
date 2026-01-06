//
//  GatewayContainer.swift
//  GatewayContainer
//
//  Manages TalkieGateway running in an Apple container via Virtualization.framework
//

import Foundation
import Containerization
import ContainerizationOCI

/// Manages the TalkieGateway Linux container lifecycle
@MainActor
public final class GatewayContainer: Sendable {

    // MARK: - Configuration

    public struct Config {
        /// Container's IPv4 address (CIDR format, e.g., "192.168.64.2/24")
        public var ipAddress: String = "192.168.64.2/24"

        /// Gateway address for container networking
        public var gateway: String = "192.168.64.1"

        /// Port Gateway listens on inside the container
        public var port: Int = 8080

        /// Memory allocation in MiB
        public var memoryMiB: Int = 512

        /// Number of CPU cores
        public var cpuCount: Int = 2

        /// Path to Linux kernel
        public var kernelPath: URL?

        /// Path to Gateway source directory (to mount into container)
        public var gatewaySourcePath: URL?

        public init() {}
    }

    // MARK: - State

    private var container: LinuxContainer?
    private var manager: ContainerManager?
    private let config: Config

    /// The container's IP address (without CIDR suffix)
    public var containerIP: String? {
        config.ipAddress.components(separatedBy: "/").first
    }

    /// Full URL to reach the Gateway
    public var gatewayURL: URL? {
        guard let ip = containerIP else { return nil }
        return URL(string: "http://\(ip):\(config.port)")
    }

    // MARK: - Initialization

    public init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Lifecycle

    /// Start the Gateway container
    public func start() async throws {
        // 1. Load kernel
        let kernelURL = config.kernelPath ?? defaultKernelPath()
        let kernel = try Kernel(url: kernelURL, platform: .arm)

        // 2. Create container manager
        // Note: This requires an image store and init filesystem
        // For POC, we'll use a pre-built image

        // 3. Pull/build Gateway image
        let imageRef = "talkie-gateway:latest"

        // 4. Create container with networking
        /*
        container = try await manager?.create("talkie-gateway", reference: imageRef) { config in
            // CPU and memory
            config.resources.cpuCount = self.config.cpuCount
            config.resources.memoryInMiB = self.config.memoryMiB

            // Networking - dedicated IP, no port forwarding needed
            let ipv4Address = try CIDRv4(self.config.ipAddress)
            let ipv4Gateway = try IPv4Address(self.config.gateway)
            config.interfaces.append(NATInterface(
                ipv4Address: ipv4Address,
                ipv4Gateway: ipv4Gateway
            ))
            config.dns = .init(nameservers: [self.config.gateway])

            // Process to run
            config.process.args = ["bun", "run", "src/server.ts"]
            config.process.cwd = "/app"

            // Environment
            config.process.env = [
                "PORT": String(self.config.port),
                "NODE_ENV": "production"
            ]
        }

        // 5. Start the container
        try await container?.create()
        try await container?.start()
        */

        print("GatewayContainer: Would start container at \(gatewayURL?.absoluteString ?? "unknown")")
        print("GatewayContainer: This is a POC skeleton - full implementation requires:")
        print("  - Linux kernel (download from Kata Containers)")
        print("  - Image store setup")
        print("  - Init filesystem")
        print("  - Built Gateway OCI image")
    }

    /// Stop the Gateway container
    public func stop() async throws {
        // Graceful shutdown
        // try await container?.stop()
        container = nil
        print("GatewayContainer: Stopped")
    }

    /// Check if Gateway is healthy
    public func healthCheck() async -> Bool {
        guard let url = gatewayURL?.appendingPathComponent("health") else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func defaultKernelPath() -> URL {
        // Default location for Linux kernel
        // Users should download from Kata Containers or build their own
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Talkie")
            .appendingPathComponent("Container")
            .appendingPathComponent("vmlinux")
    }
}

// MARK: - Quick Start Helper

public extension GatewayContainer {

    /// Quick setup instructions for first-time use
    static func printSetupInstructions() {
        print("""

        ╔══════════════════════════════════════════════════════════════╗
        ║           TalkieGateway Container Setup                      ║
        ╠══════════════════════════════════════════════════════════════╣
        ║                                                              ║
        ║  1. Download Linux kernel from Kata Containers:              ║
        ║     https://github.com/kata-containers/kata-containers       ║
        ║                                                              ║
        ║  2. Place kernel at:                                         ║
        ║     ~/Library/Application Support/Talkie/Container/vmlinux   ║
        ║                                                              ║
        ║  3. Build Gateway container image:                           ║
        ║     cd macOS/TalkieGateway                                   ║
        ║     # Use cctl to build from Containerfile                   ║
        ║                                                              ║
        ║  4. Start Gateway:                                           ║
        ║     let gateway = GatewayContainer()                         ║
        ║     try await gateway.start()                                ║
        ║                                                              ║
        ║  Gateway will be available at: http://192.168.64.2:8080      ║
        ║                                                              ║
        ╚══════════════════════════════════════════════════════════════╝

        """)
    }
}
