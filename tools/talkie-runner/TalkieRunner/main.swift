import AppKit
import SwiftUI

// MARK: - Environment

enum AppEnvironment: String, CaseIterable {
    case dev, prod

    var label: String {
        switch self {
        case .dev: return "DEV"
        case .prod: return "PROD"
        }
    }
}

// MARK: - App Configuration

struct TalkieApp: Identifiable {
    let id: String
    let name: String
    let icon: String
    let devBundleID: String
    let prodBundleID: String?  // nil for script-only apps
    let derivedDataName: String
    let isScript: Bool
    let scriptPath: String?
    let launchAgentPlist: String?      // Dev launch agent plist filename
    let prodLaunchAgentLabel: String?  // Prod launch agent label (to unload when running dev)
    let xcodeProjPath: String?
    let scheme: String?

    init(
        id: String,
        name: String,
        icon: String,
        devBundleID: String,
        prodBundleID: String? = nil,
        derivedDataName: String,
        isScript: Bool = false,
        scriptPath: String? = nil,
        launchAgentPlist: String? = nil,
        prodLaunchAgentLabel: String? = nil,
        xcodeProjPath: String? = nil,
        scheme: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.devBundleID = devBundleID
        self.prodBundleID = prodBundleID
        self.derivedDataName = derivedDataName
        self.isScript = isScript
        self.scriptPath = scriptPath
        self.launchAgentPlist = launchAgentPlist
        self.prodLaunchAgentLabel = prodLaunchAgentLabel
        self.xcodeProjPath = xcodeProjPath
        self.scheme = scheme
    }

    func bundleID(for env: AppEnvironment) -> String? {
        switch env {
        case .dev: return devBundleID
        case .prod: return prodBundleID
        }
    }

    static let all: [TalkieApp] = [
        TalkieApp(
            id: "talkie",
            name: "Talkie",
            icon: "waveform.circle.fill",
            devBundleID: "to.talkie.app.mac.dev",
            prodBundleID: "to.talkie.app.mac",
            derivedDataName: "Talkie-",
            xcodeProjPath: "apps/macos/Talkie/Talkie.xcodeproj",
            scheme: "Talkie"
        ),
        TalkieApp(
            id: "talkieagent",
            name: "TalkieAgent",
            icon: "mic.circle.fill",
            devBundleID: "to.talkie.app.agent.dev",
            prodBundleID: "to.talkie.app.agent",
            derivedDataName: "TalkieSuite-",
            launchAgentPlist: "to.talkie.app.agent.xpc.dev.plist",
            prodLaunchAgentLabel: "to.talkie.app.agent",
            xcodeProjPath: "apps/macos/TalkieAgent/TalkieAgent.xcodeproj",
            scheme: "TalkieAgent"
        ),
        TalkieApp(
            id: "talkieheadless",
            name: "TalkieHeadless",
            icon: "server.rack",
            devBundleID: "to.talkie.app.headless",
            prodBundleID: nil,
            derivedDataName: "TalkieHeadless-"
        ),
        TalkieApp(
            id: "talkieserver",
            name: "TalkieServer",
            icon: "network",
            devBundleID: "talkieserver",
            prodBundleID: nil,
            derivedDataName: "",
            isScript: true,
            scriptPath: "apps/macos/TalkieServer"
        )
    ]
}

// MARK: - App State

@Observable
class AppState {
    // Track running apps by environment
    var runningDevApps: Set<String> = []   // Dev bundle IDs
    var runningProdApps: Set<String> = []  // Prod bundle IDs

    // Track paths by environment
    var devPaths: [String: URL] = [:]      // appId -> DerivedData path
    var prodPaths: [String: URL] = [:]     // appId -> /Applications/ path

    // Build dates by environment
    var devBuildDates: [String: Date] = [:]
    var prodBuildDates: [String: Date] = [:]

    // Legacy tracking for dev apps (launched build dates)
    var launchedDevBuildDates: [String: Date] = [:]
    var devAppsWithUpdates: Set<String> = []

    // Building state
    var buildingApps: Set<String> = []

    // Script processes
    var scriptProcesses: [String: Process] = [:]

    // Auto-restart setting (for dev only)
    var autoRestart: Bool = UserDefaults.standard.bool(forKey: "autoRestart") {
        didSet { UserDefaults.standard.set(autoRestart, forKey: "autoRestart") }
    }

    // Base path for the talkie repo
    let talkieBasePath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("dev/talkie")
    }()

    // PID file directory for tracking background processes
    let pidDirectory: URL = {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".talkie/pids")
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }()

    func pidFile(for appId: String) -> URL {
        pidDirectory.appendingPathComponent("\(appId).pid")
    }

    func readPID(for appId: String) -> Int32? {
        let file = pidFile(for: appId)
        guard let content = try? String(contentsOf: file, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    func writePID(_ pid: Int32, for appId: String) {
        let file = pidFile(for: appId)
        try? "\(pid)".write(to: file, atomically: true, encoding: .utf8)
    }

    func removePID(for appId: String) {
        let file = pidFile(for: appId)
        try? FileManager.default.removeItem(at: file)
    }

    func isProcessRunning(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    init() {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    func refresh() {
        let workspace = NSWorkspace.shared
        let runningBundleIDs = Set(workspace.runningApplications.compactMap { $0.bundleIdentifier })

        // Check dev apps
        runningDevApps = Set(TalkieApp.all.compactMap { app in
            runningBundleIDs.contains(app.devBundleID) ? app.devBundleID : nil
        })

        // Check prod apps
        runningProdApps = Set(TalkieApp.all.compactMap { app in
            guard let prodID = app.prodBundleID else { return nil }
            return runningBundleIDs.contains(prodID) ? prodID : nil
        })

        // Check script apps via PID file or pgrep
        for app in TalkieApp.all where app.isScript {
            var running = false

            if let pid = readPID(for: app.id), isProcessRunning(pid: pid) {
                running = true
            } else if app.id == "talkieserver" && isServerRunning() {
                running = true
            }

            if running {
                runningDevApps.insert(app.devBundleID)
            } else {
                removePID(for: app.id)
            }
        }

        findAppPaths()
    }

    func isServerRunning() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "TalkieServer.*server"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    func findAppPaths() {
        findDevPaths()
        findProdPaths()
    }

    func findDevPaths() {
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: derivedData,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        var appsToRestart: [TalkieApp] = []

        for app in TalkieApp.all {
            // Script apps are always "available"
            if app.isScript {
                if let scriptPath = app.scriptPath {
                    let fullPath = talkieBasePath.appendingPathComponent(scriptPath)
                    if FileManager.default.fileExists(atPath: fullPath.path) {
                        devPaths[app.id] = fullPath
                    }
                }
                continue
            }

            let matching = contents
                .filter { $0.lastPathComponent.hasPrefix(app.derivedDataName) }
                .compactMap { url -> (URL, Date)? in
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    guard let date = values?.contentModificationDate else { return nil }
                    return (url, date)
                }
                .sorted { $0.1 > $1.1 }
                .first

            if let (folder, folderDate) = matching {
                let appPath = folder.appendingPathComponent("Build/Products/Debug/\(app.name).app")
                if FileManager.default.fileExists(atPath: appPath.path) {
                    let appDate = (try? appPath.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? folderDate

                    devPaths[app.id] = appPath
                    devBuildDates[app.id] = appDate

                    // Check if there's a newer build than when we launched
                    if isRunning(app, environment: .dev), let launchedDate = launchedDevBuildDates[app.id] {
                        if appDate > launchedDate {
                            devAppsWithUpdates.insert(app.id)

                            if autoRestart {
                                appsToRestart.append(app)
                            }
                        } else {
                            devAppsWithUpdates.remove(app.id)
                        }
                    }
                }
            }
        }

        for app in appsToRestart {
            restart(app, environment: .dev)
        }
    }

    func findProdPaths() {
        for app in TalkieApp.all where app.prodBundleID != nil {
            let appPath = URL(fileURLWithPath: "/Applications/\(app.name).app")
            if FileManager.default.fileExists(atPath: appPath.path) {
                prodPaths[app.id] = appPath
                if let date = (try? appPath.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                    prodBuildDates[app.id] = date
                }
            }
        }
    }

    func isRunning(_ app: TalkieApp, environment: AppEnvironment) -> Bool {
        switch environment {
        case .dev:
            return runningDevApps.contains(app.devBundleID)
        case .prod:
            guard let prodID = app.prodBundleID else { return false }
            return runningProdApps.contains(prodID)
        }
    }

    func hasPath(_ app: TalkieApp, environment: AppEnvironment) -> Bool {
        switch environment {
        case .dev: return devPaths[app.id] != nil
        case .prod: return prodPaths[app.id] != nil
        }
    }

    func launch(_ app: TalkieApp, environment: AppEnvironment, debugMode: Bool = false) {
        if app.isScript && environment == .dev {
            launchScript(app, debugMode: debugMode)
            return
        }

        // CONFLICT PREVENTION: For launchd-managed helpers (TalkieAgent),
        // stop the opposite environment first. Running both causes XPC to connect
        // to the wrong one (e.g., stale production agent missing new XPC methods).
        let oppositeEnv: AppEnvironment = environment == .dev ? .prod : .dev
        if isRunning(app, environment: oppositeEnv) {
            print("⚠️ Stopping \(oppositeEnv.label) \(app.name) before launching \(environment.label)")
            terminate(app, environment: oppositeEnv)
            killStaleProcesses(named: app.name, keepPID: nil)
            Thread.sleep(forTimeInterval: 0.3)
        }

        let path: URL?
        switch environment {
        case .dev:
            // Check for LaunchAgent for dev XPC services
            if let plist = app.launchAgentPlist, !debugMode {
                if let buildDate = devBuildDates[app.id] {
                    launchedDevBuildDates[app.id] = buildDate
                }
                devAppsWithUpdates.remove(app.id)
                loadLaunchAgent(plist)
                return
            }
            path = devPaths[app.id]
            if let buildDate = devBuildDates[app.id] {
                launchedDevBuildDates[app.id] = buildDate
            }
            devAppsWithUpdates.remove(app.id)
        case .prod:
            path = prodPaths[app.id]
        }

        guard let path = path else { return }
        NSWorkspace.shared.openApplication(at: path, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    func launchScript(_ app: TalkieApp, debugMode: Bool = false) {
        guard let scriptPath = app.scriptPath else { return }
        let fullPath = talkieBasePath.appendingPathComponent(scriptPath)

        if debugMode {
            let script = """
            tell application "Terminal"
                activate
                do script "cd '\(fullPath.path)' && bun run src/server.ts --local"
            end tell
            """

            let process = Process()
            process.launchPath = "/usr/bin/osascript"
            process.arguments = ["-e", script]

            do {
                try process.run()
            } catch {
                print("Failed to launch \(app.name) in debug mode: \(error)")
            }
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bun", "run", "src/server.ts", "--local"]
            process.currentDirectoryURL = fullPath

            let logFile = pidDirectory.appendingPathComponent("\(app.id).log")
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            let fileHandle = try? FileHandle(forWritingTo: logFile)
            process.standardOutput = fileHandle
            process.standardError = fileHandle

            do {
                try process.run()
                writePID(process.processIdentifier, for: app.id)
                scriptProcesses[app.id] = process
                runningDevApps.insert(app.devBundleID)
            } catch {
                print("Failed to launch \(app.name): \(error)")
            }
        }
    }

    func terminate(_ app: TalkieApp, environment: AppEnvironment) {
        if app.isScript && environment == .dev {
            terminateScript(app)
            return
        }

        let bundleID: String?
        switch environment {
        case .dev:
            if let plist = app.launchAgentPlist {
                unloadLaunchAgent(plist)
                runningDevApps.remove(app.devBundleID)
                return
            }
            bundleID = app.devBundleID
        case .prod:
            // Unload prod launch agent so it doesn't respawn
            if let prodLabel = app.prodLaunchAgentLabel {
                unloadProdLaunchAgent(prodLabel)
                runningProdApps.remove(app.prodBundleID ?? "")
                return
            }
            bundleID = app.prodBundleID
        }

        guard let bundleID = bundleID else { return }

        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleID }
            .forEach { $0.terminate() }
    }

    func unloadLaunchAgent(_ plist: String) {
        let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/" + plist
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistPath]
        try? task.run()
        task.waitUntilExit()
        print("Unloaded LaunchAgent: \(plist)")
    }

    func loadLaunchAgent(_ plist: String) {
        let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/" + plist
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", plistPath]
        try? task.run()
        task.waitUntilExit()
        print("Loaded LaunchAgent: \(plist)")
    }

    func unloadProdLaunchAgent(_ label: String) {
        let uid = getuid()
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["bootout", "gui/\(uid)/\(label)"]
        try? task.run()
        task.waitUntilExit()
        print("Unloaded prod LaunchAgent: \(label)")
    }

    func terminateScript(_ app: TalkieApp) {
        if let pid = readPID(for: app.id) {
            kill(pid, SIGTERM)
        }

        if let process = scriptProcesses[app.id] {
            process.terminate()
            scriptProcesses.removeValue(forKey: app.id)
        }

        if app.id == "talkieserver" {
            let task = Process()
            task.launchPath = "/usr/bin/pkill"
            task.arguments = ["-f", "TalkieServer.*server"]
            try? task.run()
            task.waitUntilExit()
        }

        removePID(for: app.id)
        runningDevApps.remove(app.devBundleID)
    }

    func restart(_ app: TalkieApp, environment: AppEnvironment) {
        terminate(app, environment: environment)
        // Also kill stale processes (old builds still running from weeks ago)
        killStaleProcesses(named: app.name, keepPID: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.launch(app, environment: environment)
        }
    }

    /// Kill processes matching a name that aren't the one we want to keep.
    /// Catches stale debug/prod builds from old Xcode sessions.
    func killStaleProcesses(named processName: String, keepPID: pid_t?) {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", processName]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = output.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }

        for pid in pids {
            if let keepPID, pid == keepPID { continue }
            print("Killing stale \(processName) process (PID \(pid))")
            kill(pid, SIGTERM)
        }
    }

    func build(_ app: TalkieApp, completion: @escaping (Bool) -> Void) {
        guard let projPath = app.xcodeProjPath, let scheme = app.scheme else {
            completion(false)
            return
        }

        buildingApps.insert(app.id)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [
            "-project", talkieBasePath.appendingPathComponent(projPath).path,
            "-scheme", scheme,
            "-configuration", "Debug",
            "build"
        ]

        let logFile = pidDirectory.appendingPathComponent("build-\(app.id).log")
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        if let fileHandle = try? FileHandle(forWritingTo: logFile) {
            process.standardOutput = fileHandle
            process.standardError = fileHandle
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.buildingApps.remove(app.id)
                self?.refresh()
                completion(proc.terminationStatus == 0)
            }
        }

        do {
            try process.run()
        } catch {
            buildingApps.remove(app.id)
            print("Failed to build \(app.name): \(error)")
            completion(false)
        }
    }

    // Convenience methods for batch operations
    func startAll(environment: AppEnvironment) {
        for app in TalkieApp.all {
            if !isRunning(app, environment: environment) && hasPath(app, environment: environment) {
                // Skip script apps for prod (they don't have prod versions)
                if environment == .prod && app.prodBundleID == nil { continue }
                launch(app, environment: environment)
            }
        }
    }

    func stopAll(environment: AppEnvironment) {
        for app in TalkieApp.all where isRunning(app, environment: environment) {
            terminate(app, environment: environment)
        }
    }

    func buildAll(completion: @escaping (Int, Int) -> Void) {
        let buildableApps = TalkieApp.all.filter { $0.xcodeProjPath != nil && $0.scheme != nil }
        var successCount = 0
        var failCount = 0
        let group = DispatchGroup()

        for app in buildableApps {
            group.enter()
            build(app) { success in
                if success {
                    successCount += 1
                } else {
                    failCount += 1
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(successCount, failCount)
        }
    }
}

// MARK: - Relative Time Formatter

func relativeTime(from date: Date?) -> String {
    guard let date = date else { return "—" }
    let interval = Date().timeIntervalSince(date)

    if interval < 60 { return "just now" }
    if interval < 3600 { return "\(Int(interval / 60))m ago" }
    if interval < 86400 { return "\(Int(interval / 3600))h ago" }
    if interval < 604800 { return "\(Int(interval / 86400))d ago" }
    return "\(Int(interval / 604800))w ago"
}

// MARK: - Panel View

struct PanelView: View {
    @Bindable var state: AppState
    var onClose: () -> Void
    @State private var isCommandHeld = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("TALKIE RUNNER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                if isCommandHeld {
                    Text("⌘")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()
                Button {
                    state.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Column headers
            HStack(spacing: 8) {
                Text("")
                    .frame(width: 26)
                Text("")
                Spacer()
                VStack(spacing: 1) {
                    Text("DEV")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if isCommandHeld {
                        Text("DerivedData")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 70)
                VStack(spacing: 1) {
                    Text("PROD")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if isCommandHeld {
                        Text("/Applications")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 70)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            // App list
            ForEach(TalkieApp.all) { app in
                AppRow(app: app, state: state, isCommandHeld: isCommandHeld)
            }

            Divider()

            // Quick actions
            VStack(spacing: 6) {
                // DEV actions
                HStack(spacing: 6) {
                    Text("DEV")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.blue)
                        .frame(width: 36, alignment: .leading)

                    Button("Start") { state.startAll(environment: .dev) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Button("Stop") { state.stopAll(environment: .dev) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Button("Build") {
                        state.buildAll { success, fail in
                            print("Build complete: \(success) succeeded, \(fail) failed")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Spacer()
                }

                // PROD actions
                HStack(spacing: 6) {
                    Text("PROD")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green)
                        .frame(width: 36, alignment: .leading)

                    Button("Start") { state.startAll(environment: .prod) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Button("Stop") { state.stopAll(environment: .prod) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Spacer()

                    // Auto-restart toggle (dev only)
                    Toggle(isOn: $state.autoRestart) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                    }
                    .toggleStyle(.button)
                    .controlSize(.mini)
                    .help("Auto-restart dev on new builds")
                    .tint(state.autoRestart ? .blue : nil)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: isCommandHeld ? 380 : 340)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.15), value: isCommandHeld)
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isCommandHeld = event.modifierFlags.contains(.command)
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }
}

struct AppRow: View {
    let app: TalkieApp
    @Bindable var state: AppState
    let isCommandHeld: Bool
    @State private var isOptionPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                // App icon and name
                Image(systemName: app.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(anyRunning ? .primary : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 12, weight: anyRunning ? .medium : .regular))
                        .foregroundStyle(anyRunning ? .primary : .secondary)
                        .lineLimit(1)

                    if isCommandHeld {
                        Text(app.devBundleID)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // DEV column
                EnvironmentControls(
                    app: app,
                    environment: .dev,
                    state: state,
                    isCommandHeld: isCommandHeld,
                    isOptionPressed: $isOptionPressed
                )
                .frame(width: 70)

                // PROD column
                if app.prodBundleID != nil {
                    EnvironmentControls(
                        app: app,
                        environment: .prod,
                        state: state,
                        isCommandHeld: isCommandHeld,
                        isOptionPressed: .constant(false)
                    )
                    .frame(width: 70)
                } else {
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 70)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isCommandHeld ? 6 : 5)
        .background(anyRunning ? Color.green.opacity(0.06) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isCommandHeld)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isOptionPressed = event.modifierFlags.contains(.option)
                return event
            }
        }
    }

    var anyRunning: Bool {
        state.isRunning(app, environment: .dev) || state.isRunning(app, environment: .prod)
    }
}

struct EnvironmentControls: View {
    let app: TalkieApp
    let environment: AppEnvironment
    @Bindable var state: AppState
    let isCommandHeld: Bool
    @Binding var isOptionPressed: Bool

    var isRunning: Bool { state.isRunning(app, environment: environment) }
    var hasPath: Bool { state.hasPath(app, environment: environment) }
    var isBuilding: Bool { state.buildingApps.contains(app.id) }
    var hasUpdate: Bool { environment == .dev && state.devAppsWithUpdates.contains(app.id) }

    var buildDate: Date? {
        switch environment {
        case .dev: return state.devBuildDates[app.id]
        case .prod: return state.prodBuildDates[app.id]
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                // Status dot
                ZStack {
                    Circle()
                        .fill(isRunning ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)

                    if hasUpdate {
                        Circle()
                            .stroke(Color.yellow, lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                    }
                }

                // Action buttons
                if isRunning {
                    Button { state.terminate(app, environment: environment) }
                        label: { Image(systemName: "stop.fill").font(.system(size: 8)) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Button { state.restart(app, environment: environment) }
                        label: {
                            Image(systemName: hasUpdate ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                                .font(.system(size: 8))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(hasUpdate ? .yellow : nil)
                } else if hasPath {
                    Button {
                        let debugMode = environment == .dev && NSEvent.modifierFlags.contains(.option)
                        state.launch(app, environment: environment, debugMode: debugMode)
                    }
                    label: {
                        Image(systemName: app.isScript && isOptionPressed && environment == .dev ? "terminal.fill" : "play.fill")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(app.isScript && environment == .dev ? "Click to start • ⌥-click for Terminal" : "Start app")
                } else if environment == .dev && app.xcodeProjPath != nil {
                    Button { state.build(app) { _ in } }
                        label: {
                            Image(systemName: isBuilding ? "hourglass" : "hammer.fill")
                                .font(.system(size: 8))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isBuilding)
                } else {
                    Text("—")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
            }

            // Build time shown when ⌘ held
            if isCommandHeld && hasPath {
                Text(relativeTime(from: buildDate))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Floating Panel

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: FloatingPanel?
    let state = AppState()
    var eventMonitor: Any?
    var selfWatchTimer: Timer?
    var launchBinaryDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Talkie Runner")
            button.action = #selector(togglePanel)
            button.target = self
        }

        // Self-reload: watch our own binary for changes
        startSelfWatch()
    }

    func startSelfWatch() {
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        launchBinaryDate = (try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        selfWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForSelfUpdate()
        }
    }

    func checkForSelfUpdate() {
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        guard let currentDate = (try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              let launchDate = launchBinaryDate else { return }

        if currentDate > launchDate {
            print("TalkieRunner binary updated, relaunching...")
            relaunchSelf()
        }
    }

    func relaunchSelf() {
        let executablePath = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments[0]

        // Spawn new instance
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = []

        do {
            try process.run()
            // Give it a moment to start, then exit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            print("Failed to relaunch: \(error)")
        }
    }

    @objc func togglePanel() {
        if let panel = panel, panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    func openPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        state.refresh()

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 340

        let panelX = screenRect.midX - panelWidth / 2
        let panelY = screenRect.minY - panelHeight - 4

        let contentRect = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        panel = FloatingPanel(contentRect: contentRect)

        let hostingView = NSHostingView(rootView:
            PanelView(state: state, onClose: { [weak self] in self?.closePanel() })
                .clipShape(RoundedRectangle(cornerRadius: 10))
        )

        panel?.contentView = hostingView
        panel?.makeKeyAndOrderFront(nil)

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePanel()
        }
    }

    func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
