/// Stable ports the iPhone needs to recognize across gateway migrations.
enum TalkieNetworkPorts {
    static let gateway = 19_825
    static let legacyGateway = 8_765

    static func migratedGatewayPort(_ port: Int) -> Int {
        port == legacyGateway ? gateway : port
    }
}
