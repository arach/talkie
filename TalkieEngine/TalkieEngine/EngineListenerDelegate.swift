//
//  EngineListenerDelegate.swift
//  TalkieEngine
//
//  XPC listener delegate for handling incoming connections
//

import Foundation
import os

private let logger = Logger(subsystem: "live.talkie.engine", category: "ListenerDelegate")

class EngineListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let serviceWrapper: XPCServiceWrapper

    init(wrapper: XPCServiceWrapper) {
        self.serviceWrapper = wrapper
        super.init()
        logger.info("EngineListenerDelegate initialized with wrapper")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        logger.info("New XPC connection from PID \(pid)")

        newConnection.exportedInterface = NSXPCInterface(with: TalkieEngineProtocol.self)
        newConnection.exportedObject = serviceWrapper

        newConnection.invalidationHandler = {
            logger.info("XPC connection invalidated")
        }

        newConnection.interruptionHandler = {
            logger.warning("XPC connection interrupted")
        }

        newConnection.resume()
        return true
    }
}
