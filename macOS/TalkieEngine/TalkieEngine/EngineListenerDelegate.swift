//
//  EngineListenerDelegate.swift
//  TalkieEngine
//
//  XPC listener delegate for handling incoming connections
//

import Foundation
import Darwin
import TalkieKit

class EngineListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let serviceWrapper: XPCServiceWrapper
    private var activeConnections = 0

    init(wrapper: XPCServiceWrapper) {
        self.serviceWrapper = wrapper
        super.init()
        AppLogger.shared.info(.xpc, "EngineListenerDelegate initialized with wrapper")
        Task { @MainActor in
            EngineStatusManager.shared.log(.info, "XPC", "Listener delegate ready")
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        activeConnections += 1
        AppLogger.shared.info(.xpc, "New XPC connection from PID \(pid)")

        // Try to get the client app name
        let clientName = getProcessName(pid: pid)

        Task { @MainActor in
            EngineStatusManager.shared.log(.info, "XPC", "Client connected: \(clientName) (PID \(pid))")
        }

        newConnection.exportedInterface = NSXPCInterface(with: TalkieEngineProtocol.self)
        newConnection.exportedObject = serviceWrapper

        newConnection.invalidationHandler = { [weak self] in
            AppLogger.shared.info(.xpc, "XPC connection invalidated")
            self?.activeConnections -= 1
            Task { @MainActor in
                EngineStatusManager.shared.log(.debug, "XPC", "Client disconnected: \(clientName) (PID \(pid))")
            }
        }

        newConnection.interruptionHandler = {
            AppLogger.shared.warning(.xpc, "XPC connection interrupted")
            Task { @MainActor in
                EngineStatusManager.shared.log(.warning, "XPC", "Connection interrupted: \(clientName) (PID \(pid))")
            }
        }

        newConnection.resume()
        return true
    }

    private func getProcessName(pid: Int32) -> String {
        // Try to get the process name from the PID
        var name = [CChar](repeating: 0, count: 1024)
        let result = proc_name(pid, &name, UInt32(name.count))
        if result > 0 {
            return String(cString: name)
        }
        return "Unknown"
    }
}
