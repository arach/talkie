//
//  main.swift
//  TalkieEngine
//
//  Entry point that sets up XPC listener before NSApplication
//

import Cocoa
import os

private let logger = Logger(subsystem: "live.talkie.engine", category: "Main")

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
