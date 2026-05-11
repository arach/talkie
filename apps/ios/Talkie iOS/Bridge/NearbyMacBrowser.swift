//
//  NearbyMacBrowser.swift
//  Talkie iOS
//
//  Discovers nearby Talkie Mac Bridge instances advertised over Bonjour.
//

import Foundation
import Observation

@MainActor
@Observable
final class NearbyMacBrowser {
    struct NearbyMac: Identifiable, Equatable {
        let id: String
        let name: String
        let hostName: String
        let port: Int
        let route: String?
        let mode: String?
        let capabilities: [String]
        let lastSeenAt: Date

        var connectionHost: String {
            hostName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }

        var routeLabel: String {
            guard let route, !route.isEmpty else {
                return "Local network"
            }
            if route.contains("tailscale") {
                return "Local or Tailscale"
            }
            return "Local network"
        }
    }

    static let shared = NearbyMacBrowser()

    private(set) var macs: [NearbyMac] = []
    private(set) var isBrowsing = false
    private(set) var errorMessage: String?

    private let delegate = NearbyMacBrowserDelegate()

    private init() {}

    func start() {
        guard !isBrowsing else { return }
        isBrowsing = true
        errorMessage = nil
        delegate.start()
    }

    func stop() {
        delegate.stop()
        isBrowsing = false
        macs = []
    }

    fileprivate func didResolve(
        name: String,
        type: String,
        domain: String,
        hostName: String?,
        port: Int,
        txt: [String: String]
    ) {
        guard let hostName, !hostName.isEmpty, port > 0 else { return }

        let id = "\(domain)|\(type)|\(name)"
        let capabilities = txt["cap"]?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        let mac = NearbyMac(
            id: id,
            name: name,
            hostName: hostName,
            port: port,
            route: txt["route"],
            mode: txt["mode"],
            capabilities: capabilities,
            lastSeenAt: .now
        )

        if let index = macs.firstIndex(where: { $0.id == id }) {
            macs[index] = mac
        } else {
            macs.append(mac)
        }

        macs.sort { left, right in
            left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    fileprivate func didRemove(name: String, type: String, domain: String) {
        let id = "\(domain)|\(type)|\(name)"
        macs.removeAll { $0.id == id }
    }

    fileprivate func didFail(_ message: String) {
        errorMessage = message
        isBrowsing = false
    }
}

private final class NearbyMacBrowserDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let serviceType = "_talkie-bridge._tcp."
    private let browser = NetServiceBrowser()
    private var resolvingServices: [String: NetService] = [:]

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: serviceType, inDomain: "local.")
    }

    func stop() {
        browser.stop()
        for service in resolvingServices.values {
            service.stop()
        }
        resolvingServices.removeAll()
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        let key = serviceKey(service)
        resolvingServices[key] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let name = service.name
        let type = service.type
        let domain = service.domain
        resolvingServices.removeValue(forKey: serviceKey(service))

        Task { @MainActor in
            NearbyMacBrowser.shared.didRemove(name: name, type: type, domain: domain)
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        Task { @MainActor in
            NearbyMacBrowser.shared.didFail("Local network search failed")
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = serviceKey(sender)
        resolvingServices.removeValue(forKey: key)

        let name = sender.name
        let type = sender.type
        let domain = sender.domain
        let hostName = sender.hostName
        let port = sender.port
        let txt = Self.decodeTXT(sender.txtRecordData())

        Task { @MainActor in
            NearbyMacBrowser.shared.didResolve(
                name: name,
                type: type,
                domain: domain,
                hostName: hostName,
                port: port,
                txt: txt
            )
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolvingServices.removeValue(forKey: serviceKey(sender))
    }

    private func serviceKey(_ service: NetService) -> String {
        "\(service.domain)|\(service.type)|\(service.name)"
    }

    private static func decodeTXT(_ data: Data?) -> [String: String] {
        guard let data else { return [:] }
        let raw = NetService.dictionary(fromTXTRecord: data)
        var decoded: [String: String] = [:]
        for (key, value) in raw {
            decoded[key] = String(data: value, encoding: .utf8)
        }
        return decoded
    }
}
