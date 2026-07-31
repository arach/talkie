//
//  TalkieGatewayPortMigrationTests.swift
//  TalkieTests
//

import XCTest
@testable import Talkie_iOS

final class TalkieGatewayPortMigrationTests: XCTestCase {
    func testMigratesExistingTalkieGatewayPairing() throws {
        let bridge = try JSONDecoder().decode(
            TalkieAppConfiguration.Bridge.self,
            from: Data(bridgeJSON(port: TalkieNetworkPorts.legacyGateway).utf8)
        )

        XCTAssertEqual(bridge.pairedMacs.first?.port, TalkieNetworkPorts.gateway)
    }

    func testPreservesCustomPairingPort() throws {
        let bridge = try JSONDecoder().decode(
            TalkieAppConfiguration.Bridge.self,
            from: Data(bridgeJSON(port: 20_100).utf8)
        )

        XCTAssertEqual(bridge.pairedMacs.first?.port, 20_100)
    }

    private func bridgeJSON(port: Int) -> String {
        """
        {
          "deviceId": "phone-1",
          "activePairedMacID": "mac-1",
          "pairedMacs": [
            {
              "id": "mac-1",
              "hostname": "talkie-mac.local",
              "port": \(port),
              "pairedMacName": "Talkie Mac",
              "serverPublicKey": "public-key",
              "privateKey": "private-key",
              "lastSuccessfulContactAt": 0,
              "lastSelectedAt": 0
            }
          ]
        }
        """
    }
}
