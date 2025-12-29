//
//  main.swift
//  TalkieEngine
//
//  Entry point that sets up XPC listener before NSApplication
//

import Cocoa
import os
import Darwin
import TalkieKit

private let log = Log(.system)


// MARK: - Signal Handling

/// Handle SIGTERM gracefully instead of crashing
func setupSignalHandling() {
    // Create a dispatch source for SIGTERM
    signal(SIGTERM, SIG_IGN)  // Ignore default handler

    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    source.setEventHandler {
        log.info("Received SIGTERM, shutting down gracefully...")

        // Give a brief moment for any in-flight work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }
    source.resume()

    // Keep reference to prevent deallocation
    _signalSource = source
}

private var _signalSource: DispatchSourceSignal?

// MARK: - Single Instance Enforcement (Honor System)

/// Find and handle any existing TalkieEngine processes
/// New instance always wins - asks old one to shut down gracefully
func ensureSingleInstance() {
    let myPID = ProcessInfo.processInfo.processIdentifier
    let existingPIDs = findExistingEngineProcesses(excludingPID: myPID)

    guard !existingPIDs.isEmpty else {
        log.info("No existing TalkieEngine processes found", critical: true)
        return
    }

    log.info("Found \(existingPIDs.count) existing TalkieEngine process(es): \(existingPIDs)", critical: true)

    // Try to ask the existing service to shut down gracefully via XPC
    // This only works if both are on the same namespace (both debug or both production)
    let gracefulShutdownWorked = requestGracefulShutdown()

    if gracefulShutdownWorked {
        // Wait for graceful shutdown (up to 2 min for in-progress work)
        waitForProcessesToExit(pids: existingPIDs, timeout: 130)
    } else {
        // XPC failed - likely different namespace (debug vs prod)
        // These are separate deployments, don't interfere with each other
        #if DEBUG
        log.info("Existing process is likely production build - debug and production can coexist", critical: true)
        #else
        log.info("Existing process is likely debug build - debug and production can coexist", critical: true)
        #endif
        // Don't wait or kill - let them coexist on different namespaces
    }
}

/// Find all TalkieEngine processes except our own
func findExistingEngineProcesses(excludingPID myPID: Int32) -> [Int32] {
    var pids: [Int32] = []

    // Get number of processes
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }

    // Allocate buffer and get PIDs
    var pidBuffer = [Int32](repeating: 0, count: Int(count) * 2)
    let actualCount = proc_listallpids(&pidBuffer, Int32(pidBuffer.count * MemoryLayout<Int32>.size))

    guard actualCount > 0 else { return [] }

    // Check each process
    for i in 0..<Int(actualCount) {
        let pid = pidBuffer[i]
        if pid == myPID || pid <= 0 { continue }

        // Get process name
        var name = [CChar](repeating: 0, count: 1024)
        let result = proc_name(pid, &name, UInt32(name.count))

        if result > 0 {
            let processName = String(cString: name)
            if processName == "TalkieEngine" {
                pids.append(pid)
            }
        }
    }

    return pids
}

/// Ask the existing engine to shut down gracefully via XPC
/// This is the "honor system" - we ask nicely and wait
/// Note: Only works if both instances are on the same namespace (both debug or both production)
func requestGracefulShutdown() -> Bool {
    log.info("Requesting graceful shutdown of existing instance via \(kTalkieEngineServiceName)...", critical: true)

    let connection = NSXPCConnection(machServiceName: kTalkieEngineServiceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: TalkieEngineProtocol.self)
    connection.resume()

    let semaphore = DispatchSemaphore(value: 0)
    var shutdownAccepted = false
    var xpcFailed = false

    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        // XPC error means we can't communicate - likely different namespace (debug vs prod)
        log.info("XPC connection failed (likely different namespace): \(error.localizedDescription)", critical: true)
        xpcFailed = true
        semaphore.signal()
    } as? TalkieEngineProtocol

    // Ask to shut down, wait for completion of any in-progress work
    proxy?.requestShutdown(waitForCompletion: true) { accepted in
        shutdownAccepted = accepted
        log.info("Shutdown request \(accepted ? "accepted" : "rejected")", critical: true)
        semaphore.signal()
    }

    // Wait for the shutdown request (short timeout since XPC errors are fast)
    let result = semaphore.wait(timeout: .now() + 5)

    connection.invalidate()

    if result == .timedOut || xpcFailed {
        return false // Couldn't communicate via XPC
    }

    return shutdownAccepted
}

/// Wait for processes to exit, with timeout
func waitForProcessesToExit(pids: [Int32], timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        // Check if any are still running
        var anyRunning = false
        for pid in pids {
            if kill(pid, 0) == 0 {
                anyRunning = true
                break
            }
        }

        if !anyRunning {
            log.info("All existing TalkieEngine processes have exited", critical: true)
            return
        }

        // Still running, wait a bit
        Thread.sleep(forTimeInterval: 0.5)
    }

    // Timeout - force kill any remaining
    log.warning("Timeout waiting for graceful shutdown, forcing termination", critical: true)
    for pid in pids {
        if kill(pid, 0) == 0 {
            log.warning("Force killing PID \(pid)", critical: true)
            kill(pid, SIGKILL)
        }
    }

    // Brief pause for cleanup
    Thread.sleep(forTimeInterval: 0.5)
}

// MARK: - Launch Mode

/// Check if running as daemon (launched by launchd with --daemon flag)
let isDaemonMode = CommandLine.arguments.contains("--daemon")

// MARK: - Main Entry Point

// Global references to prevent deallocation (must be at global scope for AppDelegate to access)
var xpcListener: NSXPCListener!
var engineService: EngineService!
var serviceWrapper: XPCServiceWrapper!
var listenerDelegate: EngineListenerDelegate!

// Wrap the entire startup in autoreleasepool since NSApplicationMain isn't active yet
autoreleasepool {
    // Configure unified logger first
    TalkieLogger.configure(source: .talkieEngine)

    // Set up signal handling first so SIGTERM doesn't crash the debugger
    setupSignalHandling()

    log.info("TalkieEngine starting (PID: \(ProcessInfo.processInfo.processIdentifier), mode: \(isDaemonMode ? "daemon" : "debug"))...", critical: true)

    // Determine XPC service name based on bundle ID and launch mode
    // Multiple environments can run side-by-side on different XPC services
    let activeServiceName: String
    let activeMode: EngineServiceMode

    // Check bundle identifier to determine environment (matches TalkieEnvironment)
    let bundleId = Bundle.main.bundleIdentifier ?? "jdi.talkie.engine"
    let isStaging = bundleId.contains(".staging")
    let isDev = bundleId.contains(".dev")

    // Use same mode detection as TalkieEnvironment for consistency
    log.info("Bundle ID: \(bundleId), isDev: \(isDev), isStaging: \(isStaging)", critical: true)

    if isDev {
        // Dev build (Debug configuration with .dev bundle suffix)
        activeServiceName = EngineServiceMode.dev.rawValue
        activeMode = .dev
        log.info("Running as DEV", detail: "XPC: \(activeServiceName)", critical: true)
    } else if isStaging {
        // Staging build
        activeServiceName = EngineServiceMode.staging.rawValue
        activeMode = .staging
        log.info("Running as STAGING", detail: "XPC: \(activeServiceName)", critical: true)
    } else {
        // Production build
        activeServiceName = EngineServiceMode.production.rawValue
        activeMode = .production
        log.info("Running as PRODUCTION", detail: "XPC: \(activeServiceName)", critical: true)
    }

    // No ensureSingleInstance() - debug and dev can coexist!

    // We're on the main thread here, so @MainActor types can be created
    // Using MainActor.assumeIsolated since we're at global scope but on main thread
    log.info("Initializing on main thread...", critical: true)

    MainActor.assumeIsolated {
        // Create the engine service on the main actor
        engineService = EngineService()
        log.info("EngineService created", critical: true)
    }

    // Create wrapper with the engine service
    serviceWrapper = XPCServiceWrapper(engine: engineService)
    listenerDelegate = EngineListenerDelegate(wrapper: serviceWrapper)

    // Create listener for the Mach service
    log.info("Setting up XPC listener", detail: activeServiceName, critical: true)
    xpcListener = NSXPCListener(machServiceName: activeServiceName)
    xpcListener.delegate = listenerDelegate
    xpcListener.resume()

    log.info("XPC listener resumed, starting app...", critical: true)

    // Configure status manager with launch mode info
    MainActor.assumeIsolated {
        EngineStatusManager.shared.configure(mode: activeMode, serviceName: activeServiceName, isDaemon: isDaemonMode)
    }

    // Now start the app
    MainActor.assumeIsolated {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
    }

    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
