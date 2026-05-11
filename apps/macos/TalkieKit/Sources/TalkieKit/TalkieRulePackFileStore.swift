import Foundation

public struct TalkieRulePackFileStore: Sendable {
    public struct Document: Identifiable, Equatable, Sendable {
        public let url: URL
        public let source: String
        public let pack: TalkieRulePack?
        public let errorDescription: String?

        public var id: String { url.path }

        public init(
            url: URL,
            source: String,
            pack: TalkieRulePack?,
            errorDescription: String? = nil
        ) {
            self.url = url
            self.source = source
            self.pack = pack
            self.errorDescription = errorDescription
        }
    }

    public static var defaultDirectoryURL: URL {
        URL.documentsDirectory
            .appending(path: "Talkie", directoryHint: .isDirectory)
            .appending(path: "Rules", directoryHint: .isDirectory)
    }

    public let directoryURL: URL

    public init(directoryURL: URL = Self.defaultDirectoryURL) {
        self.directoryURL = directoryURL
    }

    public func ensureRulesDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    public func seedSamplePackIfNeeded() throws -> URL? {
        try ensureRulesDirectoryExists()
        try migrateLegacyJSONIfNeeded()

        guard ruleFileURLs().isEmpty else { return nil }

        let sampleURL = directoryURL.appending(path: "terminal.trf.toml", directoryHint: .notDirectory)
        try save(
            source: TalkieRulePackTOML.encode(.starterPack()),
            at: sampleURL
        )
        return sampleURL
    }

    public func loadDocuments() -> [Document] {
        _ = try? seedSamplePackIfNeeded()

        return ruleFileURLs().map { fileURL in
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return Document(
                    url: fileURL,
                    source: "",
                    pack: nil,
                    errorDescription: "Failed to read file."
                )
            }

            do {
                let pack = try TalkieRulePackTOML.decode(source)
                return Document(url: fileURL, source: source, pack: pack)
            } catch {
                return Document(
                    url: fileURL,
                    source: source,
                    pack: nil,
                    errorDescription: error.localizedDescription
                )
            }
        }
    }

    public func loadPacks() -> [TalkieRulePack] {
        loadDocuments().compactMap(\.pack)
    }

    public func parse(_ source: String) throws -> TalkieRulePack {
        try TalkieRulePackTOML.decode(source)
    }

    public func serialize(_ pack: TalkieRulePack) -> String {
        TalkieRulePackTOML.encode(pack)
    }

    public func save(source: String, at url: URL) throws {
        try ensureRulesDirectoryExists()
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    public func createPack(named preferredStem: String) throws -> Document {
        try ensureRulesDirectoryExists()

        let fileStem = uniqueFileStem(from: preferredStem)
        let title = fileStem
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
        let pack = TalkieRulePack.starterPack(id: fileStem, name: title)
        let url = directoryURL.appending(path: "\(fileStem).trf.toml", directoryHint: .notDirectory)
        let source = serialize(pack)
        try save(source: source, at: url)
        return Document(url: url, source: source, pack: pack)
    }

    private func uniqueFileStem(from preferredStem: String) -> String {
        let baseStem = slugify(preferredStem.isEmpty ? "rule-pack" : preferredStem)
        var candidate = baseStem
        var suffix = 2

        while FileManager.default.fileExists(
            atPath: directoryURL
                .appending(path: "\(candidate).trf.toml", directoryHint: .notDirectory)
                .path
        ) {
            candidate = "\(baseStem)-\(suffix)"
            suffix += 1
        }

        return candidate
    }

    private func slugify(_ value: String) -> String {
        let lowercase = value.lowercased()
        let allowed = CharacterSet.alphanumerics
        var result = ""
        var lastWasSeparator = false

        for scalar in lowercase.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "rule-pack" : trimmed
    }

    private func migrateLegacyJSONIfNeeded() throws {
        let legacyURLs = legacyRuleFileURLs()
        guard ruleFileURLs().isEmpty, !legacyURLs.isEmpty else { return }

        let decoder = JSONDecoder()
        for legacyURL in legacyURLs {
            let data = try Data(contentsOf: legacyURL)
            let pack = try decoder.decode(TalkieRulePack.self, from: data)
            let stem = legacyURL.deletingPathExtension().deletingPathExtension().lastPathComponent
            let destinationURL = directoryURL.appending(path: "\(stem).trf.toml", directoryHint: .notDirectory)
            try save(source: serialize(pack), at: destinationURL)
        }
    }

    private func ruleFileURLs() -> [URL] {
        directoryContents()
            .filter { $0.lastPathComponent.hasSuffix(".trf.toml") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func legacyRuleFileURLs() -> [URL] {
        directoryContents()
            .filter { $0.lastPathComponent.hasSuffix(".trf.json") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func directoryContents() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}
