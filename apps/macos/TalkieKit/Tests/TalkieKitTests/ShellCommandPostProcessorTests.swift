import XCTest
@testable import TalkieKit

final class ShellCommandPostProcessorTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
    }

    func testSeedsSampleRulePackAndColonizesBunCommand() {
        let processor = ShellCommandPostProcessor(directoryURL: tempDirectoryURL)

        let result = processor.process("Bun run Native App Build", scope: .terminal)

        XCTAssertEqual(result.text, "bun run native:app:build")
        XCTAssertEqual(
            result.rewrites,
            [
                .init(
                    trigger: "Bun run Native App Build",
                    replacement: "bun run native:app:build",
                    count: 1
                ),
            ]
        )

        let sampleURL = tempDirectoryURL.appending(path: "terminal.trf.toml", directoryHint: .notDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sampleURL.path))
    }

    func testLeavesEmbeddedPhraseUntouched() {
        let processor = ShellCommandPostProcessor(directoryURL: tempDirectoryURL)

        let result = processor.process("we should bun run native app build later", scope: .terminal)

        XCTAssertEqual(result.text, "we should bun run native app build later")
        XCTAssertTrue(result.rewrites.isEmpty)
    }

    func testUsesUserAuthoredRuleFile() throws {
        let store = TalkieRulePackFileStore(directoryURL: tempDirectoryURL)
        let customPack = TalkieRulePack(
            id: "custom-terminal-rules",
            name: "Custom Terminal Rules",
            rules: [
                .init(
                    id: "pnpm-create-script",
                    scope: [.terminal],
                    priority: 200,
                    match: "pnpm create {script...}",
                    emit: "pnpm create {{script}}",
                    transforms: [
                        "script": [
                            .init(op: .lowercase),
                            .init(op: .join, separator: "-"),
                        ]
                    ]
                )
            ]
        )

        try store.save(
            source: store.serialize(customPack),
            at: tempDirectoryURL.appending(path: "custom.trf.toml", directoryHint: .notDirectory)
        )

        let processor = ShellCommandPostProcessor(directoryURL: tempDirectoryURL)
        let result = processor.process("pnpm create Native App Build", scope: .terminal)

        XCTAssertEqual(result.text, "pnpm create native-app-build")
    }

    func testMigratesLegacyJSONRuleFileToTOML() throws {
        let legacyPack = TalkieRulePack.starterPack(id: "legacy-terminal-rules", name: "Legacy Terminal Rules")
        let data = try JSONEncoder().encode(legacyPack)
        try data.write(
            to: tempDirectoryURL.appending(path: "legacy.trf.json", directoryHint: .notDirectory),
            options: .atomic
        )

        let processor = ShellCommandPostProcessor(directoryURL: tempDirectoryURL)
        let result = processor.process("Bun run Native App Build", scope: .terminal)

        XCTAssertEqual(result.text, "bun run native:app:build")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempDirectoryURL
                    .appending(path: "legacy.trf.toml", directoryHint: .notDirectory)
                    .path
            )
        )
    }
}
