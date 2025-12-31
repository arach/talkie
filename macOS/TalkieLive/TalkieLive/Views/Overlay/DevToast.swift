//
//  DevToast.swift
//  TalkieLive
//
//  Minimal ephemeral toast for dev mode messages.
//  DEBUG builds only. Tap to dismiss.
//

#if DEBUG

import SwiftUI
import AppKit

struct ToastAction {
    let label: String
    let action: () -> Void
}

@MainActor
final class DevToastController {
    static let shared = DevToastController()

    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, duration: TimeInterval? = 6.0, actions: [ToastAction] = []) {
        dismissTask?.cancel()

        let isNewWindow = window == nil
        let wasVisible = window?.isVisible == true

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 100),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.hasShadow = true
            window = w
        }

        guard let window = window else { return }

        let hostingView = NSHostingView(rootView: DevToastView(
            message: message,
            actions: actions,
            onDismiss: { [weak self] in self?.dismiss() }
        ))
        window.contentView = hostingView

        let size = hostingView.fittingSize
        window.setContentSize(NSSize(width: max(380, min(580, size.width + 48)), height: size.height + 24))

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - window.frame.width / 2
            let y = screen.visibleFrame.maxY - window.frame.height - 60
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Only animate in if window wasn't already visible
        if isNewWindow || !wasVisible {
            window.alphaValue = 0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        } else {
            // Window already visible - just update content without animation
            window.orderFrontRegardless()
        }

        // Only auto-dismiss if duration is provided (nil = stay until dismissed)
        if let duration = duration {
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        guard let window = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    /// Engine not running - show helpful dev message with option to launch
    func showEngineNotRunning(service: String) {
        let plistExists = hasDevDaemonPlist()
        let enginePath = findDebugEngine()

        if plistExists {
            show("""
            🔧 Debug Engine Not Running

            TalkieEngine can run two ways:

            • Daemon (LaunchAgent): Managed by macOS launchd.
              Auto-restarts if it crashes, survives logout,
              runs in background. Best for normal dev work.

            • Direct: Just launch the app. Easier to attach
              debugger, see logs in Xcode console. Stops
              when you quit. Use for debugging the engine.
            """, duration: nil, actions: [
                ToastAction(label: "Start Daemon") { [weak self] in
                    self?.startDebugDaemon()
                },
                ToastAction(label: "Launch Direct") { [weak self] in
                    if let path = self?.findDebugEngine() {
                        self?.launchDebugEngine(at: path)
                    }
                },
                ToastAction(label: "View Logs") { [weak self] in
                    self?.openDaemonLogs()
                },
                ToastAction(label: "Dismiss") { [weak self] in
                    self?.dismiss()
                }
            ])
        } else if enginePath != nil {
            show("""
            🔧 Debug Engine Not Running

            Found a debug build but no LaunchAgent plist.

            The plist is generated when you build TalkieEngine
            in Xcode. It tells launchd how to run the engine
            as a daemon (auto-restart, background service).

            For now, you can launch directly as a regular app.
            """, duration: nil, actions: [
                ToastAction(label: "Launch Direct") { [weak self] in
                    if let path = enginePath {
                        self?.launchDebugEngine(at: path)
                    }
                },
                ToastAction(label: "Open in Xcode") { [weak self] in
                    self?.openEngineInXcode()
                },
                ToastAction(label: "Dismiss") { [weak self] in
                    self?.dismiss()
                }
            ])
        } else {
            show("""
            🔧 Debug Engine Not Running

            No debug build of TalkieEngine found.

            Open TalkieEngine.xcodeproj (or TalkieSuite workspace)
            and build the TalkieEngine scheme. This creates the
            debug binary and a LaunchAgent plist for daemon mode.
            """, duration: nil, actions: [
                ToastAction(label: "Open in Xcode") { [weak self] in
                    self?.openEngineInXcode()
                },
                ToastAction(label: "Show in Finder") { [weak self] in
                    self?.showEngineProjectInFinder()
                },
                ToastAction(label: "Dismiss") { [weak self] in
                    self?.dismiss()
                }
            ])
        }
    }

    /// Check if dev daemon plist exists
    private func hasDevDaemonPlist() -> Bool {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/jdi.talkie.engine.dev.plist")
        return FileManager.default.fileExists(atPath: plistPath.path)
    }

    /// Start debug engine daemon via launchctl
    private func startDebugDaemon() {
        let label = "jdi.talkie.engine.dev"
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")

        let userID = getuid()

        // Try bootstrap first, then kickstart if already loaded
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootstrap", "gui/\(userID)", plistPath.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                show("✓ Dev engine daemon starting...", duration: 3.0)
            } else {
                // Already loaded - use kickstart to restart
                let kickTask = Process()
                kickTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                kickTask.arguments = ["kickstart", "-k", "gui/\(userID)/\(label)"]
                kickTask.standardOutput = FileHandle.nullDevice
                kickTask.standardError = FileHandle.nullDevice
                try kickTask.run()
                kickTask.waitUntilExit()
                show("✓ Dev engine daemon restarting...", duration: 3.0)
            }
        } catch {
            show("✗ Failed: \(error.localizedDescription)", duration: 5.0)
        }
    }

    /// Find debug TalkieEngine - checks stable path first, then DerivedData
    private func findDebugEngine() -> URL? {
        // Check stable path first (where build phase copies to)
        let stablePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Talkie/Debug/TalkieEngine.app")
        if FileManager.default.fileExists(atPath: stablePath.path) {
            return stablePath
        }

        // Fallback to DerivedData
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: derivedData,
            includingPropertiesForKeys: nil
        ) else { return nil }

        let buildPaths = [
            "Build/Products/Debug/TalkieEngine.app",
            "Index.noindex/Build/Products/Debug/TalkieEngine.app"
        ]

        for folder in contents {
            let folderName = folder.lastPathComponent
            if folderName.hasPrefix("TalkieSuite") || folderName.hasPrefix("TalkieEngine") || folderName.hasPrefix("Talkie-") {
                for buildPath in buildPaths {
                    let enginePath = folder.appendingPathComponent(buildPath)
                    if FileManager.default.fileExists(atPath: enginePath.path) {
                        return enginePath
                    }
                }
            }
        }
        return nil
    }

    /// Launch debug TalkieEngine directly
    private func launchDebugEngine(at path: URL) {
        NSWorkspace.shared.openApplication(
            at: path,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            Task { @MainActor in
                if let error = error {
                    self?.show("✗ Failed: \(error.localizedDescription)", duration: 5.0)
                } else {
                    self?.show("✓ Launching TalkieEngine...", duration: 3.0)
                }
            }
        }
    }

    /// Open daemon log files in Console.app
    private func openDaemonLogs() {
        let logPath = "/tmp/jdi.talkie.engine.dev.stdout.log"
        let logURL = URL(fileURLWithPath: logPath)

        if FileManager.default.fileExists(atPath: logPath) {
            NSWorkspace.shared.open(logURL)
        } else {
            // No logs yet - open /tmp in Finder
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/tmp")
            show("No daemon logs yet. Check /tmp after starting.", duration: 4.0)
        }
    }

    /// Open TalkieEngine project in Xcode
    private func openEngineInXcode() {
        // Try workspace first, then project
        let workspacePath = findTalkieWorkspace()
        let projectPath = findEngineProject()

        if let workspace = workspacePath {
            NSWorkspace.shared.open(workspace)
            dismiss()
        } else if let project = projectPath {
            NSWorkspace.shared.open(project)
            dismiss()
        } else {
            show("Couldn't find TalkieEngine project. Check ~/dev/talkie/", duration: 5.0)
        }
    }

    /// Show TalkieEngine project folder in Finder
    private func showEngineProjectInFinder() {
        let possiblePaths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("dev/talkie/macOS/TalkieEngine"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/talkie/macOS/TalkieEngine"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects/talkie/macOS/TalkieEngine")
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                dismiss()
                return
            }
        }

        // Fallback - just open home
        show("Couldn't find TalkieEngine folder.", duration: 4.0)
    }

    /// Find TalkieSuite workspace
    private func findTalkieWorkspace() -> URL? {
        let possiblePaths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("dev/talkie/macOS/TalkieSuite.xcworkspace"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/talkie/macOS/TalkieSuite.xcworkspace")
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    /// Find TalkieEngine project
    private func findEngineProject() -> URL? {
        let possiblePaths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("dev/talkie/macOS/TalkieEngine/TalkieEngine.xcodeproj"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/talkie/macOS/TalkieEngine/TalkieEngine.xcodeproj")
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }
}

struct DevToastView: View {
    let message: String
    var actions: [ToastAction] = []
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions.indices, id: \.self) { index in
                        let action = actions[index]
                        Button(action: action.action) {
                            Text(action.label)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(index == 0 ? .black : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(index == 0 ? Color.green : Color.white.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            ZStack {
                // Blur effect
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

                // Dark overlay
                Color.black.opacity(0.7)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .scaleEffect(isHovered ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#endif
