import Foundation

/// Rewrites natural-language shell command utterances into executable forms.
///
/// Rules are loaded from user-authored rule packs in `~/Documents/Talkie/Rules`.
/// The runtime seeds a sample `bun run {script...}` rule pack on first use.
public final class ShellCommandPostProcessor {
    public struct Rewrite: Equatable, Sendable {
        public let trigger: String
        public let replacement: String
        public let count: Int

        public init(trigger: String, replacement: String, count: Int) {
            self.trigger = trigger
            self.replacement = replacement
            self.count = count
        }
    }

    public static let shared = ShellCommandPostProcessor()

    public static var defaultRulesDirectoryURL: URL {
        TalkieRulePackFileStore.defaultDirectoryURL
    }

    private let directoryURL: URL
    private let fileStore: TalkieRulePackFileStore
    private let executor: TalkieRuleExecutor
    private var cachedFingerprint: [FileFingerprint] = []
    private var cachedPacks: [TalkieRulePack] = []

    public init(
        directoryURL: URL = ShellCommandPostProcessor.defaultRulesDirectoryURL,
        executor: TalkieRuleExecutor = .shared
    ) {
        self.directoryURL = directoryURL
        self.fileStore = TalkieRulePackFileStore(directoryURL: directoryURL)
        self.executor = executor
    }

    public func process(
        _ text: String,
        scope: TalkieRulePack.Scope = .natural
    ) -> (text: String, rewrites: [Rewrite]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (text, [])
        }

        let packs = loadRulePacks()
        guard let match = executor.rewrite(trimmed, scope: scope, packs: packs),
              match.output != trimmed else {
            return (text, [])
        }

        return (
            match.output,
            [
                Rewrite(
                    trigger: trimmed,
                    replacement: match.output,
                    count: 1
                ),
            ]
        )
    }

    private struct FileFingerprint: Equatable {
        let path: String
        let modifiedAt: Date
        let size: Int64
    }

    private func loadRulePacks() -> [TalkieRulePack] {
        _ = try? fileStore.seedSamplePackIfNeeded()

        let fingerprint = currentFingerprint()
        if fingerprint == cachedFingerprint {
            return cachedPacks
        }

        let packs = fileStore.loadPacks()

        cachedFingerprint = fingerprint
        cachedPacks = packs
        return packs
    }

    private func ruleFileURLs() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.lastPathComponent.hasSuffix(".trf.toml") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func currentFingerprint() -> [FileFingerprint] {
        ruleFileURLs().map { fileURL in
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return FileFingerprint(
                path: fileURL.path,
                modifiedAt: values?.contentModificationDate ?? .distantPast,
                size: Int64(values?.fileSize ?? 0)
            )
        }
    }
}
