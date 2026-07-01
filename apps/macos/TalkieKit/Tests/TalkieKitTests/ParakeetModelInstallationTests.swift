import XCTest
@testable import TalkieKit

final class ParakeetModelInstallationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParakeetModelInstallationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
    }

    func testMarkerReportsInstalled() throws {
        XCTAssertFalse(
            ParakeetModelInstallation.isInstalled("v3", applicationSupportDirectory: tempDirectory)
        )

        try ParakeetModelInstallation.markDownloaded("v3", applicationSupportDirectory: tempDirectory)

        let status = ParakeetModelInstallation.status(
            for: "v3",
            applicationSupportDirectory: tempDirectory
        )

        XCTAssertTrue(status.markerExists)
        XCTAssertTrue(status.isInstalled)
        XCTAssertEqual(
            ParakeetModelInstallation.installedModelIds(applicationSupportDirectory: tempDirectory),
            ["v3"]
        )
    }

    func testFluidAudioPayloadReportsInstalledWithoutMarker() throws {
        let modelDirectory = ParakeetModelInstallation.fluidAudioModelsBaseURL(
            applicationSupportDirectory: tempDirectory
        )
        .appendingPathComponent("parakeet-tdt-0.6b-v3-coreml", isDirectory: true)

        try writeArtifacts(
            ParakeetModelInstallation.requiredFluidAudioArtifacts(for: "v3"),
            to: modelDirectory
        )

        let status = ParakeetModelInstallation.status(
            for: "v3",
            applicationSupportDirectory: tempDirectory
        )

        XCTAssertFalse(status.markerExists)
        XCTAssertEqual(status.installedFluidAudioDirectoryURL, modelDirectory)
        XCTAssertTrue(status.isInstalled)
    }

    func testLegacyFluidAudioPayloadReportsInstalledWithoutMarker() throws {
        let modelDirectory = ParakeetModelInstallation.fluidAudioModelsBaseURL(
            applicationSupportDirectory: tempDirectory
        )
        .appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)

        try writeArtifacts(
            ParakeetModelInstallation.requiredFluidAudioArtifacts(for: "v3"),
            to: modelDirectory
        )

        let status = ParakeetModelInstallation.status(
            for: "v3",
            applicationSupportDirectory: tempDirectory
        )

        XCTAssertFalse(status.markerExists)
        XCTAssertEqual(status.installedFluidAudioDirectoryURL, modelDirectory)
        XCTAssertTrue(status.isInstalled)
    }

    func testIncompleteFluidAudioPayloadIsNotInstalled() throws {
        let modelDirectory = ParakeetModelInstallation.fluidAudioModelsBaseURL(
            applicationSupportDirectory: tempDirectory
        )
        .appendingPathComponent("parakeet-tdt-0.6b-v3-coreml", isDirectory: true)

        try writeArtifacts(["Encoder.mlmodelc", "parakeet_vocab.json"], to: modelDirectory)

        let status = ParakeetModelInstallation.status(
            for: "v3",
            applicationSupportDirectory: tempDirectory
        )

        XCTAssertNil(status.installedFluidAudioDirectoryURL)
        XCTAssertFalse(status.isInstalled)
    }

    private func writeArtifacts(_ artifactNames: [String], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for artifactName in artifactNames {
            let artifactURL = directory.appendingPathComponent(artifactName)
            if artifactName.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)
            } else {
                try Data("{}".utf8).write(to: artifactURL)
            }
        }
    }
}
