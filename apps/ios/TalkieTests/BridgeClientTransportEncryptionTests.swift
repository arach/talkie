//
//  BridgeClientTransportEncryptionTests.swift
//  TalkieTests
//

import XCTest
@testable import Talkie_iOS

final class BridgeClientTransportEncryptionTests: XCTestCase {
    func testPairingBootstrapRemainsPlaintext() {
        XCTAssertFalse(BridgeClient.supportsTransportEncryption(for: "/pair"))
    }

    func testAuthenticatedRoutesUseTransportEncryption() {
        XCTAssertTrue(BridgeClient.supportsTransportEncryption(for: "/sessions"))
        XCTAssertTrue(BridgeClient.supportsTransportEncryption(for: "/companion/state"))
    }
}
