import Foundation

public struct ParakeetModelInstallationStatus: Equatable, Sendable {
    public let modelId: String
    public let talkieModelDirectoryURL: URL
    public let markerURL: URL
    public let markerExists: Bool
    public let talkieModelDirectoryExists: Bool
    public let fluidAudioCandidateDirectoryURLs: [URL]
    public let installedFluidAudioDirectoryURL: URL?

    public var hasFluidAudioArtifacts: Bool {
        installedFluidAudioDirectoryURL != nil
    }

    public var isInstalled: Bool {
        markerExists || hasFluidAudioArtifacts
    }
}

public enum ParakeetModelInstallation {
    public static let knownModelIds = ["v2", "v3"]

    public static func status(
        for modelId: String,
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) -> ParakeetModelInstallationStatus {
        let supportDirectory = applicationSupportDirectory ?? defaultApplicationSupportDirectory(fileManager: fileManager)
        let talkieModelDirectory = talkieModelsBaseURL(applicationSupportDirectory: supportDirectory)
            .appendingPathComponent(modelId, isDirectory: true)
        let markerURL = talkieModelDirectory.appendingPathComponent(".marker")
        let fluidAudioCandidates = fluidAudioCandidateDirectoryURLs(
            for: modelId,
            applicationSupportDirectory: supportDirectory
        )

        var isDirectory: ObjCBool = false
        let talkieModelDirectoryExists = fileManager.fileExists(
            atPath: talkieModelDirectory.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue

        let installedFluidAudioDirectory = fluidAudioCandidates.first { candidate in
            hasRequiredFluidAudioArtifacts(for: modelId, at: candidate, fileManager: fileManager)
        }

        return ParakeetModelInstallationStatus(
            modelId: modelId,
            talkieModelDirectoryURL: talkieModelDirectory,
            markerURL: markerURL,
            markerExists: fileManager.fileExists(atPath: markerURL.path),
            talkieModelDirectoryExists: talkieModelDirectoryExists,
            fluidAudioCandidateDirectoryURLs: fluidAudioCandidates,
            installedFluidAudioDirectoryURL: installedFluidAudioDirectory
        )
    }

    public static func isInstalled(
        _ modelId: String,
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) -> Bool {
        status(
            for: modelId,
            fileManager: fileManager,
            applicationSupportDirectory: applicationSupportDirectory
        ).isInstalled
    }

    public static func installedModelIds(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) -> Set<String> {
        Set(knownModelIds.filter {
            isInstalled($0, fileManager: fileManager, applicationSupportDirectory: applicationSupportDirectory)
        })
    }

    public static func markDownloaded(
        _ modelId: String,
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) throws {
        let supportDirectory = applicationSupportDirectory ?? defaultApplicationSupportDirectory(fileManager: fileManager)
        let modelDirectory = talkieModelsBaseURL(applicationSupportDirectory: supportDirectory)
            .appendingPathComponent(modelId, isDirectory: true)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try "downloaded".write(
            to: modelDirectory.appendingPathComponent(".marker"),
            atomically: true,
            encoding: .utf8
        )
    }

    public static func removeTalkieMarkerDirectory(
        _ modelId: String,
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) throws {
        let supportDirectory = applicationSupportDirectory ?? defaultApplicationSupportDirectory(fileManager: fileManager)
        let modelDirectory = talkieModelsBaseURL(applicationSupportDirectory: supportDirectory)
            .appendingPathComponent(modelId, isDirectory: true)
        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.removeItem(at: modelDirectory)
        }
    }

    public static func talkieModelsBaseURL(applicationSupportDirectory: URL? = nil) -> URL {
        (applicationSupportDirectory ?? defaultApplicationSupportDirectory())
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("ParakeetModels", isDirectory: true)
    }

    public static func fluidAudioModelsBaseURL(applicationSupportDirectory: URL? = nil) -> URL {
        (applicationSupportDirectory ?? defaultApplicationSupportDirectory())
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    public static func fluidAudioCandidateDirectoryURLs(
        for modelId: String,
        applicationSupportDirectory: URL? = nil
    ) -> [URL] {
        let baseURL = fluidAudioModelsBaseURL(applicationSupportDirectory: applicationSupportDirectory)
        return fluidAudioDirectoryNames(for: modelId).map {
            baseURL.appendingPathComponent($0, isDirectory: true)
        }
    }

    public static func requiredFluidAudioArtifacts(for modelId: String) -> [String] {
        switch modelId {
        case "v3":
            return [
                "Preprocessor.mlmodelc",
                "Encoder.mlmodelc",
                "Decoder.mlmodelc",
                "JointDecisionv3.mlmodelc",
                "parakeet_vocab.json"
            ]
        default:
            return [
                "Preprocessor.mlmodelc",
                "Encoder.mlmodelc",
                "Decoder.mlmodelc",
                "JointDecision.mlmodelc",
                "parakeet_vocab.json"
            ]
        }
    }

    private static func defaultApplicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        if let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return supportDirectory
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    private static func fluidAudioDirectoryNames(for modelId: String) -> [String] {
        switch modelId {
        case "v2":
            return ["parakeet-tdt-0.6b-v2-coreml", "parakeet-tdt-0.6b-v2"]
        case "v3":
            return ["parakeet-tdt-0.6b-v3-coreml", "parakeet-tdt-0.6b-v3"]
        default:
            return []
        }
    }

    private static func hasRequiredFluidAudioArtifacts(
        for modelId: String,
        at directory: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        return requiredFluidAudioArtifacts(for: modelId).allSatisfy { artifactName in
            fileManager.fileExists(atPath: directory.appendingPathComponent(artifactName).path)
        }
    }
}
