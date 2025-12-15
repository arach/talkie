//
//  main.swift
//  TalkieEngine
//
//  Entry point that sets up XPC listener before NSApplication
//

import Cocoa
import os
import Darwin

private let logger = Logger(subsystem: "jdi.talkie.engine", category: "Main")

// MARK: - Single Instance Enforcement (Honor System)

/// Find and handle any existing TalkieEngine processes
/// New instance always wins - asks old one to shut down gracefully
func ensureSingleInstance() {
    let myPID = ProcessInfo.processInfo.processIdentifier
    let existingPIDs = findExistingEngineProcesses(excludingPID: myPID)

    guard !existingPIDs.isEmpty else {
        logger.info("No existing TalkieEngine processes found")
        return
    }

    logger.info("Found \(existingPIDs.count) existing TalkieEngine process(es): \(existingPIDs)")

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
        logger.info("Existing process is likely production build - debug and production can coexist")
        #else
        logger.info("Existing process is likely debug build - debug and production can coexist")
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
    logger.info("Requesting graceful shutdown of existing instance via \(kTalkieEngineServiceName)...")

    let connection = NSXPCConnection(machServiceName: kTalkieEngineServiceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: TalkieEngineProtocol.self)
    connection.resume()

    let semaphore = DispatchSemaphore(value: 0)
    var shutdownAccepted = false
    var xpcFailed = false

    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        // XPC error means we can't communicate - likely different namespace (debug vs prod)
        logger.info("XPC connection failed (likely different namespace): \(error.localizedDescription)")
        xpcFailed = true
        semaphore.signal()
    } as? TalkieEngineProtocol

    // Ask to shut down, wait for completion of any in-progress work
    proxy?.requestShutdown(waitForCompletion: true) { accepted in
        shutdownAccepted = accepted
        logger.info("Shutdown request \(accepted ? "accepted" : "rejected")")
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
            logger.info("All existing TalkieEngine processes have exited")
            return
        }

        // Still running, wait a bit
        Thread.sleep(forTimeInterval: 0.5)
    }

    // Timeout - force kill any remaining
    logger.warning("Timeout waiting for graceful shutdown, forcing termination")
    for pid in pids {
        if kill(pid, 0) == 0 {
            logger.warning("Force killing PID \(pid)")
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

logger.info("TalkieEngine starting (PID: \(ProcessInfo.processInfo.processIdentifier), mode: \(isDaemonMode ? "daemon" : "debug"))...")

// Determine XPC service name based on launch mode
// Debug and Dev can run side-by-side on different XPC services
let activeServiceName: String
let activeMode: EngineServiceMode

#if DEBUG
if isDaemonMode {
    // Daemon mode: use dev XPC (always running in background)
    activeServiceName = EngineServiceMode.dev.rawValue
    activeMode = .dev
    logger.info("Running as DEV daemon → \(activeServiceName)")
} else {
    // Xcode mode: use debug XPC (active development)
    activeServiceName = EngineServiceMode.debug.rawValue
    activeMode = .debug
    logger.info("Running as DEBUG from Xcode → \(activeServiceName)")
}
#else
// Production build - always use production XPC
activeServiceName = EngineServiceMode.production.rawValue
activeMode = .production
logger.info("Running as PROD → \(activeServiceName)")
#endif

// No ensureSingleInstance() - debug and dev can coexist!

// Global references to prevent deallocation
var xpcListener: NSXPCListener!
var engineService: EngineService!
var serviceWrapper: XPCServiceWrapper!
var listenerDelegate: EngineListenerDelegate!

// We're on the main thread here, so @MainActor types can be created
// Using MainActor.assumeIsolated since we're at global scope but on main thread
logger.info("TalkieEngine: Initializing on main thread...")

MainActor.assumeIsolated {
    // Create the engine service on the main actor
    engineService = EngineService()
    logger.info("TalkieEngine: EngineService created")
}

// Create wrapper with the engine service
serviceWrapper = XPCServiceWrapper(engine: engineService)
listenerDelegate = EngineListenerDelegate(wrapper: serviceWrapper)

// Create listener for the Mach service
logger.info("TalkieEngine: Setting up XPC listener for \(activeServiceName)")
xpcListener = NSXPCListener(machServiceName: activeServiceName)
xpcListener.delegate = listenerDelegate
xpcListener.resume()

logger.info("TalkieEngine: XPC listener resumed, starting app...")

// Configure status manager with launch mode info
MainActor.assumeIsolated {
    EngineStatusManager.shared.configure(mode: activeMode, serviceName: activeServiceName)
}

// Now start the app
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
}
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
