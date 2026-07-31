import Foundation
import XCTest
@testable import TalkieKit

final class TalkieNetworkEndpointsTests: XCTestCase {
    func testGatewayEndpointUsesOwnedPortAndEscapesPathComponents() {
        let url = TalkieNetworkEndpoints.gateway(
            path: "/sessions/task with spaces/messages",
            queryItems: [URLQueryItem(name: "limit", value: "100")]
        )

        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, TalkieNetworkPorts.gateway)
        XCTAssertEqual(url.path, "/sessions/task with spaces/messages")
        XCTAssertEqual(url.query, "limit=100")
    }

    func testGatewayPortDoesNotCollideWithMicrophoneHelper() {
        XCTAssertEqual(TalkieNetworkPorts.gateway, 19_825)
        XCTAssertNotEqual(TalkieNetworkPorts.gateway, TalkieNetworkPorts.microphone)
    }
}
