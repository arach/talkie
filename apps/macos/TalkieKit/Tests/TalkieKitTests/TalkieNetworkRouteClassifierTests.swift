import XCTest
@testable import TalkieKit

final class TalkieNetworkRouteClassifierTests: XCTestCase {
    func testTailscaleIPv4RangeIsCgnatRangeOnly() {
        XCTAssertFalse(TalkieNetworkRouteClassifier.isTailscaleIPv4Address("100.63.255.255"))
        XCTAssertTrue(TalkieNetworkRouteClassifier.isTailscaleIPv4Address("100.64.0.1"))
        XCTAssertTrue(TalkieNetworkRouteClassifier.isTailscaleIPv4Address("100.127.255.254"))
        XCTAssertFalse(TalkieNetworkRouteClassifier.isTailscaleIPv4Address("100.128.0.1"))
    }

    func testTailscaleHostnameUsesSuffix() {
        XCTAssertTrue(TalkieNetworkRouteClassifier.isTailscaleHost("arachs-mac.tail123.ts.net"))
        XCTAssertTrue(TalkieNetworkRouteClassifier.isTailscaleHost("arach@arachs-mac.tail123.ts.net:22"))
        XCTAssertFalse(TalkieNetworkRouteClassifier.isTailscaleHost("arachs-mac.ts.net.example.com"))
    }

    func testRouteClassifiesLocalHosts() {
        XCTAssertEqual(TalkieNetworkRouteClassifier.route(for: "forge.local"), .localNetwork)
        XCTAssertEqual(TalkieNetworkRouteClassifier.route(for: "http://forge.local:8765/status"), .localNetwork)
        XCTAssertEqual(TalkieNetworkRouteClassifier.route(for: "192.168.1.44"), .localNetwork)
        XCTAssertEqual(TalkieNetworkRouteClassifier.route(for: "172.16.0.2"), .localNetwork)
        XCTAssertEqual(TalkieNetworkRouteClassifier.route(for: "10.0.0.12"), .localNetwork)
        XCTAssertEqual(TalkieNetworkRouteClassifier.route(for: "100.64.0.12"), .tailscale)
        XCTAssertEqual(TalkieNetworkRouteClassifier.route(for: "100.64.0.12:22"), .tailscale)
    }

    func testBonjourHostnameOnlyAcceptsLocalishNames() {
        XCTAssertEqual(TalkieNetworkRouteClassifier.localBonjourHostname(from: "Forge"), "forge.local")
        XCTAssertEqual(TalkieNetworkRouteClassifier.localBonjourHostname(from: "forge.local."), "forge.local")
        XCTAssertNil(TalkieNetworkRouteClassifier.localBonjourHostname(from: "forge.tail123.ts.net"))
        XCTAssertNil(TalkieNetworkRouteClassifier.localBonjourHostname(from: "192.168.1.44"))
    }

    func testNetworkIdentityNormalizesKnownLocalSuffixes() {
        XCTAssertEqual(TalkieNetworkRouteClassifier.networkIdentity(from: "Forge.local"), "forge")
        XCTAssertEqual(TalkieNetworkRouteClassifier.networkIdentity(from: "Forge.tail123.ts.net"), "forge")
        XCTAssertEqual(TalkieNetworkRouteClassifier.networkIdentity(from: "Forge LAN"), "forgelan")
    }
}
