//
//  WatchReadyHapticConfigurationTests.swift
//  TalkieTests
//
//  A config written before `watchReadyHapticEnabled` existed must keep the rest
//  of the user's voice settings. Synthesized `Codable` does not apply property
//  defaults for missing keys, so this section decodes by hand and that hand
//  work is what these tests pin down.
//

import XCTest
@testable import Talkie_iOS

final class WatchReadyHapticConfigurationTests: XCTestCase {
    func testLegacyConfigurationKeepsVoiceSettingsAndDefaultsHapticOn() throws {
        let tts = try JSONDecoder().decode(
            TalkieAppConfiguration.TTS.self,
            from: Data(legacyTTSJSON.utf8)
        )

        XCTAssertEqual(tts.provider, "elevenlabs")
        XCTAssertEqual(tts.voice, "rachel")
        XCTAssertEqual(tts.aiVoiceOutputRoute, "watch")
        XCTAssertTrue(tts.watchReadyHapticEnabled)
    }

    func testStoredHapticPreferenceSurvivesRoundTrip() throws {
        var tts = TalkieAppConfiguration.TTS()
        tts.watchReadyHapticEnabled = false

        let decoded = try JSONDecoder().decode(
            TalkieAppConfiguration.TTS.self,
            from: try JSONEncoder().encode(tts)
        )

        XCTAssertFalse(decoded.watchReadyHapticEnabled)
    }

    private let legacyTTSJSON = """
    {
      "mode": "direct",
      "provider": "elevenlabs",
      "voice": "rachel",
      "apiKey": "",
      "aiVoiceOutputRoute": "watch"
    }
    """
}
