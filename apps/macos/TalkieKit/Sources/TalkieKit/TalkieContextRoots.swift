import Foundation

public enum TalkieContextRoots {
    public static func defaultRoots(workspacePath: String? = nil) -> [TalkieContextRoot] {
        var roots: [TalkieContextRoot] = []

        if let workspacePath, !workspacePath.isEmpty {
            let workspaceRootURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
                .appending(path: ".talkie", directoryHint: .isDirectory)
            roots.append(TalkieContextRoot(kind: .workspace, url: workspaceRootURL))
        }

        let globalRootURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".talkie", directoryHint: .isDirectory)
        roots.append(TalkieContextRoot(kind: .global, url: globalRootURL))

        if let builtInRootURL {
            roots.append(TalkieContextRoot(kind: .builtIn, url: builtInRootURL))
        }

        return roots
    }

    public static var builtInRootURL: URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let rootURL = resourceURL.appending(path: "Context", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: rootURL.path(percentEncoded: false)) else {
            return nil
        }
        return rootURL
    }
}
