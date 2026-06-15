//
//  TalkieReporter.swift
//  TalkieKit
//
//  Unified error reporting and context gathering for Talkie apps.
//  Collects logs, system info, and app state for troubleshooting.
//

import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Source app for the report
public enum ReportSource: String, Codable {
    case talkie
    case live
    case engine
}

/// App info for report
public struct ReportAppInfo: Codable {
    public let running: Bool
    public let pid: Int32?
    public let version: String?
    public let uptime: TimeInterval?
    public let memoryMB: Int?

    public init(running: Bool, pid: Int32?, version: String?, uptime: TimeInterval? = nil, memoryMB: Int? = nil) {
        self.running = running
        self.pid = pid
        self.version = version
        self.uptime = uptime
        self.memoryMB = memoryMB
    }
}

/// System info for report
public struct ReportSystemInfo: Codable {
    public let os: String
    public let osVersion: String
    public let chip: String
    public let memory: String
    public let locale: String?

    public init(os: String, osVersion: String, chip: String, memory: String, locale: String? = nil) {
        self.os = os
        self.osVersion = osVersion
        self.chip = chip
        self.memory = memory
        self.locale = locale
    }
}

/// Context for the report
public struct ReportContext: Codable {
    public let source: ReportSource
    public let connectionState: String?
    public let lastError: String?
    public let userDescription: String?
    public let contactInfo: String?

    public init(source: ReportSource, connectionState: String? = nil, lastError: String? = nil, userDescription: String? = nil, contactInfo: String? = nil) {
        self.source = source
        self.connectionState = connectionState
        self.lastError = lastError
        self.userDescription = userDescription
        self.contactInfo = contactInfo
    }
}

/// Health check snapshot included in reports
public struct ReportHealthCheck: Codable {
    public let talkieMicrophone: String
    public let talkieAccessibility: String
    public let talkieAutomation: String
    public let agentRunning: Bool
    public let agentConnected: Bool
    public let agentMic: String?
    public let agentAccessibility: String?
    public let engineRunning: Bool
    public let appEnvironment: String?
    public let helperEnvironment: String?
    public let permissionModel: String?
    public let talkieBundleId: String?
    public let talkieBundlePath: String?
    public let agentBundleId: String?
    public let agentLaunchdLabel: String?
    public let agentXPCService: String?
    public let agentObservedPath: String?
    public let agentPermissionPrincipal: String?
    public let agentLastPermissionCheck: String?
    public let agentPermissionSnapshotAgeSeconds: Int?
    public let permissionNotes: [String]?

    public init(
        talkieMicrophone: String,
        talkieAccessibility: String,
        talkieAutomation: String,
        agentRunning: Bool,
        agentConnected: Bool,
        agentMic: String?,
        agentAccessibility: String?,
        engineRunning: Bool,
        appEnvironment: String? = nil,
        helperEnvironment: String? = nil,
        permissionModel: String? = nil,
        talkieBundleId: String? = nil,
        talkieBundlePath: String? = nil,
        agentBundleId: String? = nil,
        agentLaunchdLabel: String? = nil,
        agentXPCService: String? = nil,
        agentObservedPath: String? = nil,
        agentPermissionPrincipal: String? = nil,
        agentLastPermissionCheck: String? = nil,
        agentPermissionSnapshotAgeSeconds: Int? = nil,
        permissionNotes: [String]? = nil
    ) {
        self.talkieMicrophone = talkieMicrophone
        self.talkieAccessibility = talkieAccessibility
        self.talkieAutomation = talkieAutomation
        self.agentRunning = agentRunning
        self.agentConnected = agentConnected
        self.agentMic = agentMic
        self.agentAccessibility = agentAccessibility
        self.engineRunning = engineRunning
        self.appEnvironment = appEnvironment
        self.helperEnvironment = helperEnvironment
        self.permissionModel = permissionModel
        self.talkieBundleId = talkieBundleId
        self.talkieBundlePath = talkieBundlePath
        self.agentBundleId = agentBundleId
        self.agentLaunchdLabel = agentLaunchdLabel
        self.agentXPCService = agentXPCService
        self.agentObservedPath = agentObservedPath
        self.agentPermissionPrincipal = agentPermissionPrincipal
        self.agentLastPermissionCheck = agentLastPermissionCheck
        self.agentPermissionSnapshotAgeSeconds = agentPermissionSnapshotAgeSeconds
        self.permissionNotes = permissionNotes
    }

    public var permissionLandscapeSummary: String {
        [
            "appEnv=\(appEnvironment ?? "unknown")",
            "helperEnv=\(helperEnvironment ?? "unknown")",
            "model=\(permissionModel ?? "unknown")",
            "talkieMicrophone=\(talkieMicrophone)",
            "talkieAX=\(talkieAccessibility)",
            "agentRunning=\(agentRunning)",
            "agentConnected=\(agentConnected)",
            "agentMic=\(agentMic ?? "Unknown")",
            "agentAX=\(agentAccessibility ?? "Unknown")",
            "agentPrincipal=\(agentPermissionPrincipal ?? "unknown")",
            "agentBundle=\(agentBundleId ?? "unknown")",
            "agentPath=\(agentObservedPath ?? "unknown")",
            "lastAgentCheck=\(agentLastPermissionCheck ?? "never")",
        ].joined(separator: " ")
    }
}

/// Full report structure matching the API
public struct TalkieReport: Codable {
    public let id: String
    public let timestamp: String
    public let system: ReportSystemInfo
    public let apps: [String: ReportAppInfo]
    public let context: ReportContext
    public let logs: [String]
    public let performance: [String: String]?
    public let health: ReportHealthCheck?

    public init(
        id: String,
        timestamp: String,
        system: ReportSystemInfo,
        apps: [String: ReportAppInfo],
        context: ReportContext,
        logs: [String],
        performance: [String: String]? = nil,
        health: ReportHealthCheck? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.system = system
        self.apps = apps
        self.context = context
        self.logs = logs
        self.performance = performance
        self.health = health
    }
}

/// Response from report submission
public struct ReportResponse: Codable {
    public let success: Bool
    public let id: String?
    public let key: String?
    public let error: String?
}

/// Configuration for TalkieReporter
public struct ReporterConfig {
    public let endpoint: String

    public init(endpoint: String) {
        self.endpoint = endpoint
    }

    /// Default production configuration
    public static let production = ReporterConfig(
        endpoint: "https://api.usetalkie.com/api"
    )
}

/// Unified reporter for Talkie ecosystem
@MainActor
public final class TalkieReporter {
    public static let shared = TalkieReporter()

    /// Configuration (can be overridden for testing)
    public var config: ReporterConfig = .production

    /// Log buffer - apps can push logs here
    private var logBuffer: [String] = []
    private let maxLogLines = 200

    /// Rate limiting - prevent spam
    private var lastSubmitTime: Date?
    private let minSubmitInterval: TimeInterval = 60  // 1 minute between submissions

    /// Callbacks for gathering app-specific info
    private var appInfoProviders: [ReportSource: () -> ReportAppInfo] = [:]
    private var connectionStateProvider: (() -> String)?
    private var lastErrorProvider: (() -> String?)?
    private var performanceProvider: (() -> [String: String])?
    private var healthCheckProvider: (() -> ReportHealthCheck)?

    private init() {}

    // MARK: - Configuration

    /// Register an app info provider
    public func registerAppInfo(for source: ReportSource, provider: @escaping () -> ReportAppInfo) {
        appInfoProviders[source] = provider
    }

    /// Register connection state provider
    public func registerConnectionState(provider: @escaping () -> String) {
        connectionStateProvider = provider
    }

    /// Register last error provider
    public func registerLastError(provider: @escaping () -> String?) {
        lastErrorProvider = provider
    }

    /// Register performance metrics provider
    public func registerPerformance(provider: @escaping () -> [String: String]) {
        performanceProvider = provider
    }

    /// Register health check provider
    public func registerHealthCheck(provider: @escaping () -> ReportHealthCheck) {
        healthCheckProvider = provider
    }

    // MARK: - Log Collection

    /// Add a log line (call from your logging system)
    public func addLog(_ line: String) {
        logBuffer.append(line)

        // Keep buffer bounded
        if logBuffer.count > maxLogLines {
            logBuffer.removeFirst(logBuffer.count - maxLogLines)
        }
    }

    /// Get recent logs from all relevant processes by reading today's log files from disk.
    /// Falls back to the in-memory buffer if no log files are found.
    public func getRecentLogs(count: Int = 200) -> [String] {
        let diskLogs = gatherLogsFromDisk(count: count)
        if !diskLogs.isEmpty { return diskLogs }
        // Fallback to in-memory buffer (main process only), redacted only for feedback export.
        return logBuffer.suffix(count).map(FeedbackLogRedactor.redact)
    }

    /// Clear log buffer
    public func clearLogs() {
        logBuffer.removeAll()
    }

    // MARK: - Disk Log Collection

    /// Log sources to include in reports: Talkie, TalkieAgent, TalkieEngine
    private static let reportLogSources: [(dir: String, label: String)] = [
        ("Talkie", "Talkie"),
        ("TalkieAgent", "Agent"),
        ("TalkieEngine", "Engine"),
    ]

    /// Read and merge today's log files from Talkie, Agent, and Engine.
    private func gatherLogsFromDisk(count: Int) -> [String] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        let fileName = "talkie-\(today).log"

        let appSupport = URL.applicationSupportDirectory
        var allLines: [String] = []

        for source in Self.reportLogSources {
            let logFile = appSupport
                .appendingPathComponent(source.dir)
                .appendingPathComponent("logs")
                .appendingPathComponent(fileName)

            guard let contents = try? String(contentsOf: logFile, encoding: .utf8) else { continue }

            for line in contents.components(separatedBy: "\n") where !line.isEmpty {
                // Format: timestamp|source|type|message|detail
                // Skip sync logs and redact user-authored content before reports include them.
                if line.contains("|SYNC|") { continue }

                allLines.append(FeedbackLogRedactor.redact(line))
            }
        }

        // Log files are per-process but each line has ISO timestamp — sort chronologically
        allLines.sort()

        // Return the most recent lines
        return Array(allLines.suffix(count))
    }

    // MARK: - Report Generation

    /// Gather full context and generate a report
    public func generateReport(
        source: ReportSource,
        userDescription: String? = nil,
        contactInfo: String? = nil
    ) -> TalkieReport {
        let id = generateShortId()
        let timestamp = ISO8601DateFormatter().string(from: Date())

        // Gather system info
        let system = gatherSystemInfo()

        // Gather app info from registered providers
        var apps: [String: ReportAppInfo] = [:]
        for (src, provider) in appInfoProviders {
            apps[src.rawValue] = provider()
        }

        // Build context
        let context = ReportContext(
            source: source,
            connectionState: connectionStateProvider?(),
            lastError: lastErrorProvider?().map(FeedbackLogRedactor.redact),
            userDescription: userDescription,
            contactInfo: contactInfo
        )

        // Get performance metrics
        let performance = performanceProvider?()

        // Get health check
        let health = healthCheckProvider?()

        // Get logs with user-authored prompt/transcript content redacted.
        var logs = getRecentLogs()
        if let health {
            let line = "\(timestamp)|Talkie|FEEDBACK|Permission landscape|\(health.permissionLandscapeSummary)"
            logs.append(FeedbackLogRedactor.redact(line))
        }

        return TalkieReport(
            id: id,
            timestamp: timestamp,
            system: system,
            apps: apps,
            context: context,
            logs: logs,
            performance: performance,
            health: health
        )
    }

    // MARK: - Submission

    /// Submit a report to the server
    public func submit(
        source: ReportSource,
        userDescription: String? = nil,
        contactInfo: String? = nil
    ) async throws -> ReportResponse {
        let report = generateReport(source: source, userDescription: userDescription, contactInfo: contactInfo)
        return try await submit(report: report)
    }

    /// Submit a pre-generated report
    public func submit(report: TalkieReport) async throws -> ReportResponse {
        // Rate limiting - prevent spam
        if let lastTime = lastSubmitTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minSubmitInterval {
                throw ReporterError.rateLimited(retryAfter: minSubmitInterval - elapsed)
            }
        }

        guard let url = URL(string: "\(config.endpoint)/report") else {
            throw ReporterError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(report)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReporterError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            let decoder = JSONDecoder()
            if let errorResponse = try? decoder.decode(ReportResponse.self, from: data) {
                throw ReporterError.serverError(errorResponse.error ?? "Unknown error")
            }
            throw ReporterError.serverError("HTTP \(httpResponse.statusCode)")
        }

        // Update last submit time on success
        lastSubmitTime = Date()

        let decoder = JSONDecoder()
        return try decoder.decode(ReportResponse.self, from: data)
    }

    // MARK: - Clipboard

    /// Copy report to clipboard as JSON
    public func copyToClipboard(source: ReportSource, userDescription: String? = nil, contactInfo: String? = nil) -> String {
        let report = generateReport(source: source, userDescription: userDescription, contactInfo: contactInfo)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8) else {
            return "Failed to generate report"
        }

        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        #endif

        return json
    }

    // MARK: - Helpers

    private func generateShortId() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).compactMap { _ in chars.randomElement() })
    }

    private func gatherSystemInfo() -> ReportSystemInfo {
        let processInfo = ProcessInfo.processInfo

        // OS info
        let osVersion = processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // Chip info
        var chip = "Unknown"
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
            chip = String(cString: buffer)
        }

        // Memory
        let memory = "\(processInfo.physicalMemory / (1024 * 1024 * 1024)) GB"

        // Locale
        let locale = Locale.current.identifier

        return ReportSystemInfo(
            os: "macOS",
            osVersion: osVersionString,
            chip: chip,
            memory: memory,
            locale: locale
        )
    }
}

// MARK: - Errors

public enum ReporterError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case rateLimited(retryAfter: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid reporter URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        case .rateLimited(let retryAfter):
            return "Rate limited. Try again in \(Int(retryAfter)) seconds."
        }
    }
}
