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

    // Ask the existing service to shut down gracefully via XPC
    // This will wait for any in-progress work to complete (up to 2 min)
    requestGracefulShutdown()

    // Wait for all existing processes to exit
    waitForProcessesToExit(pids: existingPIDs, timeout: 130) // 2 min + 10s buffer
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
func requestGracefulShutdown() {
    logger.info("Requesting graceful shutdown of existing instance...")

    let connection = NSXPCConnection(machServiceName: kTalkieEngineServiceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: TalkieEngineProtocol.self)
    connection.resume()

    let semaphore = DispatchSemaphore(value: 0)
    var shutdownAccepted = false

    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        logger.warning("XPC error requesting shutdown: \(error.localizedDescription)")
        semaphore.signal()
    } as? TalkieEngineProtocol

    // Ask to shut down, wait for completion of any in-progress work
    proxy?.requestShutdown(waitForCompletion: true) { accepted in
        shutdownAccepted = accepted
        logger.info("Shutdown request \(accepted ? "accepted" : "rejected")")
        semaphore.signal()
    }

    // Wait for the shutdown request to complete (2 min grace + buffer)
    let result = semaphore.wait(timeout: .now() + 130)

    if result == .timedOut {
        logger.warning("Shutdown request timed out")
    } else if shutdownAccepted {
        logger.info("Existing instance accepted shutdown request")
    }

    connection.invalidate()
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

// MARK: - Main Entry Point

logger.info("TalkieEngine starting (PID: \(ProcessInfo.processInfo.processIdentifier))...")

// Ensure we're the only instance - new one wins, old one gracefully exits
ensureSingleInstance()

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
logger.info("TalkieEngine: Setting up XPC listener for \(kTalkieEngineServiceName)")
xpcListener = NSXPCListener(machServiceName: kTalkieEngineServiceName)
xpcListener.delegate = listenerDelegate
xpcListener.resume()

logger.info("TalkieEngine: XPC listener resumed, starting app...")

// Now start the app
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
