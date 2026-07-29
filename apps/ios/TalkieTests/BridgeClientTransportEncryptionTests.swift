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

    func testHTTPAcceptedIsSuccessfulForAsyncBridgeRoutes() {
        XCTAssertTrue(BridgeClient.accepts(statusCode: 200))
        XCTAssertTrue(BridgeClient.accepts(statusCode: 202))
        XCTAssertTrue(BridgeClient.accepts(statusCode: 299))
    }

    func testNon2xxStatusesRemainErrors() {
        XCTAssertFalse(BridgeClient.accepts(statusCode: 199))
        XCTAssertFalse(BridgeClient.accepts(statusCode: 300))
        XCTAssertFalse(BridgeClient.accepts(statusCode: 401))
        XCTAssertFalse(BridgeClient.accepts(statusCode: 500))
    }
}
