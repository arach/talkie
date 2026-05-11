//
//  NearbyBridgeAdvertiser.swift
//  TalkieAgent
//
//  Advertises the Mac Bridge on the local network for iPhone discovery.
//

import Foundation
import TalkieKit

final class NearbyBridgeAdvertiser: NSObject, NetServiceDelegate {
    static let shared = NearbyBridgeAdvertiser()

    private let log = Log(.system)
    private let serviceType = "_talkie-bridge._tcp."
    private var service: NetService?
    private var currentPort: Int32?
    private var currentRoute: String?
    private var currentMode: String?

    private override init() {
        super.init()
    }

    func start(port: Int32, route: String, mode: String) {
        if service != nil,
           currentPort == port,
           currentRoute == route,
           currentMode == mode {
            return
        }

        stop()

        let service = NetService(
            domain: "local.",
            type: serviceType,
            name: Self.serviceName,
            port: port
        )
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "v": Data("1".utf8),
            "route": Data(route.utf8),
            "mode": Data(mode.utf8),
            "cap": Data("commandDeck,memoIngest,workflowStatus".utf8),
        ]))
        service.publish()

        self.service = service
        currentPort = port
        currentRoute = route
        currentMode = mode
        log.info("Publishing Nearby Bridge Bonjour service", detail: "type=\(serviceType) port=\(port) route=\(route)")
    }

    func stop() {
        guard let service else { return }
        service.stop()
        self.service = nil
        currentPort = nil
        currentRoute = nil
        currentMode = nil
        log.info("Stopped Nearby Bridge Bonjour service")
    }

    func netServiceDidPublish(_ sender: NetService) {
        log.info("Nearby Bridge Bonjour service published", detail: "name=\(sender.name) type=\(sender.type)")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        log.error("Nearby Bridge Bonjour publish failed: \(errorDict)")
    }

    private static var serviceName: String {
        let candidates = [
            Host.current().localizedName,
            ProcessInfo.processInfo.hostName,
        ]

        for candidate in candidates {
            let trimmed = candidate?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ".local", with: "")
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }

        return "Talkie Mac"
    }
}
