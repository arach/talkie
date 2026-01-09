//
//  ConnectionsSettingsSection.swift
//  TalkieLive
//
//  Connections settings: XPC service status, environment info
//

import SwiftUI
import TalkieKit

// MARK: - Connections Settings Section

struct ConnectionsSettingsSection: View {
    @State private var engineStatus: EngineConnectionStatus = .unknown
    @State private var isRefreshing = false

    private let myPID = ProcessInfo.processInfo.processIdentifier

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header - consistent glass style
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    // Icon in a subtle glass container
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Color.accentColor.opacity(0.12))
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                        Image(systemName: "network")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: 36, height: 36)

                    // Title and subtitle stacked
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.sm) {
                            Text("CONNECTIONS")
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(Tracking.normal)
                                .foregroundColor(TalkieTheme.textPrimary)

                            Spacer()

                            Button(action: refresh) {
                                if isRefreshing {
                                    BrailleSpinner()
                                        .font(.system(size: 12, weight: .medium))
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(TalkieTheme.textSecondary)
                        }

                        Text("XPC service connections to Talkie ecosystem.")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }

                    Spacer()
                }

                // Subtle separator line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .padding(.top, Spacing.md)
            }

            // This Process
            ConnectionCard(
                title: "TalkieLive",
                subtitle: "This process",
                icon: "app.fill",
                status: .connected,
                pid: myPID,
                serviceName: nil
            )

            // TalkieEngine Connection
            ConnectionCard(
                title: "TalkieEngine",
                subtitle: "Transcription service",
                icon: "waveform",
                status: engineStatus,
                pid: engineStatus.pid,
                serviceName: TalkieEnvironment.current.engineXPCService
            )

            // Talkie Connection
            TalkieAppCard(
                serviceName: TalkieEnvironment.current.liveXPCService,
                onRefresh: refresh
            )

            // Environment Info
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("ENVIRONMENT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(Tracking.normal)
                    .foregroundColor(TalkieTheme.textTertiary)

                HStack {
                    Text("Mode:")
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textSecondary)
                    Text(TalkieEnvironment.current.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(TalkieTheme.accent)

                    Spacer()

                    if let bundleID = Bundle.main.bundleIdentifier {
                        Text(bundleID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .textSelection(.enabled)
                    }
                }
                .padding(Spacing.sm)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Color.white.opacity(0.04))
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.06),
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                )
            }
        }
        .padding(Spacing.lg)
        .onAppear { refresh() }
    }

    private func refresh() {
        isRefreshing = true

        // Check Engine connection
        Task {
            let client = EngineClient.shared
            let connected = await client.ensureConnected()

            await MainActor.run {
                if connected {
                    engineStatus = .connected
                } else {
                    engineStatus = .disconnected
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isRefreshing = false
                }
            }
        }
    }
}

// MARK: - Engine Connection Status

enum EngineConnectionStatus {
    case unknown
    case connected
    case disconnected

    var pid: Int32? { nil }  // TODO: Get from engine status
}

// MARK: - Talkie App Card (Special handling for main app)

struct TalkieAppCard: View {
    let serviceName: String?
    var onRefresh: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isLaunching = false

    // Check if Talkie is running - this is what matters for the Connections display
    // (XPC connection status is an implementation detail for real-time updates)
    private var isTalkieRunning: Bool {
        let targetBundleId = TalkieEnvironment.current == .production
            ? "jdi.talkie.core"
            : "jdi.talkie.core.dev"
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == targetBundleId
        }
    }

    private var statusColor: Color {
        isTalkieRunning ? .green : TalkieTheme.textTertiary
    }

    private var statusText: String {
        isTalkieRunning ? "Running" : "Not Running"
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon - Talkie app icon style
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(statusColor.opacity(isHovered ? 0.25 : 0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18))
                    .foregroundColor(statusColor)
            }
            .animation(TalkieAnimation.fast, value: isHovered)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text("Talkie")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Memos, Workflows & Dictations")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)

                if let serviceName = serviceName {
                    Text(serviceName)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            Spacer()

            // Status or Launch button
            if isTalkieRunning {
                // Show status when running
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(statusColor)
                }
            } else {
                // Show Launch button when not running
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action: launchAndRefresh) {
                        HStack(spacing: 4) {
                            if isLaunching {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                            }
                            Text(isLaunching ? "Launching..." : "Launch")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(TalkieTheme.textSecondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(Color.primary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLaunching)

                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }
        }
        .padding(Spacing.md)
        .glassHover(isHovered: isHovered, cornerRadius: CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.primary.opacity(isHovered ? 0.15 : 0.08), lineWidth: 0.5)
                .animation(TalkieAnimation.fast, value: isHovered)
        )
        .onHover { isHovered = $0 }
    }

    private func launchAndRefresh() {
        isLaunching = true
        launchTalkie()

        // Poll for connection after launching - Talkie needs time to start and connect
        Task {
            // Wait a bit for Talkie to launch
            try? await Task.sleep(for: .seconds(1.5))

            // Poll a few times waiting for connection
            for _ in 0..<5 {
                await MainActor.run {
                    onRefresh?()
                }
                try? await Task.sleep(for: .seconds(1.0))
            }

            await MainActor.run {
                isLaunching = false
            }
        }
    }

    private func launchTalkie() {
        #if DEBUG
        // Dev mode: Find the most recent Talkie.app in DerivedData
        if let devAppURL = findDevTalkieApp() {
            NSWorkspace.shared.open(devAppURL)
            return
        }
        #endif

        // Production: Try /Applications/Talkie.app first
        let prodPath = "/Applications/Talkie.app"
        if FileManager.default.fileExists(atPath: prodPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: prodPath))
            return
        }

        // Fall back to opening by bundle ID
        let bundleID = TalkieEnvironment.current == .production
            ? "com.jdi.talkie"
            : "com.jdi.talkie.dev"

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open(url)
        }
    }

    #if DEBUG
    /// Find the most recent Talkie.app dev build in DerivedData
    private func findDevTalkieApp() -> URL? {
        // Get our own bundle path to find DerivedData
        guard let myBundlePath = Bundle.main.bundlePath as NSString? else { return nil }

        // Navigate up from our path to find DerivedData root
        // e.g., .../DerivedData/TalkieLive-xxx/Build/Products/Debug/TalkieLive.app
        //       -> .../DerivedData/
        var path = myBundlePath as String
        while !path.isEmpty && !path.hasSuffix("DerivedData") {
            path = (path as NSString).deletingLastPathComponent
        }

        guard !path.isEmpty else { return nil }

        let derivedDataURL = URL(fileURLWithPath: path)
        let fm = FileManager.default

        // Search for Talkie.app in all project folders
        var candidates: [(url: URL, modified: Date)] = []

        if let projectFolders = try? fm.contentsOfDirectory(at: derivedDataURL, includingPropertiesForKeys: nil) {
            for folder in projectFolders {
                // Look for Talkie-* folders (not TalkieLive, TalkieEngine, etc.)
                let folderName = folder.lastPathComponent
                guard folderName.hasPrefix("Talkie-") && !folderName.hasPrefix("TalkieLive") && !folderName.hasPrefix("TalkieEngine") else {
                    continue
                }

                // Check Debug build path
                let appPath = folder
                    .appendingPathComponent("Build/Products/Debug/Talkie.app")

                if fm.fileExists(atPath: appPath.path) {
                    if let attrs = try? fm.attributesOfItem(atPath: appPath.path),
                       let modified = attrs[.modificationDate] as? Date {
                        candidates.append((url: appPath, modified: modified))
                    }
                }
            }
        }

        // Return the most recently modified
        return candidates
            .sorted { $0.modified > $1.modified }
            .first?.url
    }
    #endif
}

// MARK: - Connection Card

struct ConnectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let status: EngineConnectionStatus
    var pid: Int32?
    var serviceName: String?

    @State private var isHovered = false

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .red
        case .unknown: return .orange
        }
    }

    private var statusText: String {
        switch status {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .unknown: return "Unknown"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(statusColor.opacity(isHovered ? 0.25 : 0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(statusColor)
            }
            .animation(TalkieAnimation.fast, value: isHovered)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)

                if let serviceName = serviceName {
                    Text(serviceName)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            Spacer()

            // Status + PID
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(statusColor)
                }

                if let pid = pid {
                    Text("PID \(pid)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }
        }
        .padding(Spacing.md)
        .glassHover(isHovered: isHovered, cornerRadius: CornerRadius.md, accentColor: statusColor)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(statusColor.opacity(isHovered ? 0.4 : 0.2), lineWidth: isHovered ? 1 : 0.5)
                .animation(TalkieAnimation.fast, value: isHovered)
        )
        .onHover { isHovered = $0 }
    }
}
