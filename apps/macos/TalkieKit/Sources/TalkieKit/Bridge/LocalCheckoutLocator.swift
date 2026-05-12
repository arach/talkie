import Foundation

public enum LocalCheckoutLocator {
    public static func talkieRepositoryRootURL(
        compileTimeFilePath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        if let override = sanitizedPath(environment["TALKIE_REPO_ROOT"]) {
            let repoRoot = URL(fileURLWithPath: override)
            if hasMacOSDirectory(in: repoRoot) {
                return repoRoot
            }
        }

        for candidate in candidateRepositoryRoots(
            compileTimeFilePath: compileTimeFilePath,
            currentDirectoryPath: currentDirectoryPath,
            homeDirectoryURL: homeDirectoryURL
        ) where hasMacOSDirectory(in: candidate) {
            return candidate
        }

        return nil
    }

    public static func talkieMacOSRootURL(
        compileTimeFilePath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        if let override = sanitizedPath(environment["TALKIE_MACOS_ROOT"]) {
            let macOSRoot = URL(fileURLWithPath: override)
            if FileManager.default.fileExists(atPath: macOSRoot.path) {
                return macOSRoot
            }
        }

        guard let repoRoot = talkieRepositoryRootURL(
            compileTimeFilePath: compileTimeFilePath,
            environment: environment,
            currentDirectoryPath: currentDirectoryPath,
            homeDirectoryURL: homeDirectoryURL
        ) else {
            return nil
        }

        return macOSRoot(in: repoRoot)
    }

    public static func talkieServerSourceURL(
        compileTimeFilePath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        if let override = sanitizedPath(environment["TALKIE_SERVER_SOURCE_PATH"]) {
            let sourceURL = URL(fileURLWithPath: override)
            if hasTalkieServerEntryPoint(at: sourceURL) {
                return sourceURL
            }
        }

        guard let macOSRoot = talkieMacOSRootURL(
            compileTimeFilePath: compileTimeFilePath,
            environment: environment,
            currentDirectoryPath: currentDirectoryPath,
            homeDirectoryURL: homeDirectoryURL
        ) else {
            return nil
        }

        let sourceURL = macOSRoot.appendingPathComponent("TalkieServer", isDirectory: true)
        return hasTalkieServerEntryPoint(at: sourceURL) ? sourceURL : nil
    }

    public static func talkieSpeechExecutableURL(
        compileTimeFilePath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        if let override = sanitizedPath(environment["TALKIE_SPEECH_EXECUTABLE_PATH"]) {
            let executableURL = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: executableURL.path) {
                return executableURL
            }
        }

        guard let macOSRoot = talkieMacOSRootURL(
            compileTimeFilePath: compileTimeFilePath,
            environment: environment,
            currentDirectoryPath: currentDirectoryPath,
            homeDirectoryURL: homeDirectoryURL
        ) else {
            return nil
        }

        let executableURL = macOSRoot
            .appendingPathComponent("TalkieSpeech", isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("TalkieSpeech")
        return FileManager.default.isExecutableFile(atPath: executableURL.path) ? executableURL : nil
    }

    private static func candidateRepositoryRoots(
        compileTimeFilePath: String,
        currentDirectoryPath: String,
        homeDirectoryURL: URL
    ) -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        for ancestor in ancestors(of: URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)) {
            appendUnique(ancestor, to: &candidates, seen: &seen)
        }

        if let compileTimeMacOSRoot = compileTimeMacOSRoot(from: compileTimeFilePath) {
            if let remappedMacOSRoot = remapToCurrentHome(
                compileTimeMacOSRoot,
                homeDirectoryURL: homeDirectoryURL
            ) {
                appendUnique(
                    repositoryRoot(containingMacOSRoot: remappedMacOSRoot),
                    to: &candidates,
                    seen: &seen
                )
            }

            let compileTimeRepoRoot = repositoryRoot(containingMacOSRoot: compileTimeMacOSRoot)
            if let repoName = compileTimeRepoRoot.lastPathComponent.nilIfEmpty {
                for workspaceRoot in commonWorkspaceRoots(homeDirectoryURL: homeDirectoryURL) {
                    appendUnique(
                        workspaceRoot.appendingPathComponent(repoName, isDirectory: true),
                        to: &candidates,
                        seen: &seen
                    )
                }
            }

            appendUnique(
                compileTimeRepoRoot,
                to: &candidates,
                seen: &seen
            )
        }

        return candidates
    }

    private static func compileTimeMacOSRoot(from filePath: String) -> URL? {
        var url = URL(fileURLWithPath: filePath)

        while true {
            if url.lastPathComponent == "macOS" ||
                (url.lastPathComponent == "macos" && url.deletingLastPathComponent().lastPathComponent == "apps") {
                return url
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return nil
            }
            url = parent
        }
    }

    private static func repositoryRoot(containingMacOSRoot macOSRoot: URL) -> URL {
        let parent = macOSRoot.deletingLastPathComponent()
        if macOSRoot.lastPathComponent == "macos", parent.lastPathComponent == "apps" {
            return parent.deletingLastPathComponent()
        }
        return parent
    }

    private static func remapToCurrentHome(_ url: URL, homeDirectoryURL: URL) -> URL? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count > 3, components[1] == "Users" else {
            return nil
        }

        let relativePath = components.dropFirst(3).joined(separator: "/")
        guard !relativePath.isEmpty else {
            return nil
        }

        return homeDirectoryURL.appendingPathComponent(relativePath)
    }

    private static func commonWorkspaceRoots(homeDirectoryURL: URL) -> [URL] {
        [
            homeDirectoryURL,
            homeDirectoryURL.appendingPathComponent("dev", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("Developer", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("Code", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("Projects", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("projects", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("src", isDirectory: true),
        ]
    }

    private static func ancestors(of startURL: URL) -> [URL] {
        var urls: [URL] = []
        var currentURL = startURL.standardizedFileURL

        while true {
            urls.append(currentURL)

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path {
                return urls
            }

            currentURL = parentURL
        }
    }

    private static func appendUnique(_ url: URL, to urls: inout [URL], seen: inout Set<String>) {
        let path = url.standardizedFileURL.path
        guard seen.insert(path).inserted else {
            return
        }
        urls.append(url.standardizedFileURL)
    }

    private static func hasMacOSDirectory(in repoRoot: URL) -> Bool {
        macOSRoot(in: repoRoot) != nil
    }

    private static func macOSRoot(in repoRoot: URL) -> URL? {
        let candidates = [
            repoRoot
                .appendingPathComponent("apps", isDirectory: true)
                .appendingPathComponent("macos", isDirectory: true),
            repoRoot.appendingPathComponent("macOS", isDirectory: true)
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func hasTalkieServerEntryPoint(at sourceURL: URL) -> Bool {
        let entryPoint = sourceURL
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent("server.ts")
        return FileManager.default.fileExists(atPath: entryPoint.path)
    }

    private static func sanitizedPath(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
