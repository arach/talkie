import Foundation
import XCTest
@testable import TalkieKit

final class ExecutableResolverTests: XCTestCase {
    func testEnrichedPATHDirectoriesKeepsOnlyActiveFNMMultishellPath() throws {
        let fileManager = FileManager.default
        let homeURL = fileManager.temporaryDirectory
            .appending(path: "ExecutableResolverTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: homeURL) }

        let activeMultishellRoot = homeURL
            .appending(path: ".local/state/fnm_multishells/current-shell", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: activeMultishellRoot.appending(path: "bin", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let staleMultishellRoot = homeURL
            .appending(path: ".local/state/fnm_multishells/stale-shell", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: staleMultishellRoot.appending(path: "bin", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let aliasBinURL = homeURL
            .appending(path: ".local/share/fnm/aliases/default/bin", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: aliasBinURL, withIntermediateDirectories: true)

        let nodeVersionBinURL = homeURL
            .appending(path: ".local/share/fnm/node-versions/v22.21.1/installation/bin", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: nodeVersionBinURL, withIntermediateDirectories: true)

        let directories = ExecutableResolver.enrichedPATHDirectories(
            environment: ["FNM_MULTISHELL_PATH": activeMultishellRoot.path],
            homeDirectory: homeURL.path
        )

        XCTAssertTrue(directories.contains(activeMultishellRoot.appending(path: "bin").path))
        XCTAssertTrue(directories.contains(aliasBinURL.path))
        XCTAssertTrue(directories.contains(nodeVersionBinURL.path))
        XCTAssertFalse(directories.contains(staleMultishellRoot.appending(path: "bin").path))
    }
}
