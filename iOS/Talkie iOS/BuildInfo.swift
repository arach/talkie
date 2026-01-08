//
//  BuildInfo.swift
//  Talkie iOS
//
//  Runtime git info - works in simulator, shows "device" on physical device
//

import Foundation

enum BuildInfo {
    /// Get current git branch (simulator only, returns "device" on physical device)
    static var gitBranch: String {
        #if DEBUG && targetEnvironment(simulator)
        return shell("git", "-C", sourceDirectory, "rev-parse", "--abbrev-ref", "HEAD") ?? "unknown"
        #else
        return "device"
        #endif
    }

    /// Get current git commit short hash
    static var gitCommit: String {
        #if DEBUG && targetEnvironment(simulator)
        return shell("git", "-C", sourceDirectory, "rev-parse", "--short", "HEAD") ?? "unknown"
        #else
        return "release"
        #endif
    }

    /// Source directory derived from #file at compile time
    private static let sourceDirectory: String = {
        // #file gives us the path to this source file at compile time
        // e.g., /Users/arach/dev/talkie/iOS/Talkie iOS/BuildInfo.swift
        let filePath = #file
        return (filePath as NSString).deletingLastPathComponent
    }()

    #if DEBUG && targetEnvironment(simulator)
    private static func shell(_ args: String...) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    #endif
}
