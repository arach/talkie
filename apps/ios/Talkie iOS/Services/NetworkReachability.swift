//
//  NetworkReachability.swift
//  Talkie iOS
//
//  Shared Network.framework reachability observer for Next surfaces.
//

import Foundation
import Network

@MainActor
final class NetworkReachability: ObservableObject {
    enum Status: Equatable {
        case offline
        case online
    }

    static let shared = NetworkReachability()

    @Published private(set) var status: Status = .online

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "to.talkie.network-reachability", qos: .utility)
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            let nextStatus: Status = path.status == .satisfied ? .online : .offline
            Task { @MainActor [weak self] in
                self?.status = nextStatus
            }
        }
        monitor.start(queue: queue)
    }
}
